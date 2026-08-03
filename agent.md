# Lan Mouse TV CEC — Agent Entry Point

Repository: <https://github.com/mingww64/lan-mouse-tv-cec>

Read [AGENTS.md](AGENTS.md) in full before changing capture, Shizuku,
TV-input gating, profiles, or deployment behavior. In particular:

- This is an Android TV client for the stock Lan Mouse desktop receiver; do
  not change the Windows receiver or TV partitions.
- The capture bridge uses privileged `EVIOCGRAB` only for explicitly selected
  USB input devices. Never grab TCL IR, power, sleep, wake, restart, or lock
  devices. The emergency exit chord is Ctrl+Alt+Shift+Z.
- TV inputs are discovered through Android's TV Input Framework. Profiles
  choose a discovered `HW…` input as their relay trigger.
- Build the ARMv7 Rust library before building the APK, and use the explicit
  `am start` deployment command rather than `monkey` after an ADB update.
