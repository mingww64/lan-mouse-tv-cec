import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lan_mouse_mobile/app/services/lan_mouse_server.dart';

class HomeGeneral extends StatefulWidget {
  const HomeGeneral({super.key});

  @override
  State<HomeGeneral> createState() => _HomeGeneralState();
}

class _HomeGeneralState extends State<HomeGeneral> {
  final LanMouseServer lanMouseServer = LanMouseServer.instance;
  final portController = TextEditingController();
  List<InternetAddress> interfaces = const [];
  String fingerprint = '';

  @override
  void initState() {
    super.initState();
    portController.text = lanMouseServer.defaultClient.port.toString();
    _refreshData();
  }

  @override
  void dispose() {
    portController.dispose();
    super.dispose();
  }

  Future<void> _refreshData() async {
    try {
      final addresses = await lanMouseServer.localBindAddresses();
      if (addresses.isNotEmpty &&
          !addresses.any((address) =>
              address.address == lanMouseServer.defaultClient.host)) {
        lanMouseServer.defaultClient.host = addresses.first.address;
      }
      if (mounted) setState(() => interfaces = addresses);
    } catch (_) {}
    try {
      final data = await lanMouseServer.getFingerprint();
      if (mounted) setState(() => fingerprint = data ?? 'Unavailable');
    } catch (_) {
      if (mounted) setState(() => fingerprint = 'Unavailable');
    }
  }

  Future<void> _selectInterface() async {
    if (interfaces.isEmpty) {
      await _refreshData();
      if (interfaces.isEmpty || !mounted) return;
    }
    var selected = lanMouseServer.defaultClient.host;
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Bind interface'),
          content: SizedBox(
            width: 520,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Choose an IPv4 address assigned to this TV.'),
              const SizedBox(height: 12),
              Flexible(
                child: RadioGroup<String>(
                  groupValue: selected,
                  onChanged: (value) => setDialogState(() => selected = value!),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final address in interfaces)
                        RadioListTile<String>(
                          value: address.address,
                          title: Text(address.address),
                          subtitle: const Text('Local interface'),
                        ),
                    ],
                  ),
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Use address')),
          ],
        ),
      ),
    );
    if (save == true && selected.isNotEmpty) {
      setState(() => lanMouseServer.defaultClient.host = selected);
    }
  }

  Future<void> _editPort() async {
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Relay port'),
        content: TextField(
          controller: portController,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(helperText: '1–65535'),
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
    );
    final port = int.tryParse(portController.text);
    if (save == true && port != null && port >= 1 && port <= 65535) {
      setState(() => lanMouseServer.defaultClient.port = port);
    }
  }

  void _copy(String value, String label) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$label copied')));
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('Network', style: Theme.of(context).textTheme.titleSmall),
            const Spacer(),
            IconButton(
                tooltip: 'Refresh local interfaces',
                onPressed: _refreshData,
                icon: const Icon(Icons.refresh)),
          ]),
          Card(
            child: Column(children: [
              ListTile(
                minVerticalPadding: 14,
                leading: const Icon(Icons.router_outlined),
                title: const Text('Bind interface'),
                subtitle: Text(lanMouseServer.defaultClient.host),
                trailing: const Icon(Icons.chevron_right),
                onTap: _selectInterface,
              ),
              const Divider(height: 1),
              ListTile(
                minVerticalPadding: 14,
                leading: const Icon(Icons.settings_ethernet),
                title: const Text('Relay port'),
                subtitle: Text(portController.text),
                trailing: const Icon(Icons.chevron_right),
                onTap: _editPort,
              ),
              const Divider(height: 1),
              ListTile(
                minVerticalPadding: 14,
                leading: const Icon(Icons.fingerprint),
                title: const Text('Certificate fingerprint'),
                subtitle: Text(fingerprint,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: const Icon(Icons.copy),
                onTap: () => _copy(fingerprint, 'Fingerprint'),
              ),
            ]),
          ),
        ],
      );
}
