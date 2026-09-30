import 'package:flutter/services.dart';

import 'sql_database.dart';
import 'sql_native_channel.dart';

/// The platform channel owns readiness and the private socket connection.
class NativeMySqlDatabase implements SqlDatabase, SqlScriptDatabase {
  const NativeMySqlDatabase({this.channel = mysqlNativeChannel});

  final MethodChannel channel;

  @override
  Future<SqlScriptResult> executeScript({
    required String databasePath,
    required String source,
  }) async {
    try {
      final raw = await channel.invokeMethod<Object?>('executeScript', {
        'schema': databasePath,
        'source': source,
      });
      return SqlScriptResult.fromNative(raw);
    } on MissingPluginException {
      return _scriptFailure('当前设备无法连接 Oracle MySQL 引擎。');
    } on PlatformException catch (error) {
      return _scriptFailure(error.message ?? error.code);
    } on FormatException {
      return _scriptFailure('MySQL 返回了无效的脚本结果。');
    }
  }

  SqlScriptResult _scriptFailure(String message) => SqlScriptResult(
    summary: SqlQueryResult.unavailable(message),
    results: const [],
  );

  @override
  Future<SqlQueryResult> query({
    required String databasePath,
    required String source,
    List<String?> parameters = const [],
  }) async {
    try {
      final raw = await channel.invokeMethod<Object?>('query', {
        'schema': databasePath,
        'source': source,
        'params': parameters,
      });
      return SqlQueryResult.fromNative(raw);
    } on MissingPluginException {
      return SqlQueryResult.unavailable('当前设备无法连接 Oracle MySQL 引擎。');
    } on PlatformException catch (error) {
      return SqlQueryResult.unavailable(error.message ?? error.code);
    } on FormatException {
      return SqlQueryResult.unavailable('MySQL 返回了无效的查询结果。');
    }
  }
}
