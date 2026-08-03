import 'dart:async';
import 'package:flutter/services.dart';
import 'package:lan_mouse_mobile/app/models/input_event.dart';
import 'package:lan_mouse_mobile/app/models/keyboard_event.dart' as lan_mouse;
import 'package:lan_mouse_mobile/app/models/pointer_event.dart';
import 'package:lan_mouse_mobile/app/services/lan_mouse_server.dart';

/// Native, root-backed TV event capture that supplies events to Lan Mouse's
/// existing DTLS connection. The HDMI source decision remains native so that
/// no event is forwarded while the selected input is not the PC.
class TvInputCapture {
  TvInputCapture._();
  static final instance = TvInputCapture._();
  static const _control = MethodChannel('lan_mouse_tv_cec/control');
  static const _events = EventChannel('lan_mouse_tv_cec/input_events');
  StreamSubscription<dynamic>? _subscription;
  final _ended = StreamController<void>.broadcast();

  /// Fires when the exclusive capture bridge exits via its CEC escape chord.
  Stream<void> get onEnded => _ended.stream;

  Future<void> activateProfile(String profileId) =>
      _control.invokeMethod<void>('activateProfile', profileId);

  Future<void> start() async {
    _subscription ??= _events.receiveBroadcastStream().listen(_onEvent);
    await _control.invokeMethod<void>('start');
  }

  Future<void> stop() async {
    await _control.invokeMethod<void>('stop');
    await _subscription?.cancel();
    _subscription = null;
  }

  Future<CustomInputFallback> getCustomFallback() async {
    final raw =
        await _control.invokeMapMethod<String, dynamic>('getCustomFallback') ??
            const <String, dynamic>{};
    return CustomInputFallback(
      enabled: raw['enabled'] == true,
      command: raw['command'] as String? ??
          "dumpsys activity starter | grep -o 'HW[0-9]*' | head -n 1",
      showOverlay: raw['showOverlay'] != false,
    );
  }

  Future<void> setCustomFallback(CustomInputFallback fallback) =>
      _control.invokeMethod<void>('setCustomFallback', {
        'enabled': fallback.enabled,
        'command': fallback.command,
        'showOverlay': fallback.showOverlay,
      });

  Future<bool> canDrawOverlays() async =>
      (await _control.invokeMethod<bool>('canDrawOverlays')) ?? false;

  Future<void> requestOverlayPermission() =>
      _control.invokeMethod<void>('requestOverlayPermission');

  Future<List<TvInputSource>> getTvInputs() async {
    final values =
        await _control.invokeListMethod<dynamic>('getTvInputs') ?? const [];
    return values.whereType<Map>().map((value) {
      final raw = Map<String, dynamic>.from(value);
      return TvInputSource(
          name: raw['name'] as String,
          identifier: raw['identifier'] as String,
          tclArg: raw['tclArg'] as String? ?? '');
    }).toList();
  }

  Future<String> getProfileTrigger() async =>
      (await _control.invokeMethod<String>('getProfileTrigger')) ?? '';

  Future<void> setProfileTrigger(String identifier) =>
      _control.invokeMethod<void>('setProfileTrigger', identifier);

  Future<List<TvCaptureDevice>> getInputDevices() async {
    final values =
        await _control.invokeListMethod<dynamic>('getInputDevices') ?? const [];
    return values.whereType<Map>().map((raw) {
      final item = Map<String, dynamic>.from(raw);
      return TvCaptureDevice(
          path: item['path'] as String, name: item['name'] as String);
    }).toList();
  }

  Future<Set<String>> getCaptureDevices() async =>
      ((await _control.invokeListMethod<String>('getCaptureDevices')) ??
              const [])
          .toSet();

  Future<void> setCaptureDevices(Set<String> devices) =>
      _control.invokeMethod<void>('setCaptureDevices', devices.toList());

  Future<bool> getVerboseLogging() async =>
      (await _control.invokeMethod<bool>('getVerboseLogging')) ?? false;

  Future<void> setVerboseLogging(bool enabled) =>
      _control.invokeMethod<void>('setVerboseLogging', enabled);

  void _onEvent(dynamic raw) {
    if (raw is! Map) return;
    final event = Map<String, dynamic>.from(raw);
    final type = event['type'];
    if (type is! String) return;
    final server = LanMouseServer.instance;
    switch (type) {
      case 'exit':
        // Native bridge consumed Ctrl+Alt+Shift+Z, released EVIOCGRAB, and
        // stopped the service. Closing the DTLS sender also releases any
        // modifiers that Windows may have seen before the chord completed.
        server.leaveClient();
        _ended.add(null);
        break;
      default:
        final code = event['code'];
        final value = event['value'];
        if (code == null || value is! int) return;
        switch (type) {
          case 'key':
            final key = int.tryParse('$code', radix: 16);
            if (key != null && (value == 0 || value == 1 || value == 2)) {
              server.sendInputEvent(
                  lan_mouse.KeyEvent(key: key, down: value != 0));
            }
            break;
          case 'button':
            final button = ButtonType.fromEvdev('$code');
            if (button != null && (value == 0 || value == 1)) {
              server.sendInputEvent(
                  ButtonEvent(button: button, down: value == 1));
            }
            break;
          case 'mouse':
            final dx = int.tryParse('$code');
            if (dx != null) {
              server.sendInputEvent(
                  MotionEvent(dx: dx.toDouble(), dy: value.toDouble()));
            }
            break;
          case 'wheel120':
            final axis = int.tryParse('$code');
            if (axis != null && (axis == 0 || axis == 1)) {
              server.sendInputEvent(
                  AxisDiscrete120Event(axis: axis, value: value));
            }
            break;
        }
    }
  }
}

class TvCaptureDevice {
  final String path;
  final String name;
  const TvCaptureDevice({required this.path, required this.name});
}

class CustomInputFallback {
  final bool enabled;
  final String command;
  final bool showOverlay;
  const CustomInputFallback(
      {required this.enabled,
      required this.command,
      required this.showOverlay});
}

class TvInputSource {
  final String name;
  final String identifier;
  final String tclArg;
  const TvInputSource(
      {required this.name, required this.identifier, required this.tclArg});
}
