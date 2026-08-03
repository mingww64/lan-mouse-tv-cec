import 'package:flutter/material.dart';
import 'package:lan_mouse_mobile/app/services/tv_input_capture.dart';

/// Global TV framework catalog and diagnostic settings. Client-specific input
/// selection happens after choosing a connection.
class HomeTvInputs extends StatefulWidget {
  const HomeTvInputs({super.key});

  @override
  State<HomeTvInputs> createState() => _HomeTvInputsState();
}

class _HomeTvInputsState extends State<HomeTvInputs> {
  List<TvInputSource>? _inputs;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _discover();
  }

  Future<void> _discover() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final inputs = await TvInputCapture.instance.getTvInputs();
      if (mounted) setState(() => _inputs = inputs);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _configureVerboseLogging() async {
    var enabled = await TvInputCapture.instance.getVerboseLogging();
    if (!mounted) return;
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Verbose relay logging'),
          content: SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Log every captured key'),
            subtitle: const Text(
                'Global diagnostic setting; use only while debugging.'),
            value: enabled,
            onChanged: (value) => setDialogState(() => enabled = value),
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
    if (save == true) await TvInputCapture.instance.setVerboseLogging(enabled);
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('TV input sources',
                style: Theme.of(context).textTheme.titleSmall),
            const Spacer(),
            IconButton(
                tooltip: 'Refresh input sources',
                onPressed: _loading ? null : _discover,
                icon: const Icon(Icons.refresh)),
          ]),
          if (_loading)
            const Padding(
                padding: EdgeInsets.all(12), child: LinearProgressIndicator()),
          if (_error != null)
            Padding(
                padding: const EdgeInsets.only(top: 8),
                child:
                    Text(_error!, style: const TextStyle(color: Colors.red))),
          if (_inputs != null)
            Card(
              margin: const EdgeInsets.only(top: 12),
              child: Column(children: [
                for (final input in _inputs!)
                  ListTile(
                    minVerticalPadding: 14,
                    leading: const Icon(Icons.input_outlined),
                    title: Text(input.name),
                    subtitle: Text(input.tclArg.isEmpty
                        ? input.identifier
                        : '${input.identifier} • arg1=${input.tclArg}'),
                  ),
                if (_inputs!.isEmpty)
                  const ListTile(
                    minVerticalPadding: 14,
                    leading: Icon(Icons.tv_off_outlined),
                    title: Text('No physical inputs found.'),
                  ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.bug_report_outlined),
                  title: const Text('Verbose relay logging'),
                  subtitle: const Text('Global diagnostic setting'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _configureVerboseLogging,
                ),
              ]),
            ),
        ],
      );
}
