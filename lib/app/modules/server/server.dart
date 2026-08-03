import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lan_mouse_mobile/app/models/client.dart';
import 'package:lan_mouse_mobile/app/services/lan_mouse_server.dart';
import 'package:lan_mouse_mobile/app/services/tv_input_capture.dart';

class Server extends StatefulWidget {
  final Client client;

  const Server({super.key, required this.client});

  @override
  State<Server> createState() => _ServerState();
}

class _ServerState extends State<Server> {
  LanMouseServer lanMouseServer = LanMouseServer.instance;
  bool waitingForAck = false;
  StreamSubscription<void>? _captureEndedSubscription;
  bool _returningHome = false;

  @override
  void initState() {
    super.initState();
    _captureEndedSubscription =
        TvInputCapture.instance.onEnded.listen((_) => _returnToMainMenu());
    _activateProfileAndStart();
  }

  Future<void> _activateProfileAndStart() async {
    try {
      await TvInputCapture.instance.activateProfile(widget.client.storageKey);
      if (!mounted) return;
      enterClient();
      await TvInputCapture.instance.start();
    } catch (error) {
      _showErrorDialog(error.toString());
    }
  }

  void enterClient() async {
    setState(() {
      waitingForAck = true;
    });
    await lanMouseServer.enterClient(
      client: widget.client,
      onError: (String err) {
        _showErrorDialog(err);
      },
    );
    setState(() {
      waitingForAck = false;
    });
  }

  @override
  void dispose() {
    _captureEndedSubscription?.cancel();
    TvInputCapture.instance.stop();
    super.dispose();
    lanMouseServer.leaveClient();
  }

  void _returnToMainMenu() {
    if (_returningHome || !mounted) return;
    _returningHome = true;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _showErrorDialog(String error) {
    if (!context.mounted) return;
    showAdaptiveDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return AlertDialog.adaptive(
          title: const Text("Error"),
          content: Text(error),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context);
              },
              child: const Text("Ok"),
            )
          ],
        );
      },
    );
  }

  Future<void> _selectProfileTrigger() async {
    List<TvInputSource> inputs;
    String selected;
    try {
      inputs = await TvInputCapture.instance.getTvInputs();
      selected = await TvInputCapture.instance.getProfileTrigger();
    } catch (error) {
      _showErrorDialog('Could not query Android TV inputs: $error');
      return;
    }
    if (!mounted) return;
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Profile trigger input'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                    'Relay for this client only while this TV input is selected.'),
                const SizedBox(height: 12),
                Flexible(
                    child: RadioGroup<String>(
                        groupValue: selected,
                        onChanged: (value) =>
                            setDialogState(() => selected = value!),
                        child: ListView(
                          shrinkWrap: true,
                          children: [
                            for (final input in inputs)
                              RadioListTile<String>(
                                value: input.identifier,
                                title: Text(input.name),
                                subtitle: Text(input.tclArg.isEmpty
                                    ? input.identifier
                                    : '${input.identifier} • TCL arg1=${input.tclArg}'),
                              ),
                            if (inputs.isEmpty)
                              const Padding(
                                padding: EdgeInsets.all(8),
                                child: Text(
                                    'No physical TV inputs were reported by the TV Input Framework.'),
                              ),
                          ],
                        ))),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Save')),
          ],
        ),
      ),
    );
    if (save == true && selected.isNotEmpty) {
      await TvInputCapture.instance.setProfileTrigger(selected);
    }
  }

  Future<void> _configureCustomFallback() async {
    var fallback = await TvInputCapture.instance.getCustomFallback();
    var overlayPermission = await TvInputCapture.instance.canDrawOverlays();
    final controller = TextEditingController(text: fallback.command);
    if (!mounted) return;
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Non-TCL HDMI fallback'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Use universal HDMI detection'),
                  subtitle: const Text(
                      'For non-TCL TVs. TCL source broadcasts remain primary.'),
                  value: fallback.enabled,
                  onChanged: (enabled) => setDialogState(() {
                    fallback = CustomInputFallback(
                        enabled: enabled,
                        command: controller.text,
                        showOverlay: fallback.showOverlay);
                  }),
                ),
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Show source-ID overlay'),
                  subtitle: Text(overlayPermission
                      ? 'Permission granted. Shows HW<n> when the input changes.'
                      : 'Permission required to show HW<n> over the HDMI image.'),
                  value: fallback.showOverlay,
                  onChanged: (showOverlay) => setDialogState(() {
                    fallback = CustomInputFallback(
                      enabled: fallback.enabled,
                      command: controller.text,
                      showOverlay: showOverlay,
                    );
                  }),
                ),
                if (!overlayPermission)
                  TextButton.icon(
                    onPressed: () async {
                      await TvInputCapture.instance.requestOverlayPermission();
                      // Android returns here after Settings closes; refresh the
                      // displayed state instead of leaving a stale button.
                      final granted =
                          await TvInputCapture.instance.canDrawOverlays();
                      setDialogState(() => overlayPermission = granted);
                    },
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Grant overlay permission'),
                  ),
                if (fallback.enabled)
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('Advanced: custom detector command'),
                    subtitle: const Text(
                        'Default is dumpsys activity starter → HW<n>.'),
                    children: [
                      TextField(
                        controller: controller,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          hintText:
                              'Command that prints active or an HW<n> source ID',
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Save')),
          ],
        ),
      ),
    );
    final updated = CustomInputFallback(
        enabled: fallback.enabled,
        command: controller.text,
        showOverlay: fallback.showOverlay);
    controller.dispose();
    if (save == true) await TvInputCapture.instance.setCustomFallback(updated);
  }

  Future<void> _selectCaptureDevices() async {
    List<TvCaptureDevice> devices;
    Set<String> selected;
    try {
      devices = await TvInputCapture.instance.getInputDevices();
      selected = await TvInputCapture.instance.getCaptureDevices();
    } catch (error) {
      if (mounted) _showErrorDialog('Could not read TV input devices: $error');
      return;
    }
    // Never default to grabbing the TCL IR receiver or TV keypad.
    if (selected.isEmpty) {
      selected = devices
          .where((device) =>
              (device.name.contains('Keyboard') ||
                  device.name.contains('Mouse')) &&
              !device.name.startsWith('sim-'))
          .map((device) => device.path)
          .toSet();
    }
    if (!mounted) return;
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('CEC capture devices'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                    'Selected devices are forwarded now and will be exclusively grabbed when CEC capture mode is enabled.'),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final device in devices)
                        CheckboxListTile(
                          value: selected.contains(device.path),
                          title: Text(device.name),
                          subtitle: Text(device.path),
                          onChanged: (checked) => setDialogState(() {
                            if (checked == true) {
                              selected.add(device.path);
                            } else {
                              selected.remove(device.path);
                            }
                          }),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Save selection')),
          ],
        ),
      ),
    );
    if (save == true) await TvInputCapture.instance.setCaptureDevices(selected);
  }

  @override
  void setState(VoidCallback fn) {
    if (mounted) super.setState(fn);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Lan Mouse CEC',
                style: Theme.of(context).textTheme.titleMedium),
            Text(widget.client.toString(),
                style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
        elevation: 0,
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Custom input-source fallback',
            onPressed: _configureCustomFallback,
            icon: const Icon(Icons.settings_input_component),
          ),
          IconButton(
            tooltip: 'Select profile trigger input',
            onPressed: _selectProfileTrigger,
            icon: const Icon(Icons.input),
          ),
          IconButton(
            tooltip: 'Select CEC capture devices',
            onPressed: _selectCaptureDevices,
            icon: const Icon(Icons.keyboard),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (waitingForAck)
                const CircularProgressIndicator.adaptive()
              else
                const Icon(Icons.tv, size: 64),
              const SizedBox(height: 24),
              const Text('CEC-style relay enabled',
                  textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ValueListenableBuilder<RelayConnectionStatus>(
                valueListenable: lanMouseServer.status,
                builder: (context, status, _) {
                  final (label, color) = switch (status) {
                    RelayConnectionStatus.connecting => (
                        'Connecting to ${widget.client.host}…',
                        Colors.amber
                      ),
                    RelayConnectionStatus.connected => (
                        'Connected — this is the only active relay client',
                        Colors.green
                      ),
                    RelayConnectionStatus.error => (
                        'Connection error: ${lanMouseServer.statusDetail ?? 'unknown error'}',
                        Colors.red
                      ),
                    RelayConnectionStatus.disconnected => (
                        'Disconnected',
                        Colors.grey
                      ),
                  };
                  return Text(label,
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(color: color, fontWeight: FontWeight.w600));
                },
              ),
              const SizedBox(height: 12),
              const Text(
                'Capture ready  •  Exit: Ctrl + Alt + Shift + Z',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
