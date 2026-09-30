import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'sql_native_channel.dart';

class SqlResultColumn {
  const SqlResultColumn({
    required this.name,
    required this.nativeType,
    required this.binary,
  });

  final String name;
  final int nativeType;
  final bool binary;
}

class SqlQueryResult {
  const SqlQueryResult({
    required this.available,
    required this.exitCode,
    required this.columns,
    required this.rows,
    required this.affectedRows,
    required this.truncated,
    this.error,
    this.sqlState,
    this.columnInfo = const [],
  });

  factory SqlQueryResult.fromNative(Object? raw) {
    if (raw is! Map ||
        raw['available'] is! bool ||
        raw['exitCode'] is! num ||
        raw['columns'] is! List ||
        raw['rows'] is! List ||
        raw['affectedRows'] is! num ||
        raw['truncated'] is! bool ||
        raw['error'] is! String) {
      throw const FormatException('Invalid native query result');
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
      throw const FormatException('Invalid native table data');
    }
    final metadata = raw['columnInfo'];
    final columnInfo = <SqlResultColumn>[];
    if (metadata != null) {
      if (metadata is! List || metadata.length != columns.length) {
        throw const FormatException('Invalid native column metadata');
      }
      for (var index = 0; index < metadata.length; index++) {
        final item = metadata[index];
        if (item is! Map ||
            item['name'] != columns[index] ||
            item['nativeType'] is! num ||
            item['binary'] is! bool) {
          throw const FormatException('Invalid native column metadata');
        }
        columnInfo.add(
          SqlResultColumn(
            name: item['name'] as String,
            nativeType: (item['nativeType'] as num).toInt(),
            binary: item['binary'] as bool,
          ),
        );
      }
    }
    final state = raw['sqlState'];
    if (state != null && state is! String) {
      throw const FormatException('Invalid native SQLSTATE');
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
      sqlState: state is String && state.isNotEmpty ? state : null,
      columnInfo: columnInfo,
    );
  }

  factory SqlQueryResult.unavailable(String message) => SqlQueryResult(
    available: false,
    exitCode: 127,
    columns: const [],
    rows: const [],
    affectedRows: 0,
    truncated: false,
    error: message,
  );

  final bool available;
  final int exitCode;
  final List<String> columns;
  final List<List<String?>> rows;
  final int affectedRows;
  final bool truncated;
  final String? error;
  final String? sqlState;
  final List<SqlResultColumn> columnInfo;

  bool get success => available && exitCode == 0 && error == null;
}

abstract interface class SqlDatabase {
  Future<SqlQueryResult> query({
    required String databasePath,
    required String source,
    List<String?> parameters,
  });
}

class SqlScriptResult {
  const SqlScriptResult({required this.summary, required this.results});

  factory SqlScriptResult.fromNative(Object? raw) {
    final summary = SqlQueryResult.fromNative(raw);
    if (raw is! Map || raw['results'] is! List) {
      throw const FormatException('Invalid native script results');
    }
    return SqlScriptResult(
      summary: summary,
      results: [
        for (final result in raw['results'] as List)
          SqlQueryResult.fromNative(result),
      ],
    );
  }

  final SqlQueryResult summary;
  final List<SqlQueryResult> results;

  bool get success => summary.success;
  bool get available => summary.available;
  int get exitCode => summary.exitCode;
  String? get error => summary.error;
  bool get truncated => summary.truncated;
}

abstract interface class SqlScriptDatabase {
  Future<SqlScriptResult> executeScript({
    required String databasePath,
    required String source,
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
      return SqlQueryResult.fromNative(raw);
    } on FormatException {
      return _failure('SQLite 返回了无效的查询结果。');
    } on MissingPluginException {
      return _failure('当前设备无法连接 SQLite 引擎。');
    } on PlatformException catch (error) {
      return _failure(error.message ?? error.code);
    } on FileSystemException catch (error) {
      return _failure('无法创建数据库目录：${error.message}');
    }
  }

  SqlQueryResult _failure(String message) =>
      SqlQueryResult.unavailable(message);
}
