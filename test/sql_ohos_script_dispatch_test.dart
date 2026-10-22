import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_sql/sql_database.dart';

Map<String, Object?> nativeResult({
  int exitCode = 0,
  String error = '',
  List<String> columns = const [],
  List<List<String?>> rows = const [],
  int affectedRows = 0,
  bool truncated = false,
}) => {
  'available': true,
  'exitCode': exitCode,
  'error': error,
  'columns': columns,
  'rows': rows,
  'affectedRows': affectedRows,
  'truncated': truncated,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('qfli_sql/ohos_script_test');
  const database = NativeSqliteDatabase(channel: channel);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('routes multi-statement scripts to the native script channel', () async {
    final directory = await Directory.systemTemp.createTemp(
      'qfli_ohos_script_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final path = p.join(directory.path, 'nested', 'data.sqlite');
    messenger.setMockMethodCallHandler(channel, (call) async {
      // A grid query would reject the second statement, so the script must not
      // be disguised as a query on OHOS.
      expect(call.method, 'executeScript');
      expect(call.arguments, {
        'source':
            "BEGIN; CREATE TABLE t (v TEXT); "
            "INSERT INTO t VALUES ('semi;colon'); COMMIT; SELECT v FROM t;",
        'databasePath': path,
      });
      expect(Directory(p.dirname(path)).existsSync(), isTrue);
      return {
        ...nativeResult(affectedRows: 0),
        'results': [
          nativeResult(),
          nativeResult(),
          nativeResult(affectedRows: 1),
          nativeResult(),
          nativeResult(
            columns: ['v'],
            rows: [
              ['semi;colon'],
            ],
          ),
        ],
      };
    });

    final script = await database.executeScript(
      databasePath: path,
      source:
          "BEGIN; CREATE TABLE t (v TEXT); "
          "INSERT INTO t VALUES ('semi;colon'); COMMIT; SELECT v FROM t;",
    );

    expect(script.success, isTrue, reason: script.error);
    expect(script.summary.exitCode, 0);
    expect(script.results.length, 5);
    expect(script.results[2].affectedRows, 1);
    expect(script.results[4].rows, [
      ['semi;colon'],
    ]);
  });

  test('keeps completed results and the real native error', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => {
        ...nativeResult(
          exitCode: 1,
          error: 'no such column: missing',
          truncated: false,
        ),
        'results': [
          nativeResult(
            columns: ['v'],
            rows: [
              ['semi;colon'],
            ],
          ),
        ],
      },
    );

    final script = await database.executeScript(
      databasePath: ':memory:',
      source: "SELECT v FROM t; SELECT missing FROM t;",
    );

    expect(script.success, isFalse);
    expect(script.available, isTrue);
    expect(script.exitCode, 1);
    expect(script.error, contains('missing'));
    expect(script.results, hasLength(1));
    expect(script.results.first.rows, [
      ['semi;colon'],
    ]);
  });

  test('keeps the shared truncation limit visible in the summary', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => {
        ...nativeResult(
          exitCode: 1,
          error: 'SQL script output exceeds the display limits.',
          truncated: true,
          columns: ['n'],
          rows: [
            ['1'],
          ],
        ),
        'results': [
          nativeResult(
            columns: ['n'],
            rows: [
              ['1'],
            ],
            truncated: true,
          ),
        ],
      },
    );

    final script = await database.executeScript(
      databasePath: ':memory:',
      source: 'SELECT 1; SELECT 2;',
    );

    expect(script.truncated, isTrue);
    expect(script.exitCode, 1);
    expect(script.error, contains('display limits'));
    expect(script.results.single.truncated, isTrue);
  });

  test('converts channel failures into an unavailable summary', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => throw PlatformException(
        code: 'SQL_NATIVE_FAILED',
        message: 'executeScript is not implemented',
      ),
    );

    final script = await database.executeScript(
      databasePath: ':memory:',
      source: 'SELECT 1;',
    );

    expect(script.available, isFalse);
    expect(script.exitCode, 127);
    expect(script.error, contains('not implemented'));
    expect(script.results, isEmpty);
  });

  test('rejects a payload without per-statement results', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => nativeResult());

    final script = await database.executeScript(
      databasePath: ':memory:',
      source: 'SELECT 1;',
    );

    expect(script.available, isFalse);
    expect(script.exitCode, 127);
    expect(script.error, contains('Invalid native script results'));
  });
}
