import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lan_mouse_mobile/app/modules/home/widgets/home_connections.dart';

import 'package:lan_mouse_mobile/app/modules/home/widgets/home_general.dart';
import 'package:lan_mouse_mobile/app/modules/home/widgets/home_top.dart';
import 'package:lan_mouse_mobile/app/modules/home/widgets/home_tv_inputs.dart';
import 'package:lan_mouse_mobile/app/services/tv_input_capture.dart';
import 'package:url_launcher/url_launcher.dart';

class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  @override
  void initState() {
    super.initState();
    TvInputCapture.instance.refreshRunningState();
  }

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
              ValueListenableBuilder<bool>(
                valueListenable: TvInputCapture.instance.running,
                builder: (context, running, _) => running
                    ? IconButton(
                        tooltip: 'End capture',
                        onPressed: _endCapture,
                        icon: const Icon(Icons.stop_circle_outlined),
                      )
                    : const SizedBox.shrink(),
              ),
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
                // LayoutBuilder measures the full sliver width. The dashboard
                // itself has 40px padding on each side, so use the inner width
                // or 1920x1080 cards overflow and wrap vertically.
                final availableWidth = constraints.maxWidth - 80;
                final contentWidth =
                    availableWidth > 2600 ? 2600.0 : availableWidth;
                // Keep information-dense TV cards compact on a large display.
                // Three columns at 4K prevent a short source label from
                // expanding into a nearly screen-wide waterfall panel.
                final viewportWidth = MediaQuery.sizeOf(context).width;
                // Flutter uses logical pixels. This TCL's 1920px panel is
                // 960 logical pixels at density 2.0, so use TV breakpoints in
                // logical units rather than the physical ADB resolution.
                final columns = viewportWidth >= 900
                    ? 3
                    : viewportWidth >= 600
                        ? 2
                        : 1;
                final cardWidth =
                    (contentWidth - (24 * (columns - 1))) / columns;
                return Padding(
                  padding: const EdgeInsets.fromLTRB(40, 28, 40, 48),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 2600),
                      child: columns == 3
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: const [
                                HomeTop(),
                                SizedBox(height: 24),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(child: HomeTvInputs()),
                                    SizedBox(width: 24),
                                    Expanded(child: HomeConnections()),
                                    SizedBox(width: 24),
                                    Expanded(child: HomeGeneral()),
                                  ],
                                ),
                              ],
                            )
                          : Wrap(
                              spacing: 24,
                              runSpacing: 24,
                              children: [
                                SizedBox(
                                    width: contentWidth,
                                    child: const HomeTop()),
                                SizedBox(
                                    width: cardWidth,
                                    child: const HomeTvInputs()),
                                SizedBox(
                                    width: cardWidth,
                                    child: const HomeConnections()),
                                SizedBox(
                                    width: cardWidth,
                                    child: const HomeGeneral()),
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

  Future<void> _endCapture() async {
    final end = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End capture?'),
        content: const Text(
          'This stops the relay service and releases all selected input devices.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('End capture')),
        ],
      ),
    );
    if (end == true) await TvInputCapture.instance.stop();
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
