# Lan Mouse TV CEC — Agent Entry Point

Repository: <https://github.com/mingww64/lan-mouse-tv-cec>

Read [AGENTS.md](AGENTS.md) in full before changing capture, Shizuku,
TV-input gating, profiles, or deployment behavior. In particular:

- This is an Android TV client for the stock Lan Mouse desktop receiver; do
  not change the Windows receiver or TV partitions.
- The capture bridge uses privileged `EVIOCGRAB` only for explicitly selected
  USB input devices. Never grab TCL IR, power, sleep, wake, restart, or lock
  devices. Ctrl+Alt+Shift+Z releases the active grab but keeps the relay
  service/session alive; capture resumes only after the trigger input is left
  and selected again. Use **End capture** to stop the service.
- TV inputs are discovered through Android's TV Input Framework. Profiles
  choose a discovered `HW…` input as their relay trigger.
- Build the Rust libraries for every intended APK ABI before building the APK,
  and use the explicit `am start` deployment command rather than `monkey`
  after an ADB update.
- The Android TV / Projectivy artwork is the 16:9 JPEG at
  `android/app/src/main/res/drawable-nodpi/tv_banner.jpg`. It is declared on
  both the application and `MainActivity` in `AndroidManifest.xml`; retain
  both declarations so Leanback launchers can resolve it consistently.

## Documentation and release checks

- Keep `README.md`'s Android TV home/client screenshots and built-in **TV
  banner** preview in sync with the shipped experience when those assets
  change.
- Verify a banner build with `aapt dump badging <apk>`: the
  `leanback-launchable-activity` must report a `banner` resource.
- A universal release builds `armeabi-v7a`, `arm64-v8a`, and `x86_64`; do not
  bump the app version unless the release request explicitly calls for it.
