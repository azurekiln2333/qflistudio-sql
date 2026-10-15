import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_sql/android_mysql_runtime.dart';
import 'package:qfli_sql/mysql_database.dart';
import 'package:qfli_sql/mysql_ffi.dart';
import 'package:qfli_sql/mysql_workspace_repository.dart';
import 'package:qfli_sql/sql_runner.dart';
import 'package:qfli_sql/sql_engine_preference.dart';
import 'package:qfli_sql/sql_workspace_repository.dart';
import 'package:qfli_sql/sql_query_library.dart';
import 'package:qfli_sql/sql_workbench_page.dart';
import 'package:qfli_studio_core/services/app_paths.dart';
import 'package:qfli_studio_core/store/auth_store.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/store/settings_store.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await _requireAndroidTestSandbox();
    final runtime = await AndroidMySqlRuntime.prepare();
    if (!p.split(runtime.dataDirectory.path).contains(_testPackage)) {
      throw StateError('Refusing the production Android MySQL runtime.');
    }
  });

  testWidgets(
    'actual Android Oracle lifecycle, workspace and editor',
    (tester) async {
      final runtime = await AndroidMySqlRuntime.prepare();
      final previousEngine = await SqlEnginePreference.load();
      addTearDown(() => SqlEnginePreference.save(previousEngine));
      await SqlEnginePreference.save(SqlEngineKind.localMysql);
      const database = NativeMySqlDatabase();
      final schema = 'android_${DateTime.now().microsecondsSinceEpoch}';
      final project = await Directory.systemTemp.createTemp('oracle-project-');
      addTearDown(() => project.delete(recursive: true));
      addTearDown(runtime.stop);
      final workspace = MySqlWorkspaceRepository(
        runtimeDirectory: project,
        database: database,
      );
      var schemaOwned = false;
      addTearDown(() async {
        // The marker belongs to this freshly created test project and is only
        // published after the editor successfully creates its random schema.
        // Read it here so a failing editor assertion still cleans owned data.
        final marker = File(p.join(project.path, '.qfli', 'mysql.json'));
        if (await marker.exists()) {
          final data = jsonDecode(await marker.readAsString()) as Map;
          final editorSchema = data['schema'];
          expect(editorSchema, isA<String>());
          expect(editorSchema, matches(r'^qfli_project_[a-z0-9_]{1,48}$'));
          final dropped = await database.query(
            databasePath: '',
            source: 'DROP DATABASE `$editorSchema`',
          );
          expect(dropped.success, isTrue, reason: dropped.error);
        }
      });
      addTearDown(() async {
        if (!schemaOwned) return;
        final dropped = await database.query(
          databasePath: '',
          source: 'DROP DATABASE `$schema`',
        );
        expect(dropped.success, isTrue, reason: dropped.error);
      });

      final version = await database.query(
        databasePath: '',
        source:
            'SELECT VERSION(), @@version_comment, @@port, @@skip_networking',
      );
      expect(version.success, isTrue, reason: version.error);
      expect(version.rows.single.first, '8.4.6');
      expect(version.rows.toString(), isNot(contains('MariaDB')));
      expect(version.rows.single.last, '1');
      await workspace.createDatabase(schema);
      schemaOwned = true;
      await workspace.createTable(schema, 'people', const [
        SqlColumnDraft(name: 'id', type: 'BIGINT', primaryKey: true),
        SqlColumnDraft(name: 'name', type: 'TEXT'),
        SqlColumnDraft(name: 'note', type: 'TEXT'),
      ]);
      await workspace.insertRow(schema, 'people', {
        'id': '9007199254740993',
        'name': "O'Brien",
        'note': null,
      });
      var page = await workspace.loadTable(schema, 'people');
      expect(page.rows, [
        ['9007199254740993', "O'Brien", null],
      ]);
      await workspace.updateCell(
        schema,
        'people',
        page.rowIds.single,
        'note',
        'persisted',
      );
      page = await workspace.loadTable(schema, 'people');
      expect(page.rows.single.last, 'persisted');

      final binary = await database.query(
        databasePath: schema,
        source: 'SELECT ? AS value, NULL AS missing, X\'00FF\' AS bytes',
        parameters: ['quoted; value'],
      );
      expect(binary.success, isTrue, reason: binary.error);
      expect(binary.rows, [
        ['quoted; value', null, '00FF'],
      ]);
      final unicode = await database.query(
        databasePath: schema,
        source:
            "SELECT REGEXP_LIKE('\u4f60\u597d\u4e16\u754c', '^\u4f60\u597d')",
      );
      expect(unicode.success, isTrue, reason: unicode.error);
      expect(unicode.rows, [
        ['1'],
      ]);
      final script = await database.executeScript(
        databasePath: schema,
        source:
            "START TRANSACTION; INSERT INTO people VALUES (2,'rollback',NULL); ROLLBACK; "
            "SELECT COUNT(*) FROM people; SELECT 'semi;colon';",
      );
      expect(script.success, isTrue, reason: script.error);
      expect(script.results[3].rows, [
        ['1'],
      ]);
      expect(script.results[4].rows, [
        ['semi;colon'],
      ]);
      final partial = await database.executeScript(
        databasePath: schema,
        source:
            'INSERT INTO people VALUES (3,\'committed\',NULL); SELECT missing FROM people;',
      );
      expect(partial.available, isTrue);
      expect(partial.success, isFalse);
      expect(partial.results.first.affectedRows, 1);
      expect(partial.error, contains('missing'));

      final socketResult = await database.query(
        databasePath: '',
        source: 'SELECT @@socket',
      );
      expect(socketResult.success, isTrue, reason: socketResult.error);
      final socket = socketResult.rows.single.single!;
      final rejected = await MySqlFfi.invoke(runtime.libraryPath, {
        'method': 'query',
        'socket': socket,
        'password': 'wrong',
        'schema': schema,
        'source': 'SELECT 1',
        'params': <String?>[],
      });
      expect(rejected['available'], isFalse);
      expect(rejected['error'].toString(), contains('Access denied'));
      final metadata =
          jsonDecode(
                await File(
                  p.join(runtime.dataDirectory.path, 'initialized.json'),
                ).readAsString(),
              )
              as Map;
      expect(metadata['password'], matches(r'^[a-f0-9]{64}$'));

      await runtime.stop();
      final persisted = await database.query(
        databasePath: schema,
        source: 'SELECT id,note FROM people ORDER BY id',
      );
      expect(persisted.success, isTrue, reason: persisted.error);
      expect(persisted.rows, [
        ['3', null],
        ['9007199254740993', 'persisted'],
      ]);

      const editor = PreferredSqlEngine();
      final written = await editor.execute(
        SqlProgramRequest(
          projectPath: project.path,
          source:
              "CREATE TABLE items (value TEXT); INSERT INTO items VALUES ('editor'); SELECT value FROM items;",
        ),
      );
      expect(written.exitCode, 0, reason: written.stderr.join('\n'));
      expect(written.stdout.join('\n'), contains('editor'));
      expect(
        await File(p.join(project.path, '.qfli', 'mysql.json')).exists(),
        isTrue,
      );
      final read = await editor.execute(
        SqlProgramRequest(
          projectPath: project.path,
          source: 'SELECT value FROM items;',
        ),
      );
      expect(read.exitCode, 0, reason: read.stderr.join('\n'));
      expect(read.stdout.join('\n'), contains('editor'));
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );

  testWidgets(
    'workbench switches actual engines and stops its Oracle server',
    (tester) async {
      final previous = await SqlEnginePreference.load();
      addTearDown(() => SqlEnginePreference.save(previous));
      final temporary = await Directory.systemTemp.createTemp(
        'oracle-workbench-',
      );
      addTearDown(() => temporary.delete(recursive: true));
      final runtime = await AndroidMySqlRuntime.prepare();
      addTearDown(runtime.stop);
      final oracle = await MySqlWorkspaceRepository.openLocal();
      final sqlite = await SqlWorkspaceRepository.openDefault();
      final name = 'engine_${DateTime.now().microsecondsSinceEpoch}';
      var oracleOwned = false;
      var sqliteOwned = false;
      addTearDown(() async {
        if (oracleOwned) await oracle.deleteDatabase(name);
      });
      addTearDown(() async {
        if (sqliteOwned) await sqlite.deleteDatabase(name);
      });
      await oracle.createDatabase(name);
      oracleOwned = true;
      await sqlite.createDatabase(name);
      sqliteOwned = true;
      final store = ProjectStore();
      final auth = AuthStore();
      final settings = SettingsStore();
      addTearDown(store.dispose);
      addTearDown(auth.dispose);
      addTearDown(settings.dispose);
      addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
      for (final repository in [oracle, sqlite]) {
        await repository.createTable(name, 'items', const [
          SqlColumnDraft(name: 'id', type: 'INTEGER', primaryKey: true),
          SqlColumnDraft(name: 'value', type: 'TEXT'),
        ]);
        await repository.insertRow(name, 'items', {
          'value': repository == oracle ? 'OracleOnly' : 'SQLiteOnly',
        });
      }
      final library = await SqlQueryLibrary.open(
        File(p.join(temporary.path, 'queries.json')),
      );
      await SqlEnginePreference.save(SqlEngineKind.sqlite);
      await tester.pumpWidget(
        MaterialApp(
          home: SqlWorkbenchPage(
            store: store,
            auth: auth,
            settings: settings,
            queryLibraryFactory: () async => library,
          ),
        ),
      );
      await tester.pumpAndSettle();

      Future<void> selectTable() async {
        final backToTree = find.byTooltip('返回数据库');
        if (backToTree.evaluate().isNotEmpty) {
          await tester.tap(backToTree);
          await tester.pumpAndSettle();
        }
        final databaseTile = find.widgetWithText(ListTile, name).first;
        await tester.ensureVisible(databaseTile);
        await tester.tap(databaseTile);
        await tester.pumpAndSettle();
        final tableTile = find.widgetWithText(ListTile, 'items').first;
        await tester.ensureVisible(tableTile);
        await tester.tap(tableTile);
        await tester.pumpAndSettle();
      }

      await selectTable();
      expect(find.text('SQLiteOnly'), findsOneWidget);
      await tester.tap(find.byTooltip('数据库引擎'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('本机 MySQL').last);
      await tester.pumpAndSettle();
      await selectTable();
      expect(find.text('OracleOnly'), findsOneWidget);
      expect(find.text('SQLiteOnly'), findsNothing);
      final storage = await AppPaths.storageDirectory();
      final saved =
          jsonDecode(
                await File(p.join(storage!, 'sql_engine.json')).readAsString(),
              )
              as Map;
      expect(saved['engine'], 'localMysql');
      await tester.tap(find.text('OracleOnly'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Edited');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(
        (await oracle.loadTable(name, 'items')).rows.single.last,
        'Edited',
      );
      final serverPid = int.parse(
        await File(
          p.join(runtime.dataDirectory.path, 'mysqld.pid'),
        ).readAsString(),
      );
      await tester.tap(find.byTooltip('数据库引擎'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('SQLite').last);
      await tester.pumpAndSettle();
      expect(await File('/proc/$serverPid/stat').exists(), isFalse);
      await selectTable();
      expect(find.text('SQLiteOnly'), findsOneWidget);
      expect(find.text('Edited'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}

const _testPackage = 'com.azurekiln.qfli.sqlab.integrationtest';

Future<void> _requireAndroidTestSandbox() async {
  if (!Platform.isAndroid) {
    throw UnsupportedError(
      'This target requires the isolated Android test app.',
    );
  }
  // /proc is read-only here. Verify the process identity before preparing the
  // runtime, writing preferences or opening any default database directory.
  final process = utf8.decode(
    (await File(
      '/proc/self/cmdline',
    ).readAsBytes()).takeWhile((byte) => byte != 0).toList(),
  );
  if (process != _testPackage) {
    throw StateError('Refusing the production Android application sandbox.');
  }
}
