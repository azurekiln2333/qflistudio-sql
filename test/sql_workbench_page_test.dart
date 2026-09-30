import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_sql/sql_database.dart';
import 'package:qfli_sql/sql_query_library.dart';
import 'package:qfli_sql/sql_workbench_page.dart';
import 'package:qfli_sql/sql_workspace_repository.dart';
import 'package:qfli_studio_core/store/auth_store.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/store/settings_store.dart';

void main() {
  late ProjectStore store;
  late AuthStore auth;
  late SettingsStore settings;
  late _FakeWorkspace workspace;
  late _FakeQueryLibrary queryLibrary;

  setUp(() {
    store = ProjectStore();
    auth = AuthStore();
    settings = SettingsStore();
    workspace = _FakeWorkspace();
    queryLibrary = _FakeQueryLibrary();
  });

  tearDown(() {
    store.dispose();
    auth.dispose();
    settings.dispose();
  });

  Widget app() => MaterialApp(
    home: SqlWorkbenchPage(
      store: store,
      auth: auth,
      settings: settings,
      repositoryFactory: () async => workspace,
      queryLibraryFactory: () async => queryLibrary,
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

  testWidgets('uses a database drawer on a narrow viewport', (tester) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.menu), findsOneWidget);
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    expect(find.text('work'), findsWidgets);
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

class _FakeWorkspace extends SqlWorkspaceRepository {
  _FakeWorkspace() : super(root: Directory.systemTemp);

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
      const SqlQueryResult(
        available: true,
        exitCode: 0,
        columns: [],
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
