#include <errno.h>
#include <fcntl.h>
#include <linux/input.h>
#include <poll.h>
#include <signal.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

static volatile sig_atomic_t running = 1;
static bool ctrl, alt, shift;

/*
 * Most keyboards provide Linux evdev KEY_LEFTMETA (125) directly.  Some
 * Android TV input stacks, however, translate the USB HID Left/Right GUI
 * usages (0x700e3/0x700e7) to a local key such as Home before delivering the
 * event. Preserve the physical HID meaning when the accompanying MSC_SCAN
 * event makes that unambiguous. Lan Mouse uses Linux evdev codes on the wire,
 * where 125/126 are the two Meta keys.
 */
static unsigned short normalized_key(unsigned short code, unsigned int scan) {
    /* The HID usage is definitive even when Android mapped it to Home, Shift,
     * or another framework-specific key code. */
    if (scan == 0x700e3) return KEY_LEFTMETA;
    if (scan == 0x700e7) return KEY_RIGHTMETA;
    return code;
}

static void stop(int ignored) { (void)ignored; running = 0; }
static void modifier(unsigned short code, int value) {
    bool down = value != 0;
    if (code == KEY_LEFTCTRL || code == KEY_RIGHTCTRL) ctrl = down;
    if (code == KEY_LEFTALT || code == KEY_RIGHTALT) alt = down;
    if (code == KEY_LEFTSHIFT || code == KEY_RIGHTSHIFT) shift = down;
}

int main(int argc, char **argv) {
    if (argc < 2) { fprintf(stderr, "no event devices selected\n"); return 2; }
    signal(SIGTERM, stop); signal(SIGINT, stop);
    setvbuf(stdout, NULL, _IONBF, 0);
    struct pollfd *polls = calloc((size_t)(argc - 1), sizeof(*polls));
    const char **paths = calloc((size_t)(argc - 1), sizeof(*paths));
    unsigned int *last_scan = calloc((size_t)(argc - 1), sizeof(*last_scan));
    int count = 0;
    for (int i = 1; i < argc; ++i) {
        int fd = open(argv[i], O_RDONLY | O_NONBLOCK | O_CLOEXEC);
        if (fd < 0) { fprintf(stderr, "open %s: %s\n", argv[i], strerror(errno)); continue; }
        if (ioctl(fd, EVIOCGRAB, 1) != 0) { fprintf(stderr, "grab %s: %s\n", argv[i], strerror(errno)); close(fd); continue; }
        polls[count].fd = fd; polls[count].events = POLLIN; paths[count++] = argv[i];
    }
    if (!count) { fprintf(stderr, "could not grab any selected device\n"); return 3; }
    while (running) {
        if (poll(polls, (nfds_t)count, 250) <= 0) continue;
        for (int i = 0; i < count; ++i) {
            if (!(polls[i].revents & POLLIN)) continue;
            struct input_event event;
            while (read(polls[i].fd, &event, sizeof(event)) == sizeof(event)) {
                if (event.type == EV_MSC && event.code == MSC_SCAN) {
                    last_scan[i] = (unsigned int)event.value;
                }
                if (event.type == EV_KEY) {
                    unsigned short code = normalized_key(event.code, last_scan[i]);
                    modifier(code, event.value);
                    if (code == KEY_Z && event.value == 1 && ctrl && alt && shift) {
                        puts("@CEC_EXIT"); running = 0; break;
                    }
                    if (code != event.code) {
                        fprintf(stderr, "normalized HID scan %08x: key %04x -> %04x\\n",
                                last_scan[i], event.code, code);
                        event.code = code;
                    }
                }
                printf("%s: %04x %04x %08x\n", paths[i], event.type, event.code, (unsigned int)event.value);
            }
        }
    }
    for (int i = 0; i < count; ++i) { ioctl(polls[i].fd, EVIOCGRAB, 0); close(polls[i].fd); }
    free(polls); free(paths); free(last_scan); return 0;
}
