import 'package:qfli_studio_core/services/api_client.dart';

import 'sql_database.dart';
import 'sql_engine_preference.dart';

/// Cloud MySQL practice space over the business API. The server owns the
/// separate practice mysqld and per-user credentials; this client only sends
/// SQL with the user's QFLI token. `databasePath` is a schema name, and an
/// empty value selects no default schema, like the native Oracle client.
class CloudMySqlDatabase implements SqlDatabase, SqlScriptDatabase {
  CloudMySqlDatabase({required this.token, ApiClient? client})
    : _client = client ?? ApiClient.instance;

  final String Function() token;
  final ApiClient _client;

  @override
  Future<SqlQueryResult> query({
    required String databasePath,
    required String source,
    List<String?> parameters = const [],
  }) async {
    if (!SqlEnginePreference.cloudEnabled) {
      return SqlQueryResult.unavailable(
        SqlEnginePreference.cloudUnavailableMessage,
      );
    }
    try {
      final raw = await _client.sqlQuery(
        token(),
        database: databasePath,
        source: source,
        params: parameters,
      );
      return SqlQueryResult.fromNative(raw);
    } on ApiException catch (error) {
      return SqlQueryResult.unavailable(error.message);
    } on FormatException {
      return SqlQueryResult.unavailable('云 MySQL 返回了无效的查询结果。');
    }
  }

  @override
  Future<SqlScriptResult> executeScript({
    required String databasePath,
    required String source,
  }) async {
    if (!SqlEnginePreference.cloudEnabled) {
      return SqlScriptResult(
        summary: SqlQueryResult.unavailable(
          SqlEnginePreference.cloudUnavailableMessage,
        ),
        results: const [],
      );
    }
    try {
      final raw = await _client.sqlScript(
        token(),
        database: databasePath,
        source: source,
      );
      return SqlScriptResult.fromNative(raw);
    } on ApiException catch (error) {
      return SqlScriptResult(
        summary: SqlQueryResult.unavailable(error.message),
        results: const [],
      );
    } on FormatException {
      return SqlScriptResult(
        summary: SqlQueryResult.unavailable('云 MySQL 返回了无效的脚本结果。'),
        results: const [],
      );
    }
  }
}
