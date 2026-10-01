import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/services/studio_profile.dart';

import 'sql_native_channel.dart';
import 'mysql_database.dart';
import 'sql_database.dart';
import 'sqlite_ffi.dart';

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
      return SqlProgramExecutionResult(
        available: result.available,
        stdout: [
          for (var index = 0; index < result.results.length; index++) ...[
            if (result.results.length > 1) '结果 ${index + 1}',
            ..._output(result.results[index]),
          ],
        ],
        stderr: [
          if (result.error != null) result.error!,
          if (result.truncated) '查询结果超过显示上限，输出已截断。',
        ],
        exitCode: result.available ? result.exitCode : kProgramNotRunExitCode,
      );
    } on FileSystemException catch (error) {
      return _failure('无法保存项目数据库配置：${error.message}');
    } on FormatException catch (error) {
      return _failure(error.message);
    }
  }

  Iterable<String> _output(SqlQueryResult result) sync* {
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

/// Matches the default workbench's native engine on each platform.
class NativeLocalSqlEngine implements SqlProgramEngine {
  const NativeLocalSqlEngine();

  @override
  Future<SqlProgramExecutionResult> execute(SqlProgramRequest request) =>
      SqliteFfi.supported
          ? const NativeSqliteEngine().execute(request)
          : const NativeMySqlEngine().execute(request);
}

/// SQL 版 App 的运行后端。
class SqlProgramRunner implements ProgramRunner {
  const SqlProgramRunner({this.engine = const NativeLocalSqlEngine()});

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
