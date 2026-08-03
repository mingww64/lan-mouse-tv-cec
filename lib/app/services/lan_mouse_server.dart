import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:lan_mouse_mobile/app/models/client.dart';
import 'package:lan_mouse_mobile/app/models/event_type.dart';
import 'package:lan_mouse_mobile/app/models/input_event.dart';
import 'package:lan_mouse_mobile/app/rust/api/lan_mouse_server.dart' as rust;
import 'package:path_provider/path_provider.dart';

enum RelayConnectionStatus { disconnected, connecting, connected, error }

class LanMouseServer {
  LanMouseServer._privateConstructor();
  static final LanMouseServer instance = LanMouseServer._privateConstructor();

  String? _tempPath;
  rust.SenderWrapper? _sender;
  StreamSubscription? _streamSubscription;
  bool _remoteInputActive = false;
  final ValueNotifier<RelayConnectionStatus> status =
      ValueNotifier(RelayConnectionStatus.disconnected);
  String? statusDetail;
  Client defaultClient = Client(host: "0.0.0.0", port: 4242);

  /// Addresses actually assigned to this device. A relay must bind to one of
  /// these rather than an arbitrary reachable LAN address.
  Future<List<InternetAddress>> localBindAddresses() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
      includeLinkLocal: false,
    );
    final seen = <String>{};
    return [
      for (final interface in interfaces)
        for (final address in interface.addresses)
          if (seen.add(address.address)) address,
    ];
  }

  Future<String?> validateBindAddress() async {
    final address = InternetAddress.tryParse(defaultClient.host);
    if (address == null || address.type != InternetAddressType.IPv4) {
      return 'Choose a valid IPv4 interface address.';
    }
    if (defaultClient.port < 1 || defaultClient.port > 65535) {
      return 'Relay port must be between 1 and 65535.';
    }
    final local = await localBindAddresses();
    if (!local.any((item) => item.address == address.address)) {
      return 'The selected bind address is no longer available.';
    }
    return null;
  }

  Future<String> get _basePath async {
    if (_tempPath == null) {
      final Directory tempDir = await getTemporaryDirectory();
      _tempPath = tempDir.path;
    }
    return _tempPath!;
  }

  Future<String?> getFingerprint() async =>
      rust.getFingerprint(path: await _basePath);

  Future<void> enterClient({
    required Client client,
    required Function(String) onError,
  }) async {
    // The wire protocol has one active target. Tear down a prior session
    // before creating a new DTLS sender so input cannot reach two desktops.
    final bindError = await validateBindAddress();
    if (bindError != null) {
      status.value = RelayConnectionStatus.error;
      statusDetail = bindError;
      onError(bindError);
      return;
    }
    await leaveClient();
    status.value = RelayConnectionStatus.connecting;
    statusDetail = '${client.host}:${client.port}';
    var (sender, receiver) = await rust.createU8Channel();
    _sender = sender;

    Stream<Uint8List> stream = rust.connect(
      basePath: await _basePath,
      ipAddr: defaultClient.host,
      port: defaultClient.port,
      targetAddr: client.host,
      targetPort: client.port,
      rx: receiver,
    );

    _streamSubscription = stream.listen((data) {
      if (data.isEmpty) return;
      var eventType = EventType.fromEvent(data.first);
      print("Client: EventType: ${eventType.name}, $data");
      if (eventType == EventType.Ping) {
        _sendEventToActiveClient(EventType.Pong);
      }
      if (eventType == EventType.Ack) {
        _remoteInputActive = true;
        status.value = RelayConnectionStatus.connected;
      }
    }, onError: (err) {
      _remoteInputActive = false;
      status.value = RelayConnectionStatus.error;
      statusDetail = err.toString();
      onError(err.toString());
    }, onDone: () {
      if (status.value != RelayConnectionStatus.disconnected) {
        _remoteInputActive = false;
        status.value = RelayConnectionStatus.disconnected;
      }
    });

    // Lan Mouse receivers deliberately discard input until this transition has
    // been acknowledged. The old mobile proof-of-concept never sent it.
    _sendEventToActiveClient(EventType.Enter, data: EventType.serial(0));
  }

  /// Tell the receiver to release this peer before closing DTLS. Sending only
  /// the channel-close marker leaves Windows' emulation watchdog waiting for
  /// a response and produces repeated "releasing keys ... not responding"
  /// warnings.
  Future<void> leaveClient() async {
    final sender = _sender;
    if (sender != null) {
      try {
        await sender
            .send(data: [EventType.Leave.index, ...EventType.serial(0)]);
        // The Rust connection loop serializes this marker after the Leave;
        // give DTLS a brief opportunity to put the datagram on the wire.
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await sender.send(data: []);
      } catch (_) {
        // The receiver may already be gone; local teardown still proceeds.
      }
    }
    _streamSubscription?.cancel();
    _sender = null;
    _remoteInputActive = false;
    status.value = RelayConnectionStatus.disconnected;
    statusDetail = null;
  }

  void sendInputEvent(InputEvent inputEvent) {
    if (!_remoteInputActive) return;
    _sendEventToActiveClient(
      inputEvent.type,
      data: inputEvent.buffer,
    );
  }

  /// Send events to active client
  void _sendEventToActiveClient(
    EventType type, {
    List<int> data = const [],
  }) {
    _sender?.send(data: [type.index, ...data]);
  }
}
