import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_sql/sql_database.dart';
import 'package:qfli_sql/sql_engine_preference.dart';
import 'package:qfli_sql/sql_execution_context.dart';
import 'package:qfli_sql/sql_query_library.dart';
import 'package:qfli_sql/sql_workbench_page.dart';
import 'package:qfli_sql/sql_workspace_repository.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/store/auth_store.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/store/settings_store.dart';

const _offlineProfile = StudioProfile(
  id: 'sql-engine-context-test',
  appTitle: 'SQL',
  templates: [],
  offlineOnly: true,
);
const _onlineProfile = StudioProfile(
  id: 'sql-engine-context-cloud-test',
  appTitle: 'SQL',
  templates: [],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory storage;
  late File preferenceFile;
  late StudioProfile? previousProfile;

  setUpAll(() {
    storage = Directory.systemTemp.createTempSync('sql_engine_context_');
    preferenceFile = File(p.join(storage.path, 'sql_engine.json'));
    preferenceFile.writeAsStringSync('{"engine":"cloud"}');
    messenger.setMockMethodCallHandler(paths, (_) async => storage.path);
  });

  setUp(() {
    previousProfile = StudioProfile.current;
    StudioProfile.current = _offlineProfile;
  });

  tearDown(() => StudioProfile.current = previousProfile);

  tearDownAll(() {
    messenger.setMockMethodCallHandler(paths, null);
    storage.deleteSync(recursive: true);
  });

  test(
    'persisted offline cloud choice resolves to SQLite without rewriting it',
    () async {
      final reads = await Future.wait([
        SqlEnginePreference.load(),
        SqlEnginePreference.load(),
      ]);
      expect(reads, everyElement(SqlEngineKind.sqlite));
      expect(jsonDecode(preferenceFile.readAsStringSync())['engine'], 'cloud');
      expect(
        SqlEnginePreference.resolveLocalEngine(SqlEngineKind.cloud),
        SqlEngineKind.sqlite,
      );
      expect(
        SqlEnginePreference.resolveLocalEngine(SqlEngineKind.localMysql),
        SqlEngineKind.localMysql,
      );
    },
  );

  test(
    'successful disk publication notifies retained consumers once',
    () async {
      await SqlEnginePreference.save(SqlEngineKind.sqlite);
      final revision = SqlEnginePreference.revision;
      final events = <(SqlEngineKind, int, String)>[];
      void changed() => events.add((
        SqlEnginePreference.current,
        SqlEnginePreference.revision,
        jsonDecode(preferenceFile.readAsStringSync())['engine'] as String,
      ));
      SqlEnginePreference.changes.addListener(changed);
      addTearDown(() => SqlEnginePreference.changes.removeListener(changed));

      await SqlEnginePreference.save(SqlEngineKind.localMysql);
      await SqlEnginePreference.save(SqlEngineKind.localMysql);

      expect(events, [(SqlEngineKind.localMysql, revision + 1, 'localMysql')]);
      expect(await SqlEnginePreference.load(), SqlEngineKind.localMysql);
    },
  );

  test(
    'failed preference write preserves engine, revision and subscribers',
    () async {
      await SqlEnginePreference.save(SqlEngineKind.sqlite);
      final revision = SqlEnginePreference.revision;
      final before = preferenceFile.readAsStringSync();
      final blockedTemporary = Directory('${preferenceFile.path}.tmp')
        ..createSync();
      addTearDown(() => blockedTemporary.deleteSync());
      var events = 0;
      void changed() => events++;
      SqlEnginePreference.changes.addListener(changed);
      addTearDown(() => SqlEnginePreference.changes.removeListener(changed));

      await expectLater(
        SqlEnginePreference.save(SqlEngineKind.localMysql),
        throwsA(isA<FileSystemException>()),
      );

      expect(SqlEnginePreference.current, SqlEngineKind.sqlite);
      expect(SqlEnginePreference.revision, revision);
      expect(preferenceFile.readAsStringSync(), before);
      expect(events, 0);
    },
  );

  test(
    'SQLite selection keeps native-channel identity and database path',
    () async {
      await SqlEnginePreference.save(SqlEngineKind.sqlite);
      const channel = MethodChannel('qfli_sql/native');
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return {
          ..._nativeResult,
          if (call.method == 'executeScript') 'results': [_nativeResult],
        };
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      const native = NativeSqliteDatabase(channel: channel);
      final repository = SqlWorkspaceRepository(
        root: Directory(p.join(storage.path, 'native-databases')),
        database: native,
        scriptDatabase: native,
      );
      final context = await SqlExecutionContext.openLocal(
        openSqlite: () async => repository,
        openMysql: () => throw StateError('SQLite must never open MySQL'),
      );

      expect(context.engine, SqlEngineKind.sqlite);
      expect(context.engineLabel, 'SQLite');
      expect((await context.runQuery('retained', 'SELECT 1')).success, isTrue);
      expect(
        (await context.runScript('retained', 'SELECT 1; SELECT 2;')).success,
        isTrue,
      );
      expect(calls.map((call) => call.method), ['query', 'executeScript']);
      for (final call in calls) {
        expect(
          call.arguments['databasePath'],
          repository.databasePath('retained'),
        );
      }
      expect(calls.first.arguments['source'], 'SELECT 1');
      expect(calls.last.arguments['source'], 'SELECT 1; SELECT 2;');
    },
  );

  test('unavailable selected MySQL never opens a SQLite fallback', () async {
    await SqlEnginePreference.save(SqlEngineKind.localMysql);
    var sqliteOpens = 0;
    var mysqlOpens = 0;
    await expectLater(
      SqlExecutionContext.openLocal(
        openSqlite: () async {
          sqliteOpens++;
          return _Workspace('sqlite');
        },
        openMysql: () async {
          mysqlOpens++;
          throw StateError('selected MySQL runtime unavailable');
        },
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('MySQL runtime unavailable'),
        ),
      ),
    );
    expect(mysqlOpens, 1);
    expect(sqliteOpens, 0);
    expect(SqlEnginePreference.current, SqlEngineKind.localMysql);
  });

  test(
    'stale retained contexts reject queries and scripts before dispatch',
    () async {
      await SqlEnginePreference.save(SqlEngineKind.sqlite);
      final sqlite = _Workspace('sqlite');
      final context = await SqlExecutionContext.openLocal(
        openSqlite: () async => sqlite,
      );
      await context.runScript('sqlite', 'SELECT 1');
      expect(sqlite.scripts, ['SELECT 1']);

      await SqlEnginePreference.save(SqlEngineKind.localMysql);

      expect(context.isCurrent, isFalse);
      expect(() => context.repository, throwsStateError);
      await expectLater(
        context.runQuery('sqlite', 'SELECT 2'),
        throwsStateError,
      );
      await expectLater(
        context.runScript('sqlite', 'DELETE FROM t'),
        throwsStateError,
      );
      expect(sqlite.queries, isEmpty);
      expect(sqlite.scripts, ['SELECT 1']);

      // Returning to the same engine still invalidates the old connection epoch.
      await SqlEnginePreference.save(SqlEngineKind.sqlite);
      expect(context.isCurrent, isFalse);
      await expectLater(
        context.runQuery('sqlite', 'SELECT 3'),
        throwsStateError,
      );
      expect(sqlite.queries, isEmpty);
    },
  );

  test(
    'engine switch during asynchronous open cannot publish old context',
    () async {
      await SqlEnginePreference.save(SqlEngineKind.localMysql);
      final opened = Completer<SqlWorkspaceRepository>();
      final started = Completer<void>();
      final pending = SqlExecutionContext.openLocal(
        openMysql: () {
          started.complete();
          return opened.future;
        },
      );
      final rejected = expectLater(pending, throwsStateError);
      await started.future;

      await SqlEnginePreference.save(SqlEngineKind.sqlite);
      opened.complete(_Workspace('mysql'));

      await rejected;
      expect(SqlEnginePreference.current, SqlEngineKind.sqlite);
    },
  );

  test(
    'offline tools stay local while nonoffline cloud preference is retained',
    () async {
      StudioProfile.current = _onlineProfile;
      await SqlEnginePreference.save(SqlEngineKind.cloud);
      final sqlite = _Workspace('sqlite');
      final context = await SqlExecutionContext.openLocal(
        openSqlite: () async => sqlite,
        openMysql: () => throw StateError('cloud must not start MySQL'),
      );

      expect(SqlEnginePreference.current, SqlEngineKind.cloud);
      expect(context.engine, SqlEngineKind.sqlite);
      expect(context.repository, same(sqlite));
      expect(jsonDecode(preferenceFile.readAsStringSync())['engine'], 'cloud');

      StudioProfile.current = _offlineProfile;
      expect(await SqlEnginePreference.load(), SqlEngineKind.sqlite);
      await expectLater(
        SqlEnginePreference.save(SqlEngineKind.cloud),
        throwsUnsupportedError,
      );
    },
  );

  testWidgets(
    'workbench reconnects on preference change and retains unsaved SQL',
    (tester) async {
      await tester.runAsync(
        () => SqlEnginePreference.save(SqlEngineKind.sqlite),
      );
      tester.view.physicalSize = const Size(1100, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final sqlite = _Workspace('sqlite-owned');
      final mysql = _Workspace('mysql-owned');
      final store = ProjectStore();
      final auth = AuthStore();
      final settings = SettingsStore();
      addTearDown(store.dispose);
      addTearDown(auth.dispose);
      addTearDown(settings.dispose);
      addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
      final library = _MemoryLibrary(
        File(p.join(storage.path, 'queries.json')),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: SqlWorkbenchPage(
            store: store,
            auth: auth,
            settings: settings,
            embedded: true,
            localContextFactory: () => SqlExecutionContext.openLocal(
              openSqlite: () async => sqlite,
              openMysql: () async => mysql,
            ),
            queryLibraryFactory: () async => library,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('sqlite-owned'), findsNWidgets(2));
      expect(find.text('mysql-owned'), findsNothing);
      await tester.tap(find.byTooltip('数据库引擎'));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(PopupMenuItem<SqlEngineKind>, 'SQLite'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(PopupMenuItem<SqlEngineKind>, '本机 MySQL'),
        findsOneWidget,
      );
      expect(find.text('云 MySQL'), findsNothing);
      await tester.tapAt(const Offset(10, 200));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('SQL'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'SELECT unsaved_source;');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, '执行'));
      await tester.pumpAndSettle();
      expect(sqlite.scripts, ['SELECT unsaved_source;']);
      expect(find.text('sqlite-owned-result'), findsOneWidget);

      await tester.runAsync(() async {
        await SqlEnginePreference.save(SqlEngineKind.localMysql);
        // The notification starts reconnecting in this real-async zone. Drain
        // that work before returning to the widget binding's fake clock.
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();

      expect(find.text('本机 MySQL'), findsOneWidget);
      expect(find.text('mysql-owned'), findsNWidgets(2));
      expect(find.text('sqlite-owned'), findsNothing);
      expect(find.text('sqlite-owned-result'), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'SELECT unsaved_source;',
      );
      await tester.tap(find.widgetWithText(FilledButton, '执行'));
      await tester.pumpAndSettle();
      expect(mysql.scripts, ['SELECT unsaved_source;']);
      expect(sqlite.scripts, ['SELECT unsaved_source;']);
      expect(find.text('mysql-owned-result'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('busy workbench reconnects after an already submitted command', (
    tester,
  ) async {
    await tester.runAsync(() => SqlEnginePreference.save(SqlEngineKind.sqlite));
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final completing = Completer<SqlScriptResult>();
    final sqlite = _Workspace('sqlite-busy')..pendingScript = completing.future;
    final mysql = _Workspace('mysql-next');
    final store = ProjectStore();
    final auth = AuthStore();
    final settings = SettingsStore();
    addTearDown(store.dispose);
    addTearDown(auth.dispose);
    addTearDown(settings.dispose);
    addTearDown(() async {
      if (!completing.isCompleted) completing.complete(sqlite.result);
      await tester.pumpWidget(const SizedBox.shrink());
    });
    await tester.pumpWidget(
      MaterialApp(
        home: SqlWorkbenchPage(
          store: store,
          auth: auth,
          settings: settings,
          embedded: true,
          localContextFactory: () => SqlExecutionContext.openLocal(
            openSqlite: () async => sqlite,
            openMysql: () async => mysql,
          ),
          queryLibraryFactory: () async =>
              _MemoryLibrary(File(p.join(storage.path, 'busy-queries.json'))),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('SQL'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'SELECT submitted;');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '执行'));
    await tester.pump();
    expect(sqlite.scripts, ['SELECT submitted;']);

    await tester.runAsync(
      () => SqlEnginePreference.save(SqlEngineKind.localMysql),
    );
    await tester.pump();
    expect(find.text('mysql-next'), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '执行'))
          .onPressed,
      isNull,
    );
    completing.complete(sqlite.result);
    await tester.pumpAndSettle();

    expect(find.text('本机 MySQL'), findsOneWidget);
    expect(find.text('mysql-next'), findsNWidgets(2));
    expect(find.text('sqlite-busy-result'), findsNothing);
    expect(mysql.scripts, isEmpty);
    await tester.tap(find.widgetWithText(FilledButton, '执行'));
    await tester.pumpAndSettle();
    expect(mysql.scripts, ['SELECT submitted;']);
    expect(sqlite.scripts, ['SELECT submitted;']);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

const _nativeResult = {
  'available': true,
  'exitCode': 0,
  'error': '',
  'columns': ['value'],
  'rows': [
    ['1'],
  ],
  'affectedRows': 0,
  'truncated': false,
};

class _Workspace extends SqlWorkspaceRepository {
  _Workspace(this.name) : super(root: Directory.systemTemp);

  final String name;
  final scripts = <String>[];
  final queries = <String>[];
  Future<SqlScriptResult>? pendingScript;

  SqlScriptResult get result {
    final query = SqlQueryResult(
      available: true,
      exitCode: 0,
      columns: const ['value'],
      rows: [
        ['$name-result'],
      ],
      affectedRows: 0,
      truncated: false,
    );
    return SqlScriptResult(summary: query, results: [query]);
  }

  @override
  Future<List<String>> listDatabases() async => [name];

  @override
  Future<List<String>> listTables(String databaseName) async => [];

  @override
  Future<SqlQueryResult> runQuery(String databaseName, String source) async {
    expect(databaseName, name);
    queries.add(source);
    return result.summary;
  }

  @override
  Future<SqlScriptResult> runScript(String databaseName, String source) async {
    expect(databaseName, name);
    scripts.add(source);
    return pendingScript ?? result;
  }
}

class _MemoryLibrary extends SqlQueryLibrary {
  _MemoryLibrary(File file) : super(file: file);

  @override
  Future<void> recordExecution({
    required String database,
    required String source,
    required bool success,
  }) async {}
}
