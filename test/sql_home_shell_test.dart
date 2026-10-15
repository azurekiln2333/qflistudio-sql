import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_sql/main.dart' show sqlProfile;
import 'package:qfli_sql/sql_home_shell.dart';
import 'package:qfli_sql/sql_query_library.dart';
import 'package:qfli_sql/sql_workspace_repository.dart';
import 'package:qfli_studio_core/content/content_repository.dart';
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/pages/local_content_pages.dart';
import 'package:qfli_studio_core/pages/settings_page.dart';
import 'package:qfli_studio_core/pages/tools_grid.dart' show commonTools;
import 'package:qfli_studio_core/services/app_paths.dart';
import 'package:qfli_studio_core/widgets/code_snippet.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/store/auth_store.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/store/settings_store.dart';

/// Home-shell boundary tests.
///
/// The shell must expose exactly five swipeable destinations and no duplicate
/// top-level toolbar. The injected content repository keeps the tutorial and
/// example pages off the bundled assets.
void main() {
  late ProjectStore store;
  late AuthStore auth;
  late SettingsStore settings;
  late _FakeWorkspace workspace;
  late _FakeQueryLibrary queryLibrary;
  late StudioProfile? previousProfile;

  setUp(() {
    previousProfile = StudioProfile.current;
    StudioProfile.current = sqlProfile;
    store = _TestProjectStore();
    auth = AuthStore();
    settings = SettingsStore();
    workspace = _FakeWorkspace();
    queryLibrary = _FakeQueryLibrary();
  });

  tearDown(() {
    StudioProfile.current = previousProfile;
    store.dispose();
    auth.dispose();
    settings.dispose();
  });

  Widget app({ContentRepository? content}) => MaterialApp(
    home: SqlHomeShell(
      store: store,
      auth: auth,
      settings: settings,
      repositoryFactory: () async => workspace,
      queryLibraryFactory: () async => queryLibrary,
      contentRepository: content ?? _FakeContentRepository(),
    ),
  );

  void size(WidgetTester tester, Size value) {
    tester.view.physicalSize = value;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('phone home exposes exactly five swipeable destinations', (
    tester,
  ) async {
    size(tester, const Size(390, 800));

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    // Exactly one PageView, with five items.
    expect(find.byKey(const ValueKey('sql-home-page-view')), findsOneWidget);
    final pageView = tester.widget<PageView>(
      find.byKey(const ValueKey('sql-home-page-view')),
    );
    expect(
      pageView.childrenDelegate.estimatedChildCount,
      SqlHomeShell.destinationLabels.length,
    );
    expect(SqlHomeShell.destinationLabels, ['数据库', '项目', '功能', '教程', '示例']);

    // Phone navigation is the bottom bar, not a rail.
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    for (final label in SqlHomeShell.destinationLabels) {
      expect(
        find.text(label),
        findsWidgets,
        reason: 'missing destination $label',
      );
    }

    // Page 0 is the database workbench: its tree is the body.
    expect(find.text('work'), findsOneWidget);
    expect(find.text('people'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('swiping reaches projects, functions, tutorials and examples', (
    tester,
  ) async {
    size(tester, const Size(390, 800));
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    // Destination 1: 项目. Embedded mode has no back-to-database affordance and
    // still renders exactly one toolbar.
    await tester.drag(find.byType(PageView), const Offset(-350, 0));
    await tester.pumpAndSettle();
    expect(find.byTooltip('搜索项目'), findsOneWidget);
    expect(find.byTooltip('返回数据库'), findsNothing);
    expect(find.byType(AppBar), findsOneWidget);

    // Destination 2: 功能 exposes the terminal entry and the SQL tool.
    await tester.drag(find.byType(PageView), const Offset(-350, 0));
    await tester.pumpAndSettle();
    expect(find.text('终端'), findsOneWidget);

    // Destination 3: 教程, destination 4: 示例 — both load through the injected
    // content repository.
    await tester.drag(find.byType(PageView), const Offset(-350, 0));
    await tester.pumpAndSettle();
    expect(find.text('教程'), findsWidgets);
    await tester.drag(find.byType(PageView), const Offset(-350, 0));
    await tester.pumpAndSettle();
    expect(find.text('示例'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop uses a NavigationRail and keeps tree beside workspace', (
    tester,
  ) async {
    size(tester, const Size(1280, 800));

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    // Workbench desktop layout: tree side panel + workspace.
    expect(find.text('work'), findsOneWidget);
    expect(find.text('people'), findsOneWidget);
    expect(find.text('Ada'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('there is no second home toolbar or duplicate rail', (
    tester,
  ) async {
    size(tester, const Size(1280, 800));

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    // The shell adds no AppBar of its own; the only AppBar belongs to the
    // active page.
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsOneWidget);
    // No nested page-view shell (the old shared HomePage is not embedded).
    expect(find.byKey(const ValueKey('home-page-view')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('embedded workbench hides push-to-projects and the 更多 menu', (
    tester,
  ) async {
    size(tester, const Size(1100, 800));

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    // The workbench still owns its database toolbar...
    expect(find.text('QFLISQLab'), findsOneWidget);
    expect(find.byTooltip('刷新'), findsOneWidget);
    // ...but 项目 is a sibling tab now, and 功能/教程/示例 are gone from 更多.
    expect(find.byTooltip('项目'), findsNothing);
    expect(find.byTooltip('更多'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone home survives 2x text scale without overflow', (
    tester,
  ) async {
    size(tester, const Size(390, 800));
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sql-home-page-view')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('database state survives distant tab switches and swipes', (
    tester,
  ) async {
    size(tester, const Size(390, 800));
    var opens = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: SqlHomeShell(
          store: store,
          auth: auth,
          settings: settings,
          repositoryFactory: () async {
            opens++;
            return workspace;
          },
          queryLibraryFactory: () async => queryLibrary,
          contentRepository: _FakeContentRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('people'));
    await tester.pumpAndSettle();
    expect(find.text('Ada'), findsOneWidget);
    await tester.tap(find.byType(NavigationDestination).at(4));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(NavigationDestination).at(0));
    await tester.pumpAndSettle();
    expect(find.text('Ada'), findsOneWidget);
    expect(find.byTooltip('返回数据库'), findsOneWidget);
    expect(opens, 1);

    await tester.tap(find.byTooltip('返回数据库'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('收起'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(PageView), const Offset(-350, 0));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(PageView), const Offset(350, 0));
    await tester.pumpAndSettle();
    expect(find.text('people'), findsNothing);
    expect(find.byTooltip('展开'), findsOneWidget);
    expect(opens, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings are reachable without a project and hide online AI', (
    tester,
  ) async {
    size(tester, const Size(390, 800));
    await tester.runAsync(AppPaths.storageDirectory);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();

    final page = tester.widget<SettingsPage>(find.byType(SettingsPage));
    expect(page.showAi, isFalse);
    expect(page.store, same(store));
    expect(find.text('外观'), findsOneWidget);
    expect(find.text('个人 AI 接口'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('people'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('content pages retain editor import dependencies', (
    tester,
  ) async {
    size(tester, const Size(390, 800));
    final content = _FakeContentRepository();
    await tester.pumpWidget(app(content: content));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(NavigationDestination).at(3));
    await tester.pumpAndSettle();
    final tutorials = tester.widget<LocalTutorialsTab>(
      find.byType(LocalTutorialsTab),
    );
    expect(tutorials.repository, same(content));
    expect(tutorials.store, same(store));
    expect(tutorials.auth, same(auth));
    expect(tutorials.settings, same(settings));
    await tester.tap(find.text('SQL SELECT lesson'));
    await tester.pumpAndSettle();
    final snippet = tester.widget<CodeSnippet>(find.byType(CodeSnippet));
    expect(snippet.store, same(store));
    expect(snippet.auth, same(auth));
    expect(snippet.settings, same(settings));
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byType(NavigationDestination).at(4));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SQL SELECT example'));
    await tester.pumpAndSettle();
    expect(find.byType(CodeSnippet), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('SQL tools retain every shared offline tool and its route', (
    tester,
  ) async {
    size(tester, const Size(390, 800));
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.byType(NavigationDestination).at(2));
    await tester.pumpAndSettle();
    expect(find.text('终端'), findsOneWidget);
    expect(find.text('SQL 查询'), findsOneWidget);
    final scrollable = find.descendant(
      of: find.byKey(const PageStorageKey('sql-tools-scroll')),
      matching: find.byType(Scrollable),
    );
    for (final tool in commonTools) {
      await tester.scrollUntilVisible(
        find.text(tool.title),
        200,
        scrollable: scrollable,
      );
      await tester.pumpAndSettle();
      expect(find.text(tool.title), findsOneWidget);
    }
    await tester.tap(find.text(commonTools.last.title));
    await tester.pumpAndSettle();
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      2,
    );
    expect(tester.takeException(), isNull);
  });

  for (final width in [390.0, 900.0, 1280.0]) {
    testWidgets('all five pages fit at width $width with 2x text', (
      tester,
    ) async {
      size(tester, Size(width, 850));
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      for (var index = 0; index < 5; index++) {
        if (width < 900) {
          await tester.tap(find.byType(NavigationDestination).at(index));
        } else {
          await tester.tap(
            find.descendant(
              of: find.byType(NavigationRail),
              matching: find.text(SqlHomeShell.destinationLabels[index]),
            ),
          );
        }
        await tester.pumpAndSettle();
        expect(find.byType(AppBar), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'page $index');
      }
    });
  }
}

class _FakeContentRepository implements ContentRepository {
  @override
  Future<ContentCatalog> load() async =>
      ContentCatalog(schemaVersion: 1, tutorials: const [], examples: const []);

  @override
  Future<List<TutorialContent>> tutorials({
    ContentFilter filter = const ContentFilter(),
  }) async => const [
    TutorialContent(
      id: 'sql-select',
      language: 'sql',
      type: 'sql',
      locale: 'zh-CN',
      level: 'beginner',
      title: 'SQL SELECT',
      summary: 'SQLite SELECT',
      concepts: ['SELECT'],
      source: 'test',
      license: 'MIT',
      updatedAt: '2026-10-15',
      lessons: [
        TutorialLessonContent(
          id: 'sql-select-lesson',
          title: 'SQL SELECT lesson',
          summary: 'SQLite SELECT',
          concepts: ['SELECT'],
          explain: 'Select one numeric literal.',
          code: 'SELECT 1;',
          output: '1',
          exercises: [],
        ),
      ],
    ),
  ];

  @override
  Future<List<ExampleContent>> examples({
    ContentFilter filter = const ContentFilter(),
  }) async => const [
    ExampleContent(
      id: 'sql-select-example',
      language: 'sql',
      type: 'sql',
      locale: 'zh-CN',
      level: 'beginner',
      title: 'SQL SELECT example',
      summary: 'SQLite SELECT',
      concepts: ['SELECT'],
      source: 'test',
      license: 'MIT',
      updatedAt: '2026-10-15',
      code: 'SELECT 1;',
      expectedOutput: '1',
      inputFixtures: {},
      templateType: 'sql',
    ),
  ];
}

class _TestProjectStore extends ProjectStore {
  @override
  bool get loaded => true;

  @override
  List<Project> get projects => [];
}

class _FakeWorkspace extends SqlWorkspaceRepository {
  _FakeWorkspace() : super(root: Directory.systemTemp);

  @override
  Future<List<String>> listDatabases() async => ['work'];

  @override
  Future<List<String>> listTables(String databaseName) async => ['people'];

  @override
  Future<SqlTablePage> loadTable(
    String databaseName,
    String table, {
    int page = 0,
    String? filterColumn,
    String filter = '',
    String? sortColumn,
    bool descending = false,
  }) async => SqlTablePage(
    columns: const [
      SqlColumn(name: 'id', type: 'INTEGER', notNull: false, primaryKey: true),
      SqlColumn(name: 'name', type: 'TEXT', notNull: true, primaryKey: false),
    ],
    rows: const [
      ['1', 'Ada'],
    ],
    rowIds: const ['1'],
    totalRows: 1,
    editable: true,
  );
}

class _FakeQueryLibrary extends SqlQueryLibrary {
  _FakeQueryLibrary()
    : super(file: File('${Directory.systemTemp.path}/unused.json'));

  @override
  List<SqlHistoryEntry> get history => const [];

  @override
  List<SqlSavedQuery> get saved => const [];
}
