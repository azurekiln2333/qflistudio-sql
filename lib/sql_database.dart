import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'sql_native_channel.dart';

class SqlQueryResult {
  const SqlQueryResult({
    required this.available,
    required this.exitCode,
    required this.columns,
    required this.rows,
    required this.affectedRows,
    required this.truncated,
    this.error,
  });

  final bool available;
  final int exitCode;
  final List<String> columns;
  final List<List<String?>> rows;
  final int affectedRows;
  final bool truncated;
  final String? error;

  bool get success => available && exitCode == 0 && error == null;
}

abstract interface class SqlDatabase {
  Future<SqlQueryResult> query({
    required String databasePath,
    required String source,
    List<String?> parameters,
  });
}

/// Structured, parameterized queries for the local SQLite database workspace.
class NativeSqliteDatabase implements SqlDatabase {
  const NativeSqliteDatabase({this.channel = sqlNativeChannel});

  final MethodChannel channel;

  @override
  Future<SqlQueryResult> query({
    required String databasePath,
    required String source,
    List<String?> parameters = const [],
  }) async {
    try {
      if (databasePath != ':memory:') {
        await Directory(p.dirname(databasePath)).create(recursive: true);
      }
      final raw = await channel.invokeMethod<Object?>('query', {
        'source': source,
        'databasePath': databasePath,
        'params': parameters,
      });
      if (raw is! Map ||
          raw['available'] is! bool ||
          raw['exitCode'] is! num ||
          raw['columns'] is! List ||
          raw['rows'] is! List ||
          raw['affectedRows'] is! num ||
          raw['truncated'] is! bool ||
          raw['error'] is! String) {
        return _failure('SQLite 返回了无效的查询结果。');
      }
      final columns = raw['columns'] as List;
      final rows = raw['rows'] as List;
      if (columns.any((value) => value is! String) ||
          rows.any(
            (row) =>
                row is! List ||
                row.length != columns.length ||
                row.any((value) => value != null && value is! String),
          )) {
        return _failure('SQLite 返回了无效的表格数据。');
      }
      final error = raw['error'] as String;
      return SqlQueryResult(
        available: raw['available'] as bool,
        exitCode: (raw['exitCode'] as num).toInt(),
        columns: List<String>.from(columns),
        rows: [for (final row in rows) List<String?>.from(row as List)],
        affectedRows: (raw['affectedRows'] as num).toInt(),
        truncated: raw['truncated'] as bool,
        error: error.isEmpty ? null : error,
      );
    } on MissingPluginException {
      return _failure('当前设备无法连接 SQLite 引擎。');
    } on PlatformException catch (error) {
      return _failure(error.message ?? error.code);
    } on FileSystemException catch (error) {
      return _failure('无法创建数据库目录：${error.message}');
    }
  }

  SqlQueryResult _failure(String message) => SqlQueryResult(
    available: false,
    exitCode: 127,
    columns: const [],
    rows: const [],
    affectedRows: 0,
    truncated: false,
    error: message,
  );
}
