import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/services/studio_profile.dart';

/// 一次待交给 SQLite 后端执行的项目查询。
class SqliteRequest {
  const SqliteRequest({required this.projectPath, required this.source});

  final String projectPath;
  final String source;

  String get databasePath => p.join(projectPath, '.qfli', 'data.sqlite');
}

/// SQLite 执行后端的最小边界。
///
/// 实现在当前进程内打开 [SqliteRequest.databasePath]，执行 SQL 并返回结果。
abstract interface class SqliteEngine {
  Future<SqliteExecutionResult> execute(SqliteRequest request);
}

class SqliteExecutionResult {
  const SqliteExecutionResult({
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

/// Calls the bundled HarmonyOS SQLite library through its method channel.
class NativeSqliteEngine implements SqliteEngine {
  const NativeSqliteEngine({
    this.channel = const MethodChannel('qfli_sql/native'),
  });

  final MethodChannel channel;

  @override
  Future<SqliteExecutionResult> execute(SqliteRequest request) async {
    try {
      await Directory(p.dirname(request.databasePath)).create(recursive: true);
      final raw = await channel.invokeMethod<Object?>('execute', {
        'source': request.source,
        'databasePath': request.databasePath,
      });
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

/// SQL 版 App 的运行后端。
class SqlProgramRunner implements ProgramRunner {
  const SqlProgramRunner({this.engine = const NativeSqliteEngine()});

  /// The engine is injectable so the native SQLite boundary can be tested
  /// without starting an external process.
  final SqliteEngine engine;

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

    final request = SqliteRequest(projectPath: projectPath, source: source);
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
