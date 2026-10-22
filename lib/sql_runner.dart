import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/terminal/shell/command_parser.dart';
import 'package:qfli_studio_core/terminal/shell/sandbox_shell_backend.dart';

import 'cloud_mysql_database.dart';
import 'sql_engine_preference.dart';
import 'sql_native_channel.dart';
import 'mysql_database.dart';
import 'sql_database.dart';

class SqlProgramRequest {
  const SqlProgramRequest({required this.projectPath, required this.source});

  final String projectPath;
  final String source;

  String get databasePath => p.join(projectPath, '.qfli', 'data.sqlite');
}

abstract interface class SqlProgramEngine {
  Future<SqlProgramExecutionResult> execute(SqlProgramRequest request);
}

class SqlProgramExecutionResult {
  const SqlProgramExecutionResult({
    required this.available,
    required this.stdout,
    required this.stderr,
    required this.exitCode,
  });

  final bool available;
  final Iterable<String> stdout;
  final Iterable<String> stderr;
  final int exitCode;
}

typedef SqliteRequest = SqlProgramRequest;
typedef SqliteEngine = SqlProgramEngine;
typedef SqliteExecutionResult = SqlProgramExecutionResult;

class NativeMySqlEngine implements SqlProgramEngine {
  const NativeMySqlEngine({this.database = const NativeMySqlDatabase()});

  final NativeMySqlDatabase database;
  static Future<void> _pending = Future<void>.value();

  @override
  Future<SqlProgramExecutionResult> execute(SqlProgramRequest request) {
    final operation = _pending.then((_) => _execute(request));
    _pending = operation.then((_) {}, onError: (Object error) {});
    return operation;
  }

  Future<SqlProgramExecutionResult> _execute(SqlProgramRequest request) async {
    try {
      final marker = File(p.join(request.projectPath, '.qfli', 'mysql.json'));
      final String schema;
      final exists = await marker.exists();
      if (exists) {
        final data = jsonDecode(await marker.readAsString());
        if (data is! Map || data['schema'] is! String) {
          throw const FormatException('项目 MySQL 配置无效。');
        }
        schema = data['schema'] as String;
        if (!RegExp(r'^qfli_project_[a-z0-9_]{1,48}$').hasMatch(schema)) {
          throw const FormatException('项目 MySQL 数据库名称无效。');
        }
      } else {
        final random = Random.secure();
        final suffix = List.generate(
          16,
          (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join();
        schema = 'qfli_project_$suffix';
      }
      final creation = await database.query(
        databasePath: '',
        source:
            'CREATE DATABASE IF NOT EXISTS `$schema` '
            'CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci',
      );
      if (!creation.success) return _result(creation);
      if (!exists) {
        await marker.parent.create(recursive: true);
        final temporary = File('${marker.path}.tmp');
        await temporary.writeAsString(
          jsonEncode({'schema': schema}),
          flush: true,
        );
        await temporary.rename(marker.path);
      }
      final result = await database.executeScript(
        databasePath: schema,
        source: request.source,
      );
      return scriptProgramResult(result);
    } on FileSystemException catch (error) {
      return _failure('无法保存项目数据库配置：${error.message}');
    } on FormatException catch (error) {
      return _failure(error.message);
    }
  }

  SqlProgramExecutionResult _result(SqlQueryResult result) =>
      SqlProgramExecutionResult(
        available: result.available,
        stdout: const [],
        stderr: [result.error ?? 'Oracle MySQL 执行失败'],
        exitCode: result.available ? result.exitCode : kProgramNotRunExitCode,
      );

  SqlProgramExecutionResult _failure(String message) =>
      SqlProgramExecutionResult(
        available: false,
        stdout: const [],
        stderr: [message],
        exitCode: kProgramNotRunExitCode,
      );
}

/// Renders a MySQL script result the same way for the local and cloud engines.
SqlProgramExecutionResult scriptProgramResult(SqlScriptResult result) {
  Iterable<String> output(SqlQueryResult result) sync* {
    if (result.columns.isEmpty) {
      yield '影响 ${result.affectedRows} 行';
    } else {
      yield result.columns.join(' | ');
      for (final row in result.rows) {
        yield row
            .map((value) => value == null ? 'NULL' : jsonEncode(value))
            .join(' | ');
      }
    }
  }

  // The cloud server adds an empty entry for the failing statement.
  final shown = [
    for (final item in result.results)
      if (item.columns.isNotEmpty || item.error == null) item,
  ];
  return SqlProgramExecutionResult(
    available: result.available,
    stdout: [
      for (var index = 0; index < shown.length; index++) ...[
        if (shown.length > 1) '结果 ${index + 1}',
        ...output(shown[index]),
      ],
    ],
    stderr: [
      if (result.error != null) result.error!,
      if (result.truncated) '查询结果超过显示上限，输出已截断。',
    ],
    exitCode: result.available ? result.exitCode : kProgramNotRunExitCode,
  );
}

/// Runs project SQL in the user's cloud MySQL default schema.
class CloudMySqlEngine implements SqlProgramEngine {
  const CloudMySqlEngine({required this.database});

  final CloudMySqlDatabase database;

  @override
  Future<SqlProgramExecutionResult> execute(SqlProgramRequest request) async {
    final result = await database.executeScript(
      databasePath: '',
      source: request.source,
    );
    return scriptProgramResult(result);
  }
}

class UnavailableSqliteEngine implements SqliteEngine {
  const UnavailableSqliteEngine();

  static const message = 'SQLite 运行时不可用：当前 App 未捆绑进程内 SQLite 引擎。';

  @override
  Future<SqliteExecutionResult> execute(SqliteRequest request) async {
    return const SqliteExecutionResult(
      available: false,
      stdout: <String>[],
      stderr: <String>[message],
      exitCode: kProgramNotRunExitCode,
    );
  }
}

/// Executes the bundled SQLite C engine through FFI or the OHOS channel.
class NativeSqliteEngine implements SqliteEngine {
  const NativeSqliteEngine({this.channel});

  final MethodChannel? channel;

  @override
  Future<SqliteExecutionResult> execute(SqliteRequest request) async {
    try {
      await Directory(p.dirname(request.databasePath)).create(recursive: true);
      final raw = await invokeSqliteNative('execute', {
        'source': request.source,
        'databasePath': request.databasePath,
      }, channel: channel);
      if (raw is! Map ||
          raw['available'] is! bool ||
          raw['exitCode'] is! num ||
          raw['output'] is! String) {
        return _unavailable('SQLite 返回了无效响应。');
      }
      final available = raw['available'] as bool;
      final error = raw['error'];
      if (error != null && error is! String) {
        return _unavailable('SQLite 返回了无效错误信息。');
      }
      final stdout = const LineSplitter().convert(raw['output'] as String);
      final stderr = <String>[
        if (error is String && error.isNotEmpty) error,
        if (raw['truncated'] == true) '查询结果超过显示上限，输出已截断。',
      ];
      return SqliteExecutionResult(
        available: available,
        stdout: stdout,
        stderr: stderr,
        exitCode: available
            ? (raw['exitCode'] as num).toInt()
            : kProgramNotRunExitCode,
      );
    } on MissingPluginException {
      return _unavailable('当前设备无法连接 SQLite 引擎。');
    } on PlatformException catch (error) {
      return _unavailable(error.message ?? error.code);
    } on FileSystemException catch (error) {
      return _unavailable('无法创建数据库目录：${error.message}');
    }
  }

  SqliteExecutionResult _unavailable(String message) => SqliteExecutionResult(
    available: false,
    stdout: const [],
    stderr: [message],
    exitCode: kProgramNotRunExitCode,
  );
}

/// Follows the workbench engine choice: device SQLite unless cloud is chosen.
class PreferredSqlEngine implements SqlProgramEngine {
  const PreferredSqlEngine();

  @override
  Future<SqlProgramExecutionResult> execute(SqlProgramRequest request) async {
    final selected = await SqlEnginePreference.load();
    if (selected == SqlEngineKind.localMysql) {
      return const NativeMySqlEngine().execute(request);
    }
    if (selected == SqlEngineKind.cloud) {
      final token = SqlEnginePreference.token();
      if (token == null) {
        return const SqlProgramExecutionResult(
          available: false,
          stdout: [],
          stderr: ['已选择云 MySQL，请先在 SQL 工作台登录。'],
          exitCode: kProgramNotRunExitCode,
        );
      }
      return CloudMySqlEngine(
        database: CloudMySqlDatabase(token: () => token),
      ).execute(request);
    }
    return const NativeLocalSqlEngine().execute(request);
  }
}

/// Executes the SQLite selection through its platform bridge.
///
/// OHOS supplies the same engine through the native channel. FFI availability
/// selects a transport inside invokeSqliteNative, never a different SQL engine.
class NativeLocalSqlEngine implements SqlProgramEngine {
  const NativeLocalSqlEngine({this.sqlite = const NativeSqliteEngine()});

  final SqlProgramEngine sqlite;

  @override
  Future<SqlProgramExecutionResult> execute(SqlProgramRequest request) =>
      sqlite.execute(request);
}

/// SQL 版 App 的运行后端。
class SqlProgramRunner implements ProgramRunner {
  const SqlProgramRunner({this.engine = const PreferredSqlEngine()});

  final SqlProgramEngine engine;

  /// 本后端接管的源码后缀。
  static const Set<String> _sourceExtensions = {'.sql'};

  @override
  Future<ProgramRunResult?> run({
    required String projectPath,
    required String entryFile,
  }) async {
    if (!_sourceExtensions.contains(p.extension(entryFile).toLowerCase())) {
      return null;
    }

    final String source;
    try {
      source = await File(entryFile).readAsString();
    } on FileSystemException catch (error) {
      return _failure(p.basename(entryFile), '无法读取 SQL 文件：${error.message}');
    }

    final request = SqlProgramRequest(projectPath: projectPath, source: source);
    final result = await engine.execute(request);
    final available = result.available;
    return ProgramRunResult(
      title: '运行 ${p.basename(entryFile)}',
      stdout: Stream<String>.fromIterable(result.stdout),
      stderr: Stream<String>.fromIterable(result.stderr),
      exitCode: Future<int>.value(
        available ? result.exitCode : kProgramNotRunExitCode,
      ),
    );
  }

  ProgramRunResult _failure(String fileName, String message) {
    return ProgramRunResult(
      title: '运行 $fileName',
      stdout: const Stream<String>.empty(),
      stderr: Stream<String>.value(message),
      exitCode: Future<int>.value(kProgramNotRunExitCode),
    );
  }
}

/// Local SQL commands shared by the standalone and embedded editor terminals.
abstract final class SqlTerminalCommands {
  static const help = '''SQL 本地终端
  sql <文件.sql>           运行 SQL 文件
  sql -e "SQL"             执行 SQL（也支持 --execute）
  sql --help               显示帮助
使用工作台选择的本地引擎和项目数据库；在项目目录内执行可与编辑器共享数据。
SQL 参数需要引号；不提供交互式 mysql/sqlite3 客户端或远程连接。''';

  static Future<bool> execute(
    SandboxShellBackend backend,
    String command, {
    SqlProgramEngine engine = const PreferredSqlEngine(),
  }) async {
    final parsed = CommandParser.tokenize(
      command,
      escapePolicy: backend.escapePolicy,
    );
    if (parsed.tokens.firstOrNull?.text != 'sql') return false;

    Future<bool> report(String message, {int code = 2}) async {
      await backend.runStreams(
        title: 'SQL',
        stdout: code == 0 ? Stream.value(message) : const Stream.empty(),
        stderr: code == 0 ? const Stream.empty() : Stream.value(message),
        exitCode: Future.value(code),
      );
      return true;
    }

    if (!parsed.ok) return report('sql: ${parsed.error}');
    if (CommandParser.classify(command, escapePolicy: backend.escapePolicy) !=
        CommandSyntax.simple) {
      return report('sql: 请用引号包住 SQL；不支持管道、重定向或命令串联。');
    }
    final args = parsed.tokens.skip(1).map((token) => token.text).toList();
    if (args.isEmpty ||
        (args.length == 1 &&
            (args.single == '--help' || args.single == '-h'))) {
      return report(help, code: 0);
    }

    final String source;
    var directory = backend.cwd;
    try {
      if (args.length == 2 &&
          (args.first == '-e' || args.first == '--execute')) {
        source = args.last;
      } else if (args.length == 1 && !args.single.startsWith('-')) {
        final path = backend.resolveSandboxPath(args.single);
        if (p.extension(path).toLowerCase() != '.sql') {
          return report('sql: 请选择 .sql 文件。');
        }
        final file = File(path);
        final resolved = await file.resolveSymbolicLinks();
        final root = await Directory(
          backend.sandboxRoot,
        ).resolveSymbolicLinks();
        if (!p.equals(root, resolved) && !p.isWithin(root, resolved)) {
          return report('sql: 文件不能越出沙盒目录。');
        }
        source = await file.readAsString();
        directory = p.dirname(path);
      } else {
        return report('sql: 参数无效。使用 sql --help 查看用法。');
      }
      if (source.trim().isEmpty) return report('sql: SQL 内容不能为空。');

      // The app terminal starts at storage, while the editor starts at a
      // project. Locate the same project for a script under e.g. src/main.sql.
      var projectPath = backend.cwd;
      var candidate = directory;
      while (p.equals(candidate, backend.sandboxRoot) ||
          p.isWithin(backend.sandboxRoot, candidate)) {
        if (await File(p.join(candidate, '.qfli', 'project.json')).exists()) {
          projectPath = candidate;
          break;
        }
        final parent = p.dirname(candidate);
        if (p.equals(parent, candidate)) break;
        candidate = parent;
      }
      final result = await engine.execute(
        SqlProgramRequest(projectPath: projectPath, source: source),
      );
      await backend.runStreams(
        title: 'SQL',
        stdout: Stream.fromIterable(result.stdout),
        stderr: Stream.fromIterable(result.stderr),
        exitCode: Future.value(
          result.available ? result.exitCode : kProgramNotRunExitCode,
        ),
      );
      return true;
    } on SandboxEscapeException {
      return report('sql: 文件不能越出沙盒目录。');
    } on FileSystemException catch (error) {
      return report('sql: 无法读取 SQL 文件：${error.message}', code: 127);
    } on FormatException catch (error) {
      return report('sql: SQL 文件必须是有效的 UTF-8 文本：${error.message}');
    }
  }
}
