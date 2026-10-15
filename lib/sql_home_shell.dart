import 'package:flutter/material.dart';
import 'package:qfli_studio_core/content/content_repository.dart';
import 'package:qfli_studio_core/pages/local_content_pages.dart';
import 'package:qfli_studio_core/pages/quick_tools_page.dart'
    show FunctionsTab, ContentToolsPage;
import 'package:qfli_studio_core/pages/terminax_terminal_page.dart'
    show TerminaxTerminalPage;
import 'package:qfli_studio_core/store/auth_store.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/store/settings_store.dart';
import 'package:qfli_studio_core/widgets/retained_page.dart';

import 'sql_content_repository.dart';
import 'sql_projects_page.dart';
import 'sql_query_library.dart';
import 'sql_workbench_page.dart';
import 'sql_workspace_repository.dart';

/// The SQL app home shell.
///
/// Owns the top-level navigation for this product: exactly five swipeable
/// destinations — 数据库, 项目, 功能, 教程, 示例. The shell itself renders **no**
/// `AppBar`; each page keeps its own single toolbar. That is what prevents the
/// "double home / duplicate toolbar" this task exists to remove: the shell owns
/// navigation only, the pages own their toolbars.
///
/// It replaces the older flow where the workbench was the app home and
/// 项目/功能/教程/示例 were pushed routes from its 更多 menu.
class SqlHomeShell extends StatefulWidget {
  const SqlHomeShell({
    super.key,
    required this.store,
    required this.auth,
    required this.settings,
    this.repositoryFactory,
    this.queryLibraryFactory,
    this.contentRepository,
  });

  final ProjectStore store;
  final AuthStore auth;
  final SettingsStore settings;

  /// Forwarded to the 数据库 page so boundary tests can inject a repository.
  final Future<SqlWorkspaceRepository> Function()? repositoryFactory;
  final Future<SqlQueryLibrary> Function()? queryLibraryFactory;
  final ContentRepository? contentRepository;

  /// Page labels in swipe order; also the navigation destination labels.
  static const List<String> destinationLabels = ['数据库', '项目', '功能', '教程', '示例'];

  @override
  State<SqlHomeShell> createState() => _SqlHomeShellState();
}

class _SqlHomeShellState extends State<SqlHomeShell> {
  final _currentIndex = ValueNotifier<int>(0);
  final PageController _pageController = PageController();
  // Pages are built lazily and retained so switching destinations does not
  // rebuild (and re-query) the workbench or re-parse content.
  final Map<int, Widget> _pages = {};

  late final ContentRepository _contentRepository =
      widget.contentRepository ?? SqlContentRepository();

  @override
  void dispose() {
    _pageController.dispose();
    _currentIndex.dispose();
    super.dispose();
  }

  void _selectPage(int index) {
    if (!_pageController.hasClients) return;
    final page = _pageController.page ?? _currentIndex.value.toDouble();
    if ((page - index).abs() < 0.001) return;
    if ((page - index).abs() > 1) {
      _pageController.jumpToPage(index);
      return;
    }
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final extendedRail = MediaQuery.sizeOf(context).width >= 1200;
    final destinations = [
      const NavigationDestination(
        icon: Icon(Icons.storage_outlined),
        selectedIcon: Icon(Icons.storage),
        label: '数据库',
      ),
      const NavigationDestination(
        icon: Icon(Icons.folder_open_outlined),
        selectedIcon: Icon(Icons.folder),
        label: '项目',
      ),
      const NavigationDestination(
        icon: Icon(Icons.build_outlined),
        selectedIcon: Icon(Icons.build),
        label: '功能',
      ),
      const NavigationDestination(
        icon: Icon(Icons.menu_book_outlined),
        selectedIcon: Icon(Icons.menu_book),
        label: '教程',
      ),
      const NavigationDestination(
        icon: Icon(Icons.code_outlined),
        selectedIcon: Icon(Icons.code),
        label: '示例',
      ),
    ];
    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (wide) ...[
            ValueListenableBuilder<int>(
              valueListenable: _currentIndex,
              builder: (context, selected, _) => NavigationRail(
                selectedIndex: selected,
                onDestinationSelected: _selectPage,
                extended: extendedRail,
                labelType: extendedRail
                    ? NavigationRailLabelType.none
                    : NavigationRailLabelType.all,
                groupAlignment: -0.7,
                destinations: [
                  for (final destination in destinations)
                    NavigationRailDestination(
                      icon: destination.icon,
                      selectedIcon: destination.selectedIcon,
                      label: Text(destination.label),
                    ),
                ],
              ),
            ),
            const VerticalDivider(width: 1, thickness: 1),
          ],
          Expanded(
            child: PageView.builder(
              key: const ValueKey('sql-home-page-view'),
              controller: _pageController,
              itemCount: SqlHomeShell.destinationLabels.length,
              onPageChanged: (index) => _currentIndex.value = index,
              itemBuilder: (context, index) => _pages.putIfAbsent(
                index,
                () => RetainedPage(
                  key: ValueKey('sql-home-page-$index'),
                  child: ValueListenableBuilder<int>(
                    valueListenable: _currentIndex,
                    builder: (context, selected, child) =>
                        TickerMode(enabled: selected == index, child: child!),
                    child: _buildPage(index),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: wide
          ? null
          : ValueListenableBuilder<int>(
              valueListenable: _currentIndex,
              builder: (context, selected, _) => NavigationBar(
                selectedIndex: selected,
                onDestinationSelected: _selectPage,
                destinations: destinations,
              ),
            ),
    );
  }

  Widget _buildPage(int index) {
    switch (index) {
      case 0:
        // The workbench owns the 数据库 toolbar and the tree/workspace body.
        return SqlWorkbenchPage(
          store: widget.store,
          auth: widget.auth,
          settings: widget.settings,
          repositoryFactory: widget.repositoryFactory,
          queryLibraryFactory: widget.queryLibraryFactory,
          contentRepository: _contentRepository,
          embedded: true,
        );
      case 1:
        // The projects page owns its single toolbar; embedded mode hides the
        // back-to-database affordance because it is now a sibling destination.
        return SqlProjectsPage(
          store: widget.store,
          auth: widget.auth,
          settings: widget.settings,
          embedded: true,
        );
      case 2:
        return FunctionsTab(
          store: widget.store,
          onOpenTerminal: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => TerminaxTerminalPage(store: widget.store),
            ),
          ),
          onOpenContentTool: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ContentToolsPage(store: widget.store),
            ),
          ),
        );
      case 3:
        return LocalTutorialsTab(
          language: 'sql',
          repository: _contentRepository,
          store: widget.store,
          auth: widget.auth,
          settings: widget.settings,
        );
      default:
        return ExampleCodeTab(
          language: 'sql',
          repository: _contentRepository,
          store: widget.store,
          auth: widget.auth,
          settings: widget.settings,
        );
    }
  }
}
