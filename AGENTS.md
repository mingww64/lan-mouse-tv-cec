# Lan Mouse TV CEC — Agent Guide

## Scope

This is an Android TV client for the stock Lan Mouse Windows receiver. It
captures selected local input devices on a rooted TCL QM850G and relays them
only while the configured PC HDMI input is selected. Do not modify the Windows
Lan Mouse receiver or TV partitions/boot images as part of this project.

## Target and safety

- Device: TCL QM850G / `G05_4K_US`, Android 11, ARMv7 (`armeabi-v7a`).
- Network ADB: `192.168.1.100:5555`.
- The TV is rooted and runs ShizukuPlus. Treat root commands and
  `EVIOCGRAB` as high-risk: grab only user-selected USB keyboard/mouse devices.
- Never grab TCL IR, TV keypad, power, sleep, wake, restart, or screen-lock
  inputs. The escape chord is Ctrl+Alt+Shift+Z.
- A device's `/dev/input/eventN` number is transient. Store/resolve selected
  device names as well as paths.

## Architecture

- Flutter UI and DTLS transport: `lib/` and `rust/`.
- Native root grabber: `native/input_grab_bridge.c`, packaged as
  `android/app/src/main/assets/input_grab_bridge`.
- Android/Shizuku integration and HDMI source gate:
  `android/app/src/main/kotlin/com/rohit/lan_mouse_mobile/`.
- TCL broadcast `com.tcl.inputsourcechanged`: HDMI1=`arg1:8`, HDMI2=`9`,
  HDMI3=`10`, HDMI4=`11`, AV=`3`, Android=`17`. The PC input mapping is
  user-configured: it accepts either a TCL argument (`8` / `arg1=8`) or a
  `HW…` hardware ID shown by the source overlay.
- thedjchi/Shizuku sends the standard
  `moe.shizuku.api.BinderContainer`/`moe.shizuku.privileged.api` binder
  payload, which is compatible with the official 13.1.5 API dependency.
  Keep the legacy `rikka.shizuku.BinderContainer` and
  `af.shizuku.api.BinderContainer` compatibility parcelables only while the
  older ShizukuPlus server remains supported.

## Build and deploy

From the repository root in PowerShell:

```powershell
$env:PATH = "$env:USERPROFILE\.cargo\bin;C:\Users\mingww64\Documents\QM8\tools\flutter\bin;" + $env:PATH
flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml
Push-Location rust
cargo ndk -t armeabi-v7a -o ..\android\app\src\main\jniLibs build --release
Pop-Location
flutter build apk --release --target-platform android-arm
$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
& $adb -s 192.168.1.100:5555 install -r build\app\outputs\flutter-apk\app-release.apk
& $adb -s 192.168.1.100:5555 shell am start -S -f 0x10008000 -n com.rohit.lan_mouse_mobile/.MainActivity
```

- Do not launch the updated APK with `monkey`. On this TCL build, if Android's
  overlay-permission Settings page was previously open, package replacement
  resumes that external activity. The explicit `am start` flags create a clean
  app task and prevent the stale page from reappearing.

- After any `flutter_rust_bridge` upgrade, regenerate bindings and rebuild the
  ARMv7 library before installing. Runtime and generated codegen versions must
  match or Flutter displays a blank screen at startup.
- Current Android baseline: AGP 8.11.1, Gradle 8.14, Kotlin 2.2.20.
- Validate Dart code with `flutter analyze lib`. The vendored CargoKit tree is
  not a useful analyzer target.

## Runtime diagnostics

```powershell
& $adb -s 192.168.1.100:5555 logcat -s TvInputRelay
& $adb -s 192.168.1.100:5555 shell getevent -il
```

- Enable verbose relay logging only during input debugging; it logs every raw
  key event.
- `Shizuku getevent: open ... No such file` means the saved event path is
  stale or device unplugged. Reopen the selector and save it so name-based
  resolution can be recorded.
- Scroll must use Lan Mouse's discrete-120 event. Do not send raw Linux wheel
  detents as continuous pointer-axis values on Windows.
- A normal CEC exit must leave the sole DTLS client and return the UI to the
  main menu, where a new single client session can be started.
- Input mapping, custom fallback, capture-device selection, explicit-grab
  confirmation, and verbose logging are saved per Windows-client profile.
  The first profile inherits settings from earlier app versions.
- TCL source broadcasts are primary. A user-supplied command fallback is
  opt-in and intended only for non-TCL TVs; it must print exactly `active`.
