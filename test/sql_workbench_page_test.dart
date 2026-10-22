import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_sql/sql_database.dart';
import 'package:qfli_sql/sql_engine_preference.dart';
import 'package:qfli_sql/sql_execution_context.dart';
import 'package:qfli_sql/sql_query_library.dart';
import 'package:qfli_sql/sql_tools_service.dart';
import 'package:qfli_sql/sql_tools_tab.dart';
import 'package:qfli_sql/sql_workbench_page.dart';
import 'package:qfli_sql/sql_workspace_repository.dart';
import 'package:qfli_sql/main.dart' show sqlProfile;
import 'package:qfli_studio_core/content/content_repository.dart';
import 'package:qfli_studio_core/pages/local_content_pages.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/store/auth_store.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/store/settings_store.dart';

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
    store = ProjectStore();
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

  Widget app({ContentRepository? content}) => SqlToolsScope(
    createController: () => SqlToolsController(
      openTarget: () async => SqlExecutionContext.forTesting(
        engine: SqlEngineKind.sqlite,
        repository: workspace,
      ),
      openLibrary: () async => queryLibrary,
      watchPreference: false,
    ),
    child: MaterialApp(
      home: SqlWorkbenchPage(
        store: store,
        auth: auth,
        settings: settings,
        repositoryFactory: () async => workspace,
        queryLibraryFactory: () async => queryLibrary,
        contentRepository: content,
      ),
    ),
  );

  testWidgets('shows real table data and saves a cell edit', (tester) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('work'), findsOneWidget);
    expect(find.text('people'), findsOneWidget);
    expect(find.text('Ada'), findsOneWidget);

    await tester.tap(find.text('Ada'));
    await tester.pumpAndSettle();
    expect(find.text('name'), findsWidgets);
    await tester.enterText(find.byType(TextField).last, 'Ada Lovelace');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(workspace.updatedValue, 'Ada Lovelace');
    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows the database tree as the phone home body', (tester) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    // The tree is the home body on a phone: no drawer, and the active database
    // is shown expanded so its tables are immediately reachable.
    expect(find.byIcon(Icons.menu), findsNothing);
    expect(find.text('数据库'), findsOneWidget);
    expect(find.text('work'), findsOneWidget);
    expect(find.text('people'), findsOneWidget);

    // Tapping a table enters the workspace; a back affordance returns to the
    // tree.
    await tester.tap(find.text('people'));
    await tester.pumpAndSettle();
    expect(find.text('Ada'), findsOneWidget);
    await tester.tap(find.byTooltip('返回数据库'));
    await tester.pumpAndSettle();
    expect(find.text('数据库'), findsOneWidget);
    expect(find.byIcon(Icons.menu), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('expands and collapses databases independently', (tester) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    // Row tap selects the database and keeps it expanded.
    await tester.tap(find.text('work'));
    await tester.pumpAndSettle();
    expect(find.text('people'), findsOneWidget);
    // The chevron collapses it independently of selection.
    await tester.tap(find.byTooltip('收起'));
    await tester.pumpAndSettle();
    expect(find.text('people'), findsNothing);
    await tester.tap(find.byTooltip('展开'));
    await tester.pumpAndSettle();
    expect(find.text('people'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opens a single-toolbar standalone projects page', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // Preload the store so the projects page shows its list, not a spinner.
    await tester.runAsync(() => store.load());

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('项目'));
    await tester.pumpAndSettle();

    // A single project toolbar: the projects page title, not a nested home.
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.text('QFLISQLab'), findsNothing);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byTooltip('搜索项目'), findsOneWidget);
    expect(find.byTooltip('返回数据库'), findsOneWidget);

    // Search toggles into the same single toolbar.
    await tester.tap(find.byTooltip('搜索项目'));
    await tester.pumpAndSettle();
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.byTooltip('关闭搜索'), findsOneWidget);
    await tester.tap(find.byTooltip('关闭搜索'));
    await tester.pumpAndSettle();

    // The original project-management actions stay in the 更多 menu.
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text('移除失效项目'), findsOneWidget);
    // Close the open menu before navigating back.
    await tester.tapAt(const Offset(20, 400));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('返回数据库'));
    await tester.pumpAndSettle();
    expect(find.text('数据库'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop 1280 keeps the tree side panel beside the workspace', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    // Side panel and workspace coexist; no mobile back affordance.
    expect(find.text('数据库'), findsOneWidget);
    expect(find.text('work'), findsOneWidget);
    expect(find.text('people'), findsOneWidget);
    expect(find.byTooltip('返回数据库'), findsNothing);
    expect(find.text('Ada'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop 1280 at 2x text scale does not overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('数据库'), findsOneWidget);
    expect(find.text('work'), findsOneWidget);
    expect(find.text('Ada'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('manual collapse of the active database survives refresh', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('people'), findsOneWidget);
    await tester.tap(find.byTooltip('收起'));
    await tester.pumpAndSettle();
    expect(find.text('people'), findsNothing);
    await tester.tap(find.byTooltip('刷新'));
    await tester.pumpAndSettle();
    expect(find.text('people'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'restores the 功能 entry so terminal and SQL tools stay reachable',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('更多'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('功能'));
      await tester.pumpAndSettle();
      // The real profile builder renders SQL controls directly under the
      // FunctionsTab toolbar, with controlled local repository dependencies.
      expect(find.text('终端'), findsOneWidget);
      expect(find.text('SQL 查询'), findsOneWidget);
      expect(find.byKey(const ValueKey('sql-tools-worksheet')), findsOneWidget);
      expect(find.byKey(const ValueKey('sql-tools-run')), findsOneWidget);
      expect(find.text('专用'), findsNothing);
      expect(find.byType(AppBar), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('offline workbench exposes no cloud or login controls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // The SQL product profile is offline: no reachable control may offer a
    // networked engine, login or Git action. With a repository injected the
    // engine menu itself is not shown, so assert the reachable UI directly.
    expect(sqlProfile.isOffline, isTrue);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('云 MySQL'), findsNothing);
    expect(find.textContaining('登录'), findsNothing);
    expect(find.textContaining('Git'), findsNothing);
    expect(find.byTooltip('退出登录'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opens injected tutorial and example content from home', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final content = _FakeContentRepository();

    await tester.pumpWidget(app(content: content));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('教程'));
    await tester.pumpAndSettle();
    expect(content.tutorialQueries, greaterThan(0));
    expect(find.text('教程'), findsWidgets);
    expect(find.byType(AppBar), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('示例'));
    await tester.pumpAndSettle();
    expect(content.exampleQueries, greaterThan(0));
    expect(find.byType(ExampleCodeTab), findsOneWidget);
    expect(find.byType(AppBar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone home tree survives 2x text scale without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('数据库'), findsOneWidget);
    expect(find.text('work'), findsOneWidget);
    expect(find.text('people'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps empty table columns visible and permits row insertion', (
    tester,
  ) async {
    workspace.emptyTable = true;
    workspace.editable = false;
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('id'), findsOneWidget);
    expect(find.text('name'), findsOneWidget);
    expect(find.text('暂无数据 · 0 / 0'), findsOneWidget);

    await tester.tap(find.text('添加行'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Grace');
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();
    expect(find.text('Grace'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'does not show old rows when switching to a table that fails to load',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      workspace.hasBrokenTable = true;

      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.text('Ada'), findsOneWidget);

      await tester.tap(find.text('broken'));
      await tester.pumpAndSettle();
      expect(find.text('Ada'), findsNothing);
      expect(find.text('无法读取数据表'), findsWidgets);
      expect(find.text('重试'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('records SQL history and saves and restores a query', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('SQL'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'SELECT 1');
    await tester.pump();
    await tester.tap(find.text('执行'));
    await tester.pumpAndSettle();
    expect(queryLibrary.history.single.database, 'work');
    expect(queryLibrary.history.single.source, 'SELECT 1');
    expect(queryLibrary.history.single.success, isTrue);

    await tester.tap(find.text('保存查询'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'One');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(queryLibrary.saved.single.name, 'One');

    await tester.tap(find.text('已保存查询'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'SELECT 2');
    await tester.ensureVisible(find.text('One'));
    await tester.tap(find.text('One'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'SELECT 1',
    );

    await tester.ensureVisible(find.byTooltip('删除保存的查询'));
    await tester.tap(find.byTooltip('删除保存的查询'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(queryLibrary.saved, isEmpty);

    await tester.ensureVisible(find.byTooltip('清空历史记录'));
    await tester.tap(find.byTooltip('清空历史记录'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清空'));
    await tester.pumpAndSettle();
    expect(queryLibrary.history, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps SQL results visible when recording history fails', (
    tester,
  ) async {
    queryLibrary.failRecording = true;
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('SQL'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'SELECT 1');
    await tester.pump();
    await tester.tap(find.text('执行'));
    await tester.pumpAndSettle();

    expect(find.text('已执行 · 影响 0 行'), findsOneWidget);
    expect(find.textContaining('无法保存查询历史'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _FakeContentRepository implements ContentRepository {
  int tutorialQueries = 0;
  int exampleQueries = 0;

  @override
  Future<ContentCatalog> load() async =>
      ContentCatalog(schemaVersion: 1, tutorials: const [], examples: const []);

  @override
  Future<List<TutorialContent>> tutorials({
    ContentFilter filter = const ContentFilter(),
  }) async {
    tutorialQueries++;
    return const [];
  }

  @override
  Future<List<ExampleContent>> examples({
    ContentFilter filter = const ContentFilter(),
  }) async {
    exampleQueries++;
    return const [];
  }
}

class _FakeWorkspace extends SqlWorkspaceRepository {
  _FakeWorkspace() : super(root: Directory.systemTemp);

  @override
  Future<List<SqlColumn>> tableColumns(
    String databaseName,
    String table,
  ) async => (await loadTable(databaseName, table)).columns;

  @override
  Future<List<SqlIndex>> tableIndexes(
    String databaseName,
    String table,
  ) async => [];

  String name = 'Ada';
  String? updatedValue;
  bool hasBrokenTable = false;
  bool emptyTable = false;
  bool editable = true;

  @override
  Future<List<String>> listDatabases() async => ['work'];

  @override
  Future<List<String>> listTables(String databaseName) async => [
    'people',
    if (hasBrokenTable) 'broken',
  ];

  @override
  Future<SqlTablePage> loadTable(
    String databaseName,
    String table, {
    int page = 0,
    String? filterColumn,
    String filter = '',
    String? sortColumn,
    bool descending = false,
  }) async {
    if (table == 'broken') throw StateError('无法读取数据表');
    return SqlTablePage(
      columns: const [
        SqlColumn(
          name: 'id',
          type: 'INTEGER',
          notNull: false,
          primaryKey: true,
        ),
        SqlColumn(name: 'name', type: 'TEXT', notNull: true, primaryKey: false),
      ],
      rows: [
        if (!emptyTable) ['1', name],
      ],
      rowIds: [if (!emptyTable && editable) '1'],
      totalRows: emptyTable ? 0 : 1,
      editable: editable,
    );
  }

  @override
  Future<void> updateCell(
    String databaseName,
    String table,
    String rowId,
    String column,
    String? value,
  ) async {
    updatedValue = value;
    name = value ?? '';
  }

  @override
  Future<void> insertRow(
    String databaseName,
    String table,
    Map<String, String?> values,
  ) async {
    name = values['name'] ?? '';
    emptyTable = false;
  }

  @override
  Future<SqlQueryResult> runQuery(String databaseName, String source) async =>
      SqlQueryResult(
        available: true,
        exitCode: 0,
        columns: source.startsWith('PRAGMA main.index_list(')
            ? ['seq', 'name', 'unique', 'origin', 'partial']
            : [],
        rows: [],
        affectedRows: 0,
        truncated: false,
      );
}

class _FakeQueryLibrary extends SqlQueryLibrary {
  _FakeQueryLibrary()
    : super(file: File('${Directory.systemTemp.path}/unused.json'));

  final _history = <SqlHistoryEntry>[];
  final _saved = <SqlSavedQuery>[];
  bool failRecording = false;

  @override
  List<SqlHistoryEntry> get history => _history;

  @override
  List<SqlSavedQuery> get saved => _saved;

  @override
  Future<void> recordExecution({
    required String database,
    required String source,
    required bool success,
  }) async {
    if (failRecording) throw const FileSystemException('无法保存查询历史');
    _history.add(
      SqlHistoryEntry(
        database: database,
        source: source,
        success: success,
        executedAt: DateTime(2026, 9, 30),
      ),
    );
  }

  @override
  Future<void> saveQuery({
    required String database,
    required String name,
    required String source,
  }) async {
    _saved.add(
      SqlSavedQuery(
        database: database,
        name: name,
        source: source,
        updatedAt: DateTime(2026, 9, 30),
      ),
    );
  }

  @override
  Future<void> deleteSavedQuery(String database, String name) async {
    _saved.removeWhere(
      (query) => query.database == database && query.name == name,
    );
  }

  @override
  Future<void> clearHistory() async => _history.clear();
}
