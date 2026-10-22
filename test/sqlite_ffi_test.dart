import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_sql/sql_database.dart';
import 'package:qfli_sql/sql_runner.dart';
import 'package:qfli_sql/sql_workspace_repository.dart';
import 'package:qfli_sql/sqlite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final platform = Platform.operatingSystem;
  final library =
      Platform.environment['QFLI_SQLITE_LIBRARY'] ??
      p.join(
        Directory.current.path,
        'native',
        'build',
        platform,
        Platform.isWindows ? 'qfli_sqlite.dll' : 'libqfli_sqlite.so',
      );
  final missing = !File(library).existsSync();

  group(
    'retained upstream SQLite C engine',
    () {
      late Directory root;
      late String databasePath;
      setUp(() async {
        root = await Directory.systemTemp.createTemp('qfli_sqlite_ffi_');
        databasePath = p.join(root.path, 'data.sqlite');
      });
      tearDown(() => root.delete(recursive: true));

      Future<SqlQueryResult> query(
        String source, [
        List<String?> values = const [],
      ]) async => SqlQueryResult.fromNative(
        await SqliteFfi.invoke('query', {
          'databasePath': databasePath,
          'source': source,
          'params': values,
        }, libraryPath: library),
      );

      test('script, grid and editor use the same persisted C database', () async {
        final engine = const NativeLocalSqlEngine();
        final script = await engine.execute(
          SqliteRequest(
            projectPath: root.path,
            source:
                'CREATE TABLE people (id INTEGER PRIMARY KEY, name TEXT); '
                "INSERT INTO people (name) VALUES ('Ada'); SELECT name FROM people;",
          ),
        );
        expect(script.available, isTrue, reason: script.stderr.join('\n'));
        expect(script.exitCode, 0);
        expect(script.stdout, ['Ada']);
        expect(
          File(p.join(root.path, '.qfli', 'data.sqlite')).existsSync(),
          isTrue,
        );

        final entry = File(p.join(root.path, 'main.sql'))
          ..writeAsStringSync('SELECT id, name FROM people;');
        final run = await SqlProgramRunner(
          engine: engine,
        ).run(projectPath: root.path, entryFile: entry.path);
        expect(await run!.stdout.toList(), ['1\tAda']);
        expect(await run.exitCode, 0);
      });

      test(
        'binds quotes, UTF-8, embedded NUL and NULL without rewriting SQL',
        () async {
          expect(
            (await query('CREATE TABLE items (value TEXT, note TEXT)')).success,
            isTrue,
          );
          const text = "O'Brien \u4e2d\u6587 \u{1f600}\x00tail";
          final inserted = await query('INSERT INTO items VALUES (?, ?)', [
            text,
            null,
          ]);
          expect(inserted.success, isTrue, reason: inserted.error);
          expect(inserted.affectedRows, 1);
          final result = await query(
            'SELECT value, note FROM items WHERE value = ?',
            [text],
          );
          expect(result.rows, [
            [text, null],
          ]);
          final update = await query(
            'UPDATE items SET note = ? WHERE value = ?',
            ['ok', text],
          );
          expect(update.affectedRows, 1);
          expect((await query('SELECT note FROM items')).rows, [
            ['ok'],
          ]);
        },
      );

      test(
        'reports SQL and parameter errors and rejects a second statement',
        () async {
          expect(
            (await query('SELECT missing FROM unknown_table')).success,
            isFalse,
          );
          final parameters = await query('SELECT ?');
          expect(parameters.available, isTrue);
          expect(parameters.error, contains('parameter count'));
          final multiple = await query(
            'SELECT 1; CREATE TABLE forbidden (id INTEGER);',
          );
          expect(multiple.error, contains('Only one SQL statement'));
          expect(
            (await query(
              "SELECT name FROM sqlite_master WHERE name = 'forbidden'",
            )).rows,
            isEmpty,
          );
          final later = await query('SELECT 42 AS answer');
          expect(later.success, isTrue);
          expect(later.rows, [
            ['42'],
          ]);
        },
      );

      test(
        'truncates rows and oversized cells without returning partial rows',
        () async {
          final rows = await query(
            'WITH RECURSIVE numbers(n) AS '
            '(SELECT 1 UNION ALL SELECT n + 1 FROM numbers WHERE n < 501) SELECT n FROM numbers',
          );
          expect(rows.truncated, isTrue);
          expect(rows.rows.length, 500);
          final bytes = await query(
            "SELECT replace(hex(zeroblob(524289)), '0', 'x') AS large",
          );
          expect(bytes.truncated, isTrue);
          expect(bytes.rows, isEmpty);
        },
      );

      test(
        'structured scripts use native statement boundaries and one transaction',
        () async {
          const database = NativeSqliteDatabase();
          final script = await database.executeScript(
            databasePath: databasePath,
            source:
                "BEGIN; CREATE TABLE script_items (text TEXT); "
                "INSERT INTO script_items VALUES ('semi;colon'); COMMIT; "
                "SELECT text FROM script_items; SELECT NULL AS note;",
          );
          expect(script.success, isTrue, reason: script.error);
          expect(script.results.length, 6);
          expect(script.results[4].rows, [
            ['semi;colon'],
          ]);
          expect(script.results[5].rows, [
            [null],
          ]);
          final failed = await database.executeScript(
            databasePath: databasePath,
            source:
                "SELECT text FROM script_items; SELECT missing FROM script_items;",
          );
          expect(failed.success, isFalse);
          expect(failed.results.first.rows, [
            ['semi;colon'],
          ]);
          expect(failed.error, contains('missing'));
          expect(
            (await query('SELECT text FROM script_items')).success,
            isTrue,
          );
        },
      );

      test(
        'script cap ignores trailing trivia and refuses statement 513 before mutation',
        () async {
          Future<SqlScriptResult> script(String source) async =>
              SqlScriptResult.fromNative(
                await SqliteFfi.invoke('executeScript', {
                  'databasePath': databasePath,
                  'source': source,
                }, libraryPath: library),
              );
          final boundary =
              '${List.filled(511, 'SELECT 1 WHERE 0;').join()}'
              "SELECT 'kept' AS marker;";
          for (final suffix in [
            ' \r\n\t ',
            '-- trailing comment\n',
            '/* trailing comment */',
            '; ; /* trailing comment */ ; -- final comment',
          ]) {
            final result = await script('$boundary$suffix');
            expect(result.success, isTrue, reason: '$suffix: ${result.error}');
            expect(result.truncated, isFalse);
            expect(result.results.length, 512);
            expect(result.results.last.rows, [
              ['kept'],
            ]);
            expect(result.summary.rows, result.results.last.rows);
          }
          expect(
            (await query('CREATE TABLE cap_guard (value TEXT)')).success,
            isTrue,
          );
          final refused = await script(
            "$boundary ; /* separator */ INSERT INTO cap_guard VALUES ('forbidden');",
          );
          expect(refused.success, isFalse);
          expect(refused.error, contains('512 statement limit'));
          expect(refused.truncated, isFalse);
          expect(refused.results.length, 512);
          expect(refused.results.every((result) => result.success), isTrue);
          expect(refused.results.last.rows, [
            ['kept'],
          ]);
          expect((await query('SELECT count(*) FROM cap_guard')).rows, [
            ['0'],
          ]);
          // The refused prepared handle is finalized and its connection closed.
          expect((await query('DROP TABLE cap_guard')).success, isTrue);
        },
      );

      test(
        'workspace creates, edits and deletes persisted rows through default FFI',
        () async {
          final workspace = SqlWorkspaceRepository(root: root);
          await workspace.createDatabase('work');
          await workspace.createTable('work', 'people', const [
            SqlColumnDraft(name: 'id', type: 'INTEGER', primaryKey: true),
            SqlColumnDraft(name: 'name', type: 'TEXT'),
          ]);
          await workspace.insertRow('work', 'people', {'name': 'Ada'});
          var page = await workspace.loadTable('work', 'people');
          expect(page.rows, [
            ['1', 'Ada'],
          ]);
          await workspace.updateCell(
            'work',
            'people',
            page.rowIds.single,
            'name',
            'Grace',
          );
          page = await workspace.loadTable('work', 'people');
          expect(page.rows, [
            ['1', 'Grace'],
          ]);
          await workspace.deleteRow('work', 'people', page.rowIds.single);
          expect((await workspace.loadTable('work', 'people')).rows, isEmpty);
        },
      );
    },
    skip: missing
        ? 'Build native/runtime for $platform before running this suite.'
        : false,
  );

  test(
    'does not substitute another engine when the native library is missing',
    () async {
      await expectLater(
        SqliteFfi.invoke(
          'query',
          {
            'databasePath': ':memory:',
            'source': 'SELECT 1',
            'params': <String?>[],
          },
          libraryPath: p.join(
            Directory.systemTemp.path,
            'missing_qfli_sqlite_library',
          ),
        ),
        throwsArgumentError,
      );
    },
  );
}
