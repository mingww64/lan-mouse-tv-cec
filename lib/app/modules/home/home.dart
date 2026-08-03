import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lan_mouse_mobile/app/modules/home/widgets/home_connections.dart';

import 'package:lan_mouse_mobile/app/modules/home/widgets/home_general.dart';
import 'package:lan_mouse_mobile/app/modules/home/widgets/home_top.dart';
import 'package:lan_mouse_mobile/app/modules/home/widgets/home_tv_inputs.dart';
import 'package:url_launcher/url_launcher.dart';

class HomeView extends StatelessWidget {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            snap: true,
            title: Text(
              "Lan Mouse CEC",
              style: Theme.of(context).textTheme.titleMedium,
            ),
            elevation: 0,
            centerTitle: true,
            actions: [
              PopupMenuButton<_HomeMenuAction>(
                tooltip: 'Menu',
                icon: const Icon(Icons.menu_rounded),
                onSelected: (action) {
                  if (action == _HomeMenuAction.source) _openSource(context);
                  if (action == _HomeMenuAction.license) _showLicense(context);
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: _HomeMenuAction.source,
                    child: ListTile(
                      leading: Icon(Icons.code),
                      title: Text('Source code'),
                      subtitle: Text('github.com/mingww64/lan-mouse-tv-cec'),
                    ),
                  ),
                  PopupMenuDivider(),
                  PopupMenuItem(
                    value: _HomeMenuAction.license,
                    child: ListTile(
                      leading: Icon(Icons.gavel_outlined),
                      title: Text('License'),
                      subtitle: Text('GNU GPL v3.0'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final contentWidth =
                    constraints.maxWidth > 2600 ? 2600.0 : constraints.maxWidth;
                final wide = contentWidth >= 1000;
                final cardWidth = wide ? (contentWidth - 24) / 2 : contentWidth;
                return Padding(
                  padding: const EdgeInsets.fromLTRB(40, 28, 40, 48),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 2600),
                      child: Wrap(
                        spacing: 24,
                        runSpacing: 24,
                        children: [
                          SizedBox(width: contentWidth, child: const HomeTop()),
                          SizedBox(
                              width: cardWidth, child: const HomeTvInputs()),
                          SizedBox(
                              width: cardWidth, child: const HomeConnections()),
                          SizedBox(
                              width: cardWidth, child: const HomeGeneral()),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showLicense(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('GNU GPL v3.0'),
        content: const Text(
          'Lan Mouse CEC is free software licensed under the GNU General Public License, version 3. '
          'It is provided without warranty. The complete license and corresponding source are available from '
          'the Source code item in this menu.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close')),
        ],
      ),
    );
  }

  Future<void> _openSource(BuildContext context) async {
    const url = 'https://github.com/mingww64/lan-mouse-tv-cec';
    final opened =
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!opened) {
      await Clipboard.setData(const ClipboardData(text: url));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not open the browser. Source URL copied.')));
    }
  }
}

enum _HomeMenuAction { source, license }
