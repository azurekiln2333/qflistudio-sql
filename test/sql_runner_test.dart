import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/services/studio_profile.dart';

import 'package:qfli_sql/sql_runner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SqlProgramRunner', () {
    test('does not claim SQL ran when the native channel is absent', () async {
      final project = await Directory.systemTemp.createTemp('qfli_sql_test_');
      addTearDown(() => project.delete(recursive: true));
      final entry = File(p.join(project.path, 'main.sql'))
        ..writeAsStringSync('SELECT 1;');

      final result = await const SqlProgramRunner().run(
        projectPath: project.path,
        entryFile: entry.path,
      );

      expect(result, isNotNull);
      expect(result!.title, '运行 main.sql');
      expect(await result.stdout.toList(), isEmpty);
      expect(await result.stderr.toList(), ['当前设备无法连接 SQLite 引擎。']);
      expect(await result.exitCode, kProgramNotRunExitCode);
    });

    test('returns null for files outside the SQL backend', () async {
      final result = await const SqlProgramRunner().run(
        projectPath: r'C:\projects\demo',
        entryFile: r'C:\projects\demo\main.py',
      );

      expect(result, isNull);
    });

    test(
      'passes the source and project database boundary to an engine',
      () async {
        final project = await Directory.systemTemp.createTemp('qfli_sql_test_');
        addTearDown(() => project.delete(recursive: true));
        final entry = File(p.join(project.path, 'main.SQL'))
          ..writeAsStringSync('SELECT 1 AS id;');
        final engine = _RecordingEngine();

        final result = await SqlProgramRunner(
          engine: engine,
        ).run(projectPath: project.path, entryFile: entry.path);

        expect(engine.request, isNotNull);
        expect(engine.request!.projectPath, project.path);
        expect(
          engine.request!.databasePath,
          p.join(project.path, '.qfli', 'data.sqlite'),
        );
        expect(engine.request!.source, 'SELECT 1 AS id;');
        expect(await result!.stdout.toList(), ['1 | Ada']);
        expect(await result.stderr.toList(), isEmpty);
        expect(await result.exitCode, 0);
        expect(result.title, '运行 main.SQL');
      },
    );
  });

  group('NativeSqliteEngine', () {
    const channel = MethodChannel('qfli_sql/native/test');
    const engine = NativeSqliteEngine(channel: channel);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    test(
      'creates the database directory and passes source to native code',
      () async {
        final project = await Directory.systemTemp.createTemp(
          'qfli_native_test_',
        );
        addTearDown(() => project.delete(recursive: true));
        final request = SqliteRequest(
          projectPath: project.path,
          source: 'SELECT 1;',
        );
        messenger.setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'execute');
          expect(call.arguments, {
            'source': 'SELECT 1;',
            'databasePath': request.databasePath,
          });
          expect(
            Directory(p.dirname(request.databasePath)).existsSync(),
            isTrue,
          );
          return {
            'available': true,
            'exitCode': 0,
            'output': '1\n2\n',
            'error': null,
            'truncated': false,
          };
        });

        final result = await engine.execute(request);
        expect(result.available, isTrue);
        expect(result.stdout, ['1', '2']);
        expect(result.stderr, isEmpty);
        expect(result.exitCode, 0);
      },
    );

    test('preserves native SQL errors and truncated output', () async {
      final project = await Directory.systemTemp.createTemp(
        'qfli_native_test_',
      );
      addTearDown(() => project.delete(recursive: true));
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {
          'available': true,
          'exitCode': 1,
          'output': 'partial\n',
          'error': 'Query output exceeds the 1 MiB display limit.',
          'truncated': true,
        },
      );

      final result = await engine.execute(
        SqliteRequest(projectPath: project.path, source: 'SELECT * FROM big;'),
      );
      expect(result.available, isTrue);
      expect(result.exitCode, 1);
      expect(result.stdout, ['partial']);
      expect(result.stderr, contains('查询结果超过显示上限，输出已截断。'));
    });

    test('rejects malformed native responses', () async {
      final project = await Directory.systemTemp.createTemp(
        'qfli_native_test_',
      );
      addTearDown(() => project.delete(recursive: true));
      messenger.setMockMethodCallHandler(channel, (_) async => {'exitCode': 0});

      final result = await engine.execute(
        SqliteRequest(projectPath: project.path, source: 'SELECT 1;'),
      );
      expect(result.available, isFalse);
      expect(result.exitCode, kProgramNotRunExitCode);
    });
  });
}

class _RecordingEngine implements SqliteEngine {
  SqliteRequest? request;

  @override
  Future<SqliteExecutionResult> execute(SqliteRequest request) async {
    this.request = request;
    return const SqliteExecutionResult(
      available: true,
      stdout: ['1 | Ada'],
      stderr: [],
      exitCode: 0,
    );
  }
}
