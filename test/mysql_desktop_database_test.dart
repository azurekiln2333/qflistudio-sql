import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_sql/local_mysql_runtime.dart';
import 'package:qfli_sql/mysql_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final bundle = Platform.environment['QFLI_MYSQL_TEST_BUNDLE'];
  group(
    'real desktop Oracle adapter',
    () {
      late Directory root;
      late LocalMySqlRuntime runtime;
      late NativeMySqlDatabase database;
      setUpAll(() async {
        root = await Directory.systemTemp.createTemp('qfli-mysql-adapter-');
        runtime = LocalMySqlRuntime(
          bundleDirectory: Directory(bundle!),
          dataDirectory: root,
          libraryPath: p.join(
            bundle,
            Platform.isWindows ? 'bin' : 'lib',
            Platform.isWindows
                ? 'qfli_mysql_bridge.dll'
                : 'libqfli_mysql_bridge.${Platform.isMacOS ? 'dylib' : 'so'}',
          ),
          launcherPath: p.join(
            bundle,
            'bin',
            Platform.isWindows
                ? 'qfli_mysql_launcher.exe'
                : 'qfli_mysql_launcher',
          ),
          serverUser: Platform.environment['QFLI_MYSQL_TEST_USER'],
          serverPath: Platform.environment['QFLI_MYSQL_TEST_SERVER'],
          pluginDirectory:
              Platform.environment['QFLI_MYSQL_TEST_PLUGIN_DIRECTORY'],
        );
        database = NativeMySqlDatabase(runtime: runtime);
      });
      tearDownAll(() async {
        await runtime.stop();
        await root.delete(recursive: true);
      });
      test('retains native exact values, NULL and binary metadata', () async {
        final result = await database.query(
          databasePath: '',
          source:
              'SELECT CAST(? AS SIGNED) AS id, CAST(? AS DECIMAL(30,6)) AS amount, UNHEX(?) AS bytes, ? AS note',
          parameters: [
            '9007199254740993',
            '123456789012345678901234.123456',
            '00FF41',
            null,
          ],
        );
        expect(result.success, isTrue, reason: result.error);
        expect(result.rows.single, [
          '9007199254740993',
          '123456789012345678901234.123456',
          '00FF41',
          null,
        ]);
        expect(result.columnInfo[2].binary, isTrue);
      });
      test(
        'decodes ordered scripts and preserves errors after mutation',
        () async {
          final result = await database.executeScript(
            databasePath: '',
            source:
                'CREATE DATABASE adapter; USE adapter; CREATE TABLE items (id INT PRIMARY KEY); INSERT INTO items VALUES (1); SELEC invalid;',
          );
          expect(result.available, isTrue);
          expect(result.success, isFalse);
          expect(result.exitCode, 1064);
          expect(result.summary.sqlState, '42000');
          expect(result.results, hasLength(4));
          final persisted = await database.query(
            databasePath: 'adapter',
            source: 'SELECT id FROM items',
          );
          expect(persisted.rows.single, ['1']);
        },
      );
    },
    skip: bundle == null
        ? 'Set QFLI_MYSQL_TEST_BUNDLE to a built Oracle bundle.'
        : false,
  );

  test('missing desktop bundle returns an unavailable typed result', () async {
    final root = await Directory.systemTemp.createTemp('qfli-mysql-missing-');
    final runtime = LocalMySqlRuntime(
      bundleDirectory: root,
      dataDirectory: root,
      libraryPath: p.join(root.path, 'missing-library'),
      launcherPath: p.join(root.path, 'missing-launcher'),
    );
    try {
      final database = NativeMySqlDatabase(runtime: runtime);
      final result = await database.query(databasePath: '', source: 'SELECT 1');
      expect(result.available, isFalse);
      expect(result.exitCode, 127);
      expect(result.error, contains('Missing bundled MySQL file'));
      final script = await database.executeScript(
        databasePath: '',
        source: 'SELECT 1;',
      );
      expect(script.available, isFalse);
      expect(script.results, isEmpty);
    } finally {
      await runtime.stop();
      await root.delete(recursive: true);
    }
  });
}
