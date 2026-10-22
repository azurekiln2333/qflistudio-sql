import 'package:flutter/foundation.dart';

import 'mysql_workspace_repository.dart';
import 'sql_database.dart';
import 'sql_engine_preference.dart';
import 'sql_workspace_repository.dart';

/// The selected local engine and its app-owned database collection.
///
/// No platform fallback is performed: OHOS SQLite uses NativeSqliteDatabase's
/// channel, while selecting MySQL always opens the local MySQL repository.
class SqlExecutionContext {
  const SqlExecutionContext._({
    required this.engine,
    required SqlWorkspaceRepository repository,
    required int revision,
    bool Function()? currentCheck,
  }) : _repository = repository,
       _revision = revision,
       _currentCheck = currentCheck;

  /// An explicitly controlled engine boundary for app-native widget/unit tests.
  /// Production callers use [openLocal], which follows the persisted choice.
  @visibleForTesting
  SqlExecutionContext.forTesting({
    required this.engine,
    required SqlWorkspaceRepository repository,
    bool Function()? isCurrent,
  }) : assert(engine != SqlEngineKind.cloud),
       _repository = repository,
       _revision = -1,
       _currentCheck = isCurrent ?? _alwaysCurrent;

  static bool _alwaysCurrent() => true;

  final SqlEngineKind engine;
  final SqlWorkspaceRepository _repository;
  final int _revision;
  final bool Function()? _currentCheck;

  String get engineLabel => switch (engine) {
    SqlEngineKind.sqlite => 'SQLite',
    SqlEngineKind.localMysql => '本机 MySQL',
    SqlEngineKind.cloud => throw StateError('本地执行上下文不能使用云数据库。'),
  };

  bool get isCurrent =>
      _currentCheck?.call() ??
      (_revision == SqlEnginePreference.revision &&
          engine ==
              SqlEnginePreference.resolveLocalEngine(
                SqlEnginePreference.current,
              ));

  /// Check again immediately before dispatching an operation. An operation
  /// already submitted to a native engine cannot be cancelled by this guard.
  void requireCurrent() {
    if (!isCurrent) {
      throw StateError('数据库引擎已切换，请重新连接后运行。');
    }
  }

  SqlWorkspaceRepository get repository {
    requireCurrent();
    return _repository;
  }

  Future<SqlQueryResult> runQuery(String databaseName, String source) async {
    requireCurrent();
    return _repository.runQuery(databaseName, source);
  }

  Future<SqlScriptResult> runScript(String databaseName, String source) async {
    requireCurrent();
    return _repository.runScript(databaseName, source);
  }

  static Future<SqlExecutionContext> openLocal({
    Future<SqlWorkspaceRepository> Function()? openSqlite,
    Future<SqlWorkspaceRepository> Function()? openMysql,
  }) async {
    await SqlEnginePreference.load();
    final revision = SqlEnginePreference.revision;
    final engine = SqlEnginePreference.resolveLocalEngine(
      SqlEnginePreference.current,
    );
    final repository = await switch (engine) {
      SqlEngineKind.sqlite =>
        (openSqlite ?? SqlWorkspaceRepository.openDefault)(),
      SqlEngineKind.localMysql =>
        (openMysql ?? MySqlWorkspaceRepository.openLocal)(),
      SqlEngineKind.cloud => throw StateError('本地执行上下文不能使用云数据库。'),
    };
    final context = SqlExecutionContext._(
      engine: engine,
      repository: repository,
      revision: revision,
    );
    // A retained tab can be reconnecting while another surface changes the
    // preference. Never publish a repository opened for that previous choice.
    context.requireCurrent();
    return context;
  }
}
