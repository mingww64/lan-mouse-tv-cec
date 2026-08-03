# Lan Mouse TV CEC

An Android TV client for the stock [Lan Mouse](https://github.com/feschber/lan-mouse)
desktop receiver. It relays selected physical keyboard and mouse devices to
one Lan Mouse desktop only while a chosen TV input is active, creating a
CEC-style experience without modifying the desktop receiver.

This project is a GPL-3.0 derivative of
[Lan Mouse Mobile](https://github.com/rohitsangwan01/lan-mouse-mobile).

## TV interface

The Android TV home screen keeps connection, TV-input, and capture controls
available from the D-pad. Profiles provide a separate, focused relay setup for
each Lan Mouse client.

<p align="center">
  <img src="screenshots/light.png" alt="Lan Mouse CEC TV interface" width="360">
</p>

## TV banner

The Leanback / Projectivy launcher banner is a 16:9 illustration of the
keyboard-and-mouse relay crossing HDMI through CEC-style input switching.

<p align="center">
  <img src="android/app/src/main/res/drawable-nodpi/tv_banner.jpg" alt="Lan Mouse CEC Android TV banner" width="760">
</p>

This is the exact launcher asset packaged in the APK.

## Features

- Shizuku-backed privileged native `getevent`/`EVIOCGRAB` capture.
- Explicit USB keyboard and mouse device selection.
- Live TV, AV, and HDMI discovery through Android's TV Input Framework
  (`dumpsys tv_input`).
- One profile per saved Lan Mouse client, with its own TV-input trigger and
  capture-device selection. Only one relay connection is active at a time.
- TCL source-change broadcasts as the primary gate; opt-in command fallback
  and source-ID overlay for non-TCL TVs.
- Relative mouse movement, high-resolution scrolling, raw-event diagnostics,
  and a Ctrl+Alt+Shift+Z emergency capture exit.

## Requirements

- Rooted Android TV with Shizuku running and permission granted to this app.
- A Lan Mouse desktop receiver on the same network.
- ARMv7 support for the included build instructions (validated on a TCL
  QM850G running Android 11).

## Configure the TV

1. Add the TV's LAN address as a Lan Mouse client on the desktop receiver and
   authorize the fingerprint shown by this app.
2. Open **TV input sources** on the home screen and discover the TV Input
   Framework catalog.
3. Add or select a Lan Mouse client.
4. In the relay screen, select the profile's trigger input and safe USB
   devices under **CEC capture devices**.
5. Start capture. Input is forwarded only while the selected TV input is
   active and the desktop client has acknowledged the connection.

The **Network** card only permits binding to an IPv4 address currently assigned
to the TV. The relay validates the bind address and port before connecting.

## Build and install

From PowerShell at the repository root:

```powershell
$env:PATH = "$env:USERPROFILE\.cargo\bin;C:\path\to\flutter\bin;" + $env:PATH
flutter pub get
flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml
Push-Location rust
cargo ndk -t armeabi-v7a -t arm64-v8a -t x86_64 -o ..\android\app\src\main\jniLibs build --release
Pop-Location
flutter build apk --release --target-platform android-arm

$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
& $adb -s <TV-IP>:5555 install -r build\app\outputs\flutter-apk\app-release.apk
& $adb -s <TV-IP>:5555 shell am start -S -f 0x10008000 -n com.rohit.lan_mouse_mobile/.MainActivity
```

For a universal release APK, build all packaged ABIs instead:

```powershell
flutter build apk --release --target-platform android-arm,android-arm64,android-x64
```

Do not use `monkey` to launch after an update. TCL can resume a stale Android
overlay-permission Settings page after package replacement; the explicit
`am start` command creates a clean task.

## Diagnostics

```powershell
& $adb -s <TV-IP>:5555 logcat -s TvInputRelay
& $adb -s <TV-IP>:5555 shell dumpsys tv_input
& $adb -s <TV-IP>:5555 shell getevent -il
```

Enable verbose logging only while mapping input devices; it logs every captured
raw key event.

## Safety

Exclusively grab only devices you explicitly select. Never select the TCL IR
receiver, TV keypad, power, sleep, wake, restart, or screen-lock inputs. The
app filters safety-critical keys, and the native exit chord is
**Ctrl+Alt+Shift+Z**.

## License

[GNU General Public License v3.0](LICENSE).
