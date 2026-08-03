# Lan Mouse TV CEC

An Android TV client built from the GPL-3.0 [Lan Mouse Mobile](https://github.com/rohitsangwan01/lan-mouse-mobile) proof of concept. It uses that project's existing Lan Mouse DTLS protocol implementation, so the desktop runs the standard [Lan Mouse](https://github.com/feschber/lan-mouse) application—there is no custom Windows receiver.

On a rooted TCL QM850G, the app observes the TV's physical key and relative-mouse events through `getevent`, then forwards them to the selected Lan Mouse desktop **only while a configured HDMI input is active**. The TV still receives all of its own input, making this behave like a CEC-style remote relay rather than taking over the device.

## Connect and configure

1. Run Lan Mouse on the desktop, add the TV's IP as a client, and authorize the TV fingerprint. Lan Mouse uses UDP port `4242` by default.
2. Install and open this APK on the TV. Add the desktop address using the original Lan Mouse Mobile connection screen.
3. On the connection page, select the HDMI settings icon. The relay starts fail-closed with `echo inactive`.
4. With the PC's HDMI input selected, obtain the TV input-service state over ADB:

   ```sh
   adb shell su -c 'dumpsys tv_input > /data/local/tmp/tv-input-state.txt'
   adb pull /data/local/tmp/tv-input-state.txt
   ```

5. Set the HDMI gate to a command that emits exactly `active` only when that input is selected. Test the command at an ADB shell first. Switch to another source and confirm the relay stops before depending on it.

## Input and safety boundaries

- Forwarded: standard keyboard/navigation keys, mouse movement, wheel, and left/right/middle buttons.
- Excluded: TV power, volume, source, settings, and vendor-specific keys.
- The capture service is foreground and does not use `EVIOCGRAB`; input continues to reach the TV.
- Root is required to read `/dev/input/event*`. Denying root simply prevents the relay from starting.
- Lan Mouse provides the encrypted desktop transport and its existing desktop authorization flow. The HDMI gate executes locally as root, so configure it only with a command you trust.

## Build

```sh
flutter pub get
flutter build apk --release
```

The Android TV launcher intent and Android 11-compatible foreground service are in the Android app module. The TV capture bridge is native Kotlin; it sends events only to the Flutter/Rust Lan Mouse client.
