import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_sql/sql_database.dart';
import 'package:qfli_sql/sql_engine_preference.dart';
import 'package:qfli_sql/sql_execution_context.dart';
import 'package:qfli_sql/sql_query_library.dart';
import 'package:qfli_sql/sql_tools_service.dart';
import 'package:qfli_sql/sql_tools_tab.dart';
import 'package:qfli_sql/sql_workspace_repository.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/widgets/retained_page.dart';

/// Widget boundary tests for the SQL section of the 功能 destination.
///
/// The controller is injected so every assertion is about the real repository
/// seam (exact engine, database and source), not about a mocked success.
void main() {
  late _FakeRepository repository;
  late _FakeLibrary library;
  var terminalOpens = 0;

  setUp(() {
    repository = _FakeRepository();
    library = _FakeLibrary();
    terminalOpens = 0;
  });

  SqlToolsController controller({
    SqlEngineKind engine = SqlEngineKind.localMysql,
    bool withLibrary = true,
    Future<SqlExecutionContext> Function()? openTarget,
  }) => SqlToolsController(
    openTarget:
        openTarget ??
        () async => SqlExecutionContext.forTesting(
          engine: engine,
          repository: repository,
        ),
    openLibrary: () async => library,
    libraryEnabled: withLibrary,
    watchPreference: false,
  );

  Widget host(SqlToolsController subject, {Size size = const Size(390, 900)}) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('功能')),
        body: SqlToolsBody(
          // Distinct keys keep two pumped controllers from sharing State.
          key: ValueKey(subject),
          store: _TestProjectStore(),
          onOpenTerminal: () => terminalOpens++,
          controller: subject,
        ),
      ),
    );
  }

  Finder scrollable() => find
      .descendant(
        of: find.byKey(const PageStorageKey('sql-tools-scroll')),
        matching: find.byType(Scrollable),
      )
      .first;

  Future<void> scrollTo(WidgetTester tester, Finder target) async {
    await tester.scrollUntilVisible(target, 200, scrollable: scrollable());
    await tester.pumpAndSettle();
  }

  testWidgets('renders SQL capabilities inline with a single toolbar', (
    tester,
  ) async {
    final subject = controller();
    addTearDown(subject.dispose);
    await tester.pumpWidget(host(subject));
    await tester.pumpAndSettle();

    expect(find.byType(AppBar), findsOneWidget);
    // No generic “专用” landing page and no secondary SQL route.
    expect(find.text('专用'), findsNothing);
    expect(find.text('SQL 查询'), findsOneWidget);
    expect(find.text('终端'), findsOneWidget);
    expect(find.byKey(const ValueKey('sql-tools-worksheet')), findsOneWidget);
    expect(find.byKey(const ValueKey('sql-tools-run')), findsOneWidget);
    expect(find.byKey(const ValueKey('sql-tools-explain')), findsOneWidget);
    expect(find.text('引擎：本机 MySQL · 数据库：shop'), findsOneWidget);
    await scrollTo(tester, find.text('结构与索引'));
    expect(find.text('结构与索引'), findsOneWidget);
    await scrollTo(tester, find.text('文本与值工具'));
    expect(find.text('文本与值工具'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('terminal entry keeps its own callback', (tester) async {
    final subject = controller();
    addTearDown(subject.dispose);
    await tester.pumpWidget(host(subject));
    await tester.pumpAndSettle();

    await tester.tap(find.text('终端'));
    await tester.pumpAndSettle();
    expect(terminalOpens, 1);
    expect(find.byType(AppBar), findsOneWidget);
  });

  testWidgets('executes the exact source on the selected engine and database', (
    tester,
  ) async {
    final subject = controller();
    addTearDown(subject.dispose);
    await tester.pumpWidget(host(subject));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('sql-tools-worksheet')),
      'SELECT 1; SELECT 2;',
    );
    await tester.pumpAndSettle();
    await scrollTo(tester, find.byKey(const ValueKey('sql-tools-run')));
    await tester.tap(find.byKey(const ValueKey('sql-tools-run')));
    await tester.pumpAndSettle();

    expect(repository.scriptCalls.single, ('shop', 'SELECT 1; SELECT 2;'));
    expect(find.byKey(const ValueKey('sql-tools-results')), findsOneWidget);
    expect(find.text('结果 1 / 2'), findsOneWidget);
    expect(find.text('结果 2 / 2'), findsOneWidget);
    // Truncation is visible and the CSV action states it.
    expect(find.byKey(const ValueKey('sql-tools-truncated')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows engine failure with SQLSTATE and partial results', (
    tester,
  ) async {
    repository.scriptResult = SqlScriptResult(
      summary: const SqlQueryResult(
        available: true,
        exitCode: 1,
        columns: [],
        rows: [],
        affectedRows: 0,
        truncated: false,
        error: 'Table does not exist',
        sqlState: '42S02',
      ),
      results: const [
        SqlQueryResult(
          available: true,
          exitCode: 0,
          columns: ['n'],
          rows: [
            ['1'],
          ],
          affectedRows: 0,
          truncated: false,
        ),
      ],
    );
    final subject = controller();
    addTearDown(subject.dispose);
    await tester.pumpWidget(host(subject));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('sql-tools-worksheet')),
      'SELECT 1; SELECT * FROM missing;',
    );
    await scrollTo(tester, find.byKey(const ValueKey('sql-tools-run')));
    await tester.tap(find.byKey(const ValueKey('sql-tools-run')));
    await tester.pumpAndSettle();

    expect(find.textContaining('SQLSTATE 42S02'), findsOneWidget);
    expect(find.textContaining('Table does not exist'), findsOneWidget);
    expect(find.textContaining('前面的语句可能已经生效'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reports an unavailable engine honestly instead of a clean run', (
    tester,
  ) async {
    final subject = controller(
      openTarget: () async => throw const FileSystemException('无法访问应用数据目录'),
    );
    addTearDown(subject.dispose);
    await tester.pumpWidget(host(subject));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('sql-tools-context-error')),
      findsOneWidget,
    );
    expect(find.textContaining('无法访问应用数据目录'), findsWidgets);
    final run = tester.widget<FilledButton>(
      find.byKey(const ValueKey('sql-tools-run')),
    );
    expect(run.onPressed, isNull);
    expect(repository.scriptCalls, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('query plan shows engine rows and never runs the source', (
    tester,
  ) async {
    final subject = controller();
    addTearDown(subject.dispose);
    await tester.pumpWidget(host(subject));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('sql-tools-worksheet')),
      'SELECT * FROM items',
    );
    await scrollTo(tester, find.byKey(const ValueKey('sql-tools-explain')));
    await tester.tap(find.byKey(const ValueKey('sql-tools-explain')));
    await tester.pumpAndSettle();
    await scrollTo(tester, find.byKey(const ValueKey('sql-tools-plan-table')));

    expect(repository.queryCalls.single, (
      'shop',
      'EXPLAIN SELECT * FROM items',
    ));
    expect(repository.scriptCalls, isEmpty);
    expect(find.text('EXPLAIN SELECT * FROM items'), findsOneWidget);
    expect(find.text('引擎：本机 MySQL'), findsOneWidget);
    expect(find.text('SIMPLE'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('schema and index inspection render real metadata', (
    tester,
  ) async {
    final subject = controller();
    addTearDown(subject.dispose);
    await tester.pumpWidget(host(subject));
    await tester.pumpAndSettle();

    await scrollTo(tester, find.byKey(const ValueKey('sql-tools-columns')));
    expect(find.text('列（2）'), findsOneWidget);
    expect(find.text('id'), findsWidgets);
    expect(find.text('INTEGER'), findsOneWidget);
    expect(find.text('索引（2）'), findsOneWidget);
    expect(find.text('PRIMARY'), findsOneWidget);
    expect(find.text('items_name'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('SQLite shows inspected indexes and its generator limitation', (
    tester,
  ) async {
    repository.indexesUnsupported = true;
    final subject = controller(engine: SqlEngineKind.sqlite);
    addTearDown(subject.dispose);
    await tester.pumpWidget(host(subject));
    await tester.pumpAndSettle();

    expect(find.text('引擎：SQLite · 数据库：shop'), findsOneWidget);
    await scrollTo(
      tester,
      find.byKey(const ValueKey('sql-tools-index-generator-note')),
    );
    expect(subject.indexes.single.name, 'items_name');
    expect(find.text('items_name'), findsOneWidget);
    expect(find.textContaining('部分索引'), findsOneWidget);
    expect(find.byKey(const ValueKey('sql-tools-index-name')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  final nativeLibrary =
      Platform.environment['QFLI_SQLITE_LIBRARY'] ??
      'native/build/${Platform.operatingSystem}/'
          '${Platform.isWindows ? 'qfli_sqlite.dll' : 'libqfli_sqlite.so'}';
  testWidgets(
    'real SQLite DROP of the last table removes its rendered columns and indexes',
    (tester) async {
      final root = Directory.systemTemp.createTempSync('qfli_tools_drop_');
      final actualRepository = SqlWorkspaceRepository(
        root: root,
        scriptDatabase: const NativeSqliteDatabase(),
      );
      await tester.runAsync(() async {
        await actualRepository.createDatabase('inspection');
        final seeded = await actualRepository.runScript(
          'inspection',
          'CREATE TABLE last_table (kept_column TEXT); '
              'CREATE INDEX kept_index ON last_table(kept_column);',
        );
        expect(seeded.success, isTrue, reason: seeded.error);
      });
      final subject = SqlToolsController(
        openTarget: () async => SqlExecutionContext.forTesting(
          engine: SqlEngineKind.sqlite,
          repository: actualRepository,
        ),
        watchPreference: false,
        libraryEnabled: false,
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        subject.dispose();
        await tester.runAsync(() => root.delete(recursive: true));
      });
      Future<void> waitForIdle() async {
        final deadline = DateTime.now().add(const Duration(seconds: 10));
        while (subject.initializing || subject.busy) {
          if (DateTime.now().isAfter(deadline)) {
            fail('Real SQLite tools operation did not settle.');
          }
          await tester.pump(const Duration(milliseconds: 20));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
        }
      }

      await tester.pumpWidget(host(subject));
      await waitForIdle();
      await tester.pumpAndSettle();
      expect(subject.contextError, isNull);
      await scrollTo(tester, find.byKey(const ValueKey('sql-tools-columns')));
      expect(find.text('kept_column'), findsWidgets);
      expect(find.text('kept_index'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('sql-tools-worksheet')),
        -200,
        scrollable: scrollable(),
      );
      await tester.enterText(
        find.byKey(const ValueKey('sql-tools-worksheet')),
        'DROP TABLE last_table;',
      );
      await tester.ensureVisible(find.byKey(const ValueKey('sql-tools-run')));
      await tester.tap(find.byKey(const ValueKey('sql-tools-run')));
      await waitForIdle();
      await tester.pumpAndSettle();
      expect(subject.script!.success, isTrue, reason: subject.script!.error);
      await scrollTo(tester, find.text('当前数据库没有可查看的数据表。'));
      expect(find.byKey(const ValueKey('sql-tools-columns')), findsNothing);
      expect(find.text('kept_column'), findsNothing);
      expect(find.text('kept_index'), findsNothing);
      expect(find.text('索引（0）'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    // This is actual-engine UI evidence only when the bundled library exists.
    skip: !File(nativeLibrary).existsSync(),
  );

  testWidgets('index builder only generates reviewed SQL', (tester) async {
    final subject = controller();
    addTearDown(subject.dispose);
    await tester.pumpWidget(host(subject));
    await tester.pumpAndSettle();

    await scrollTo(tester, find.byKey(const ValueKey('sql-tools-index-name')));
    await tester.enterText(
      find.byKey(const ValueKey('sql-tools-index-name')),
      'idx name',
    );
    await tester.tap(find.widgetWithText(FilterChip, 'name'));
    await tester.pumpAndSettle();
    await scrollTo(
      tester,
      find.byKey(const ValueKey('sql-tools-build-create-index')),
    );
    await tester.tap(
      find.byKey(const ValueKey('sql-tools-build-create-index')),
    );
    await tester.pumpAndSettle();
    await scrollTo(
      tester,
      find.byKey(const ValueKey('sql-tools-index-preview')),
    );

    expect(
      find.text('CREATE INDEX `idx name` ON `items` (`name`);'),
      findsOneWidget,
    );
    expect(find.textContaining('不会自动执行'), findsOneWidget);
    expect(repository.scriptCalls, isEmpty);
    expect(repository.queryCalls, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('identifier and value helpers follow the selected dialect', (
    tester,
  ) async {
    final subject = controller();
    addTearDown(subject.dispose);
    await tester.pumpWidget(host(subject));
    await tester.pumpAndSettle();

    await scrollTo(tester, find.byKey(const ValueKey('sql-tools-identifier')));
    await tester.enterText(
      find.byKey(const ValueKey('sql-tools-identifier')),
      'order',
    );
    await tester.pumpAndSettle();
    expect(find.text('MySQL：`order`'), findsOneWidget);

    await scrollTo(tester, find.byKey(const ValueKey('sql-tools-value')));
    await tester.enterText(
      find.byKey(const ValueKey('sql-tools-value')),
      "it's",
    );
    await tester.pumpAndSettle();
    expect(find.text("'it''s'"), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('sql-tools-value-null')));
    await tester.pumpAndSettle();
    expect(find.textContaining('SQL 空值'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('history persistence failure keeps the valid result', (
    tester,
  ) async {
    library.failOnRecord = true;
    final subject = controller();
    addTearDown(subject.dispose);
    await tester.pumpWidget(host(subject));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('sql-tools-worksheet')),
      'SELECT 1',
    );
    await scrollTo(tester, find.byKey(const ValueKey('sql-tools-run')));
    await tester.tap(find.byKey(const ValueKey('sql-tools-run')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('sql-tools-results')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('sql-tools-library-error')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('statement count follows the selected dialect', (tester) async {
    final mysql = controller();
    addTearDown(mysql.dispose);
    await tester.pumpWidget(host(mysql));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('sql-tools-worksheet')),
      'SELECT 1--2; SELECT 3',
    );
    await tester.pumpAndSettle();
    // MySQL needs whitespace after `--`, so both halves are statements.
    expect(find.text('可执行语句：2 条'), findsOneWidget);

    final sqlite = controller(engine: SqlEngineKind.sqlite);
    addTearDown(sqlite.dispose);
    await tester.pumpWidget(host(sqlite));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('sql-tools-worksheet')),
      'SELECT 1--2; SELECT 3',
    );
    await tester.pumpAndSettle();
    // SQLite treats `--2; SELECT 3` as a comment: only one statement remains.
    expect(find.text('可执行语句：1 条'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'ambiguous statement count stays visible without blocking execution',
    (tester) async {
      final subject = controller(engine: SqlEngineKind.sqlite);
      addTearDown(subject.dispose);
      await tester.pumpWidget(host(subject));
      await tester.pumpAndSettle();
      const source =
          'CREATE TRIGGER t AFTER INSERT ON x BEGIN UPDATE x SET end=1; END; SELECT 2;';
      await tester.enterText(
        find.byKey(const ValueKey('sql-tools-worksheet')),
        source,
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('语句数量暂无法可靠统计'), findsOneWidget);
      await scrollTo(tester, find.byKey(const ValueKey('sql-tools-run')));
      await tester.tap(find.byKey(const ValueKey('sql-tools-run')));
      await tester.pumpAndSettle();
      expect(repository.scriptCalls.single.$2, source);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('results and 2x text fit a narrow phone without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final subject = controller();
    addTearDown(subject.dispose);
    await tester.pumpWidget(host(subject));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('sql-tools-worksheet')),
      'SELECT 1',
    );
    await scrollTo(tester, find.byKey(const ValueKey('sql-tools-run')));
    await tester.tap(find.byKey(const ValueKey('sql-tools-run')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('sql-tools-results')), findsOneWidget);
    await scrollTo(tester, find.byKey(const ValueKey('sql-tools-columns')));
    await scrollTo(tester, find.byKey(const ValueKey('sql-tools-identifier')));
    expect(tester.takeException(), isNull);
  });

  testWidgets('worksheet text survives a distant retained page switch', (
    tester,
  ) async {
    final subject = controller();
    addTearDown(subject.dispose);
    final pages = PageController();
    addTearDown(pages.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: PageView(
          controller: pages,
          children: [
            const Center(child: Text('页面 A')),
            RetainedPage(
              child: Scaffold(
                appBar: AppBar(title: const Text('功能')),
                body: SqlToolsBody(
                  store: _TestProjectStore(),
                  onOpenTerminal: () {},
                  controller: subject,
                ),
              ),
            ),
            const Center(child: Text('页面 C')),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    pages.jumpToPage(1);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('sql-tools-worksheet')),
      'SELECT 42 AS answer;',
    );
    await tester.pumpAndSettle();
    pages.jumpToPage(2);
    await tester.pumpAndSettle();
    pages.jumpToPage(1);
    await tester.pumpAndSettle();

    expect(find.text('SELECT 42 AS answer;'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _TestProjectStore extends ProjectStore {
  @override
  bool get loaded => true;
}

class _FakeRepository extends SqlWorkspaceRepository {
  _FakeRepository() : super(root: Directory.systemTemp);

  final List<(String, String)> scriptCalls = [];
  final List<(String, String)> queryCalls = [];
  bool indexesUnsupported = false;
  SqlScriptResult? scriptResult;

  @override
  bool get supportsSchemaTools => !indexesUnsupported;

  @override
  Future<List<String>> listDatabases() async => ['shop'];

  @override
  Future<List<String>> listTables(String databaseName) async => ['items'];

  @override
  Future<List<SqlColumn>> tableColumns(
    String databaseName,
    String table,
  ) async => const [
    SqlColumn(name: 'id', type: 'INTEGER', notNull: true, primaryKey: true),
    SqlColumn(name: 'name', type: 'TEXT', notNull: false, primaryKey: false),
  ];

  @override
  Future<List<SqlIndex>> tableIndexes(String databaseName, String table) async {
    if (indexesUnsupported) {
      throw UnsupportedError('当前数据库引擎不支持索引操作');
    }
    return const [
      SqlIndex(name: 'PRIMARY', columns: ['id'], unique: true, primary: true),
      SqlIndex(name: 'items_name', columns: ['name'], unique: false),
    ];
  }

  @override
  Future<SqlScriptResult> runScript(String databaseName, String source) async {
    scriptCalls.add((databaseName, source));
    return scriptResult ??
        SqlScriptResult(
          summary: const SqlQueryResult(
            available: true,
            exitCode: 0,
            columns: ['n'],
            rows: [
              ['1'],
            ],
            affectedRows: 0,
            truncated: true,
          ),
          results: const [
            SqlQueryResult(
              available: true,
              exitCode: 0,
              columns: ['n'],
              rows: [
                ['1'],
              ],
              affectedRows: 0,
              truncated: false,
            ),
            SqlQueryResult(
              available: true,
              exitCode: 0,
              columns: ['n'],
              rows: [
                ['2'],
              ],
              affectedRows: 0,
              truncated: false,
            ),
          ],
        );
  }

  @override
  Future<SqlQueryResult> runQuery(String databaseName, String source) async {
    queryCalls.add((databaseName, source));
    if (source.startsWith('PRAGMA main.index_list(')) {
      return const SqlQueryResult(
        available: true,
        exitCode: 0,
        columns: ['seq', 'name', 'unique', 'origin', 'partial'],
        rows: [
          ['0', 'items_name', '0', 'c', '1'],
        ],
        affectedRows: 0,
        truncated: false,
      );
    }
    if (source.startsWith('PRAGMA main.index_info(')) {
      return const SqlQueryResult(
        available: true,
        exitCode: 0,
        columns: ['seqno', 'cid', 'name'],
        rows: [
          ['0', '1', 'name'],
        ],
        affectedRows: 0,
        truncated: false,
      );
    }
    return const SqlQueryResult(
      available: true,
      exitCode: 0,
      columns: ['id', 'select_type', 'table'],
      rows: [
        ['1', 'SIMPLE', 'items'],
      ],
      affectedRows: 0,
      truncated: false,
    );
  }
}

class _FakeLibrary extends SqlQueryLibrary {
  _FakeLibrary()
    : super(file: File('${Directory.systemTemp.path}/unused-tab.json'));

  bool failOnRecord = false;
  final List<SqlHistoryEntry> _entries = [];

  @override
  List<SqlHistoryEntry> get history => List.unmodifiable(_entries);

  @override
  List<SqlSavedQuery> get saved => const [];

  @override
  Future<void> recordExecution({
    required String database,
    required String source,
    required bool success,
  }) async {
    if (failOnRecord) throw const FileSystemException('磁盘写入失败');
    _entries.insert(
      0,
      SqlHistoryEntry(
        database: database,
        source: source,
        executedAt: DateTime(2026, 10, 22),
        success: success,
      ),
    );
  }
}
