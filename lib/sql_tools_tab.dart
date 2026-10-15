import 'package:flutter/material.dart';
import 'package:qfli_studio_core/i18n/studio_localizations.dart';
import 'package:qfli_studio_core/pages/quick_tools_page.dart'
    show ContentToolsPage;
import 'package:qfli_studio_core/pages/tools_grid.dart' show commonTools;
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/widgets/tool_widgets.dart'
    show ToolsSectionHeading;

/// Product-owned body for the shared FunctionsTab's single toolbar.
Widget buildSqlToolsTab(ProjectStore store, VoidCallback onOpenTerminal) =>
    SqlToolsBody(store: store, onOpenTerminal: onOpenTerminal);

/// Natural-height rows keep all tools usable with large accessibility text.
/// Shared tool definitions still own their original destinations and behavior.
class SqlToolsBody extends StatelessWidget {
  const SqlToolsBody({
    super.key,
    required this.store,
    required this.onOpenTerminal,
  });

  final ProjectStore store;
  final VoidCallback onOpenTerminal;

  @override
  Widget build(BuildContext context) {
    final l10n = StudioLocalizations.of(context);
    return ListView(
      key: const PageStorageKey('sql-tools-scroll'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        _heading('快捷入口', Icons.widgets_outlined),
        ListTile(
          leading: const Icon(Icons.terminal),
          title: const Text('终端'),
          subtitle: const Text('在本机沙盒中运行命令'),
          trailing: const Icon(Icons.chevron_right),
          onTap: onOpenTerminal,
        ),
        _heading('专用', Icons.storage_outlined),
        ListTile(
          leading: const Icon(Icons.storage_outlined),
          title: Text(l10n.sqlTools),
          subtitle: Text(l10n.executeQuery),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ContentToolsPage(store: store),
            ),
          ),
        ),
        _heading('通用', Icons.build_outlined),
        for (final tool in commonTools)
          ListTile(
            leading: Icon(tool.icon),
            title: Text(tool.title),
            subtitle: Text(tool.description),
            trailing: const Icon(Icons.chevron_right),
            onTap:
                tool.onTap ??
                () => Navigator.of(
                  context,
                ).push(MaterialPageRoute<void>(builder: tool.builder!)),
          ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 24, 16, 0),
          child: Text('通用工具均在本机离线计算，不会上传任何内容。'),
        ),
      ],
    );
  }

  Widget _heading(String title, IconData icon) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
    child: ToolsSectionHeading(icon: icon, title: title),
  );
}
