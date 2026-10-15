import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_sql/main.dart' show sqlProfile;
import 'package:qfli_sql/sql_runner.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/terminal/shell/sandbox_shell_backend.dart';
import 'package:qfli_studio_core/terminal/shell/shell_backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory storage;
  late Directory project;
  late _Engine engine;
  late List<ShellChunk> output;

  setUp(() {
    storage = Directory.systemTemp.createTempSync('sql_terminal_');
    project = Directory(p.join(storage.path, 'project'))..createSync();
    Directory(p.join(project.path, '.qfli')).createSync();
    File(p.join(project.path, '.qfli', 'project.json')).writeAsStringSync('{}');
    engine = _Engine();
    output = [];
  });

  tearDown(() => storage.deleteSync(recursive: true));

  SandboxShellBackend terminal({String? cwd}) {
    final backend = SandboxShellBackend(
      sandboxRoot: storage.path,
      startDirectory: cwd ?? project.path,
      delegate: (backend, command) =>
          SqlTerminalCommands.execute(backend, command, engine: engine),
    );
    final subscription = backend.output.listen(output.add);
    addTearDown(() async {
      await subscription.cancel();
      await backend.shutdown();
    });
    return backend;
  }

  test(
    'profile wires SQL commands into both shared terminal consumers',
    () async {
      final delegate = sqlProfile.terminalCommandDelegate;
      expect(delegate, isNotNull);
      final backend = terminal();
      expect(await delegate!(backend, 'sql --help'), isTrue);
      expect(output.map((chunk) => chunk.text).join(), contains('sql -e'));
      expect(engine.requests, isEmpty);
    },
  );

  test(
    'standalone and editor terminals share a nested script project',
    () async {
      final entry = File(p.join(project.path, 'src', 'with spaces.SQL'));
      entry.parent.createSync();
      entry.writeAsStringSync("SELECT '中文' AS label;");
      final standalone = terminal(cwd: storage.path);
      final editor = terminal(cwd: project.path);

      await standalone.execute('sql "project/src/with spaces.SQL"');
      await editor.execute('sql "src/with spaces.SQL"');

      expect(engine.requests, hasLength(2));
      for (final request in engine.requests) {
        expect(request.projectPath, project.path);
        expect(
          request.databasePath,
          p.join(project.path, '.qfli', 'data.sqlite'),
        );
        expect(request.source, "SELECT '中文' AS label;");
      }
      expect(standalone.lastExitCode, 0);
      expect(editor.lastExitCode, 0);
      expect(output.where((chunk) => chunk.kind == OutputKind.stderr), isEmpty);
    },
  );

  test('direct SQL preserves SQL syntax and engine failure status', () async {
    engine.result = const SqlProgramExecutionResult(
      available: true,
      stdout: ['first result'],
      stderr: ['syntax error'],
      exitCode: 1,
    );
    final backend = terminal(cwd: p.join(project.path, 'src'));
    await backend.execute('sql --execute "SELECT 1; SELECT * FROM missing;"');

    expect(engine.requests.single.projectPath, project.path);
    expect(engine.requests.single.source, 'SELECT 1; SELECT * FROM missing;');
    expect(output.map((chunk) => chunk.text).join(), contains('first result'));
    expect(output.map((chunk) => chunk.text).join(), contains('syntax error'));
    expect(backend.lastExitCode, 1);
  });

  test('unavailable engine cannot report a successful terminal exit', () async {
    engine.result = const SqlProgramExecutionResult(
      available: false,
      stdout: [],
      stderr: ['engine unavailable'],
      exitCode: 0,
    );
    final backend = terminal();
    await backend.execute('sql -e "SELECT 1;"');
    expect(backend.lastExitCode, kProgramNotRunExitCode);
  });

  test('invalid input never executes SQL or a partial shell command', () async {
    final backend = terminal();
    for (final command in [
      'sql -e "SELECT 1;"; touch injected',
      'sql --host remote.example',
      'sql -e " "',
      'sql main.py',
      'sql "../../outside.sql"',
      'sql missing.sql',
    ]) {
      await backend.execute(command);
      expect(backend.lastExitCode, isNonZero, reason: command);
    }
    expect(engine.requests, isEmpty);
    expect(File(p.join(project.path, 'injected')).existsSync(), isFalse);
  });

  test('non-SQL tools remain owned by the shared shell', () async {
    final backend = terminal();
    expect(await SqlTerminalCommands.execute(backend, 'other-tool'), isFalse);
    expect(engine.requests, isEmpty);
  });

  final library =
      Platform.environment['QFLI_SQLITE_LIBRARY'] ??
      p.join(
        'native',
        'build',
        Platform.operatingSystem,
        Platform.isWindows ? 'qfli_sqlite.dll' : 'libqfli_sqlite.so',
      );
  test(
    'real terminal script and editor use one persisted SQLite database',
    () async {
      final backend = SandboxShellBackend(
        sandboxRoot: storage.path,
        startDirectory: storage.path,
        delegate: (backend, command) => SqlTerminalCommands.execute(
          backend,
          command,
          engine: const NativeSqliteEngine(),
        ),
      );
      final subscription = backend.output.listen(output.add);
      addTearDown(() async {
        await subscription.cancel();
        await backend.shutdown();
      });
      final entry = File(p.join(project.path, 'src', 'main.sql'));
      entry.parent.createSync();
      entry.writeAsStringSync(
        "CREATE TABLE people (name TEXT); INSERT INTO people VALUES ('Ada'); SELECT name FROM people;",
      );

      await backend.execute('sql project/src/main.sql');
      expect(
        backend.lastExitCode,
        0,
        reason: output.map((chunk) => chunk.text).join(),
      );
      expect(output.map((chunk) => chunk.text).join(), contains('Ada'));
      entry.writeAsStringSync('SELECT name FROM people;');
      final editorRun = await const SqlProgramRunner(
        engine: NativeSqliteEngine(),
      ).run(projectPath: project.path, entryFile: entry.path);
      expect(await editorRun!.exitCode, 0);
      expect(await editorRun.stdout.toList(), ['Ada']);
      expect(
        File(p.join(project.path, 'src', '.qfli', 'data.sqlite')).existsSync(),
        isFalse,
      );
    },
    skip: !File(library).existsSync()
        ? 'Native SQLite library unavailable'
        : false,
  );

  test('invalid UTF-8 is reported by both editor and terminal', () async {
    final entry = File(p.join(project.path, 'invalid.sql'))
      ..writeAsBytesSync([0xff]);
    final backend = terminal();
    await backend.execute('sql invalid.sql');
    expect(backend.lastExitCode, isNonZero);
    expect(
      output.map((chunk) => chunk.text).join().toLowerCase(),
      contains('utf-8'),
    );
    final run = await SqlProgramRunner(
      engine: engine,
    ).run(projectPath: project.path, entryFile: entry.path);
    expect(await run!.exitCode, kProgramNotRunExitCode);
    expect((await run.stderr.toList()).single.toLowerCase(), contains('utf-8'));
    expect(engine.requests, isEmpty);
  });
}

class _Engine implements SqlProgramEngine {
  final requests = <SqlProgramRequest>[];
  SqlProgramExecutionResult result = const SqlProgramExecutionResult(
    available: true,
    stdout: ['label', '"中文"'],
    stderr: [],
    exitCode: 0,
  );

  @override
  Future<SqlProgramExecutionResult> execute(SqlProgramRequest request) async {
    requests.add(request);
    return result;
  }
}
