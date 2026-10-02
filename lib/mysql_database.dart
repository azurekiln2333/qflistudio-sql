import 'dart:io';

import 'package:flutter/services.dart';

import 'sql_database.dart';
import 'sql_native_channel.dart';
import 'local_mysql_runtime.dart';
import 'android_mysql_runtime.dart';

/// Native FFI and the OHOS channel own a real private Oracle runtime.
class NativeMySqlDatabase implements SqlDatabase, SqlScriptDatabase {
  const NativeMySqlDatabase({this.channel, this.runtime});

  final MethodChannel? channel;
  final LocalMySqlRuntime? runtime;

  Future<Object?> _invoke(String method, Map<String, Object?> arguments) async {
    if (channel == null && (runtime != null || LocalMySqlRuntime.supported)) {
      final selected =
          runtime ??
          (Platform.isAndroid
              ? await AndroidMySqlRuntime.prepare()
              : LocalMySqlRuntime.shared);
      return selected.invoke(method, arguments);
    }
    return (channel ?? mysqlNativeChannel).invokeMethod<Object?>(
      method,
      arguments,
    );
  }

  @override
  Future<SqlScriptResult> executeScript({
    required String databasePath,
    required String source,
  }) async {
    try {
      final raw = await _invoke('executeScript', {
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
      final raw = await _invoke('query', {
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
