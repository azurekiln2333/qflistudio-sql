import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/services/app_paths.dart';

class SqlHistoryEntry {
  const SqlHistoryEntry({
    required this.database,
    required this.source,
    required this.executedAt,
    required this.success,
  });

  final String database;
  final String source;
  final DateTime executedAt;
  final bool success;

  Map<String, Object?> toJson() => {
    'database': database,
    'source': source,
    'executedAt': executedAt.toUtc().toIso8601String(),
    'success': success,
  };

  static SqlHistoryEntry fromJson(Map<String, dynamic> json) => SqlHistoryEntry(
    database: json['database'] as String,
    source: json['source'] as String,
    executedAt: DateTime.parse(json['executedAt'] as String),
    success: json['success'] as bool,
  );
}

class SqlSavedQuery {
  const SqlSavedQuery({
    required this.database,
    required this.name,
    required this.source,
    required this.updatedAt,
  });

  final String database;
  final String name;
  final String source;
  final DateTime updatedAt;

  Map<String, Object?> toJson() => {
    'database': database,
    'name': name,
    'source': source,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  static SqlSavedQuery fromJson(Map<String, dynamic> json) => SqlSavedQuery(
    database: json['database'] as String,
    name: json['name'] as String,
    source: json['source'] as String,
    updatedAt: DateTime.parse(json['updatedAt'] as String),
  );
}

/// App-private SQL history and saved queries, independent of the SQL engine.
class SqlQueryLibrary {
  SqlQueryLibrary({required this.file});

  final File file;
  final List<SqlHistoryEntry> _history = [];
  final List<SqlSavedQuery> _saved = [];

  static const int historyLimit = 100;

  List<SqlHistoryEntry> get history => List.unmodifiable(_history);
  List<SqlSavedQuery> get saved => List.unmodifiable(_saved);

  static Future<SqlQueryLibrary> openDefault() async {
    final storage = await AppPaths.storageDirectory();
    if (storage == null) {
      throw const FileSystemException('无法访问应用数据目录');
    }
    return SqlQueryLibrary.open(File(p.join(storage, 'sql_queries.json')));
  }

  static Future<SqlQueryLibrary> open(File file) async {
    final library = SqlQueryLibrary(file: file);
    if (!await file.exists()) return library;
    final data = jsonDecode(await file.readAsString());
    if (data is! Map<String, dynamic> || data['version'] != 1) {
      throw const FormatException('SQL 查询记录格式无效');
    }
    final history = data['history'];
    final saved = data['saved'];
    if (history is! List || saved is! List) {
      throw const FormatException('SQL 查询记录格式无效');
    }
    library._history.addAll([
      for (final item in history)
        SqlHistoryEntry.fromJson(Map<String, dynamic>.from(item as Map)),
    ]);
    library._saved.addAll([
      for (final item in saved)
        SqlSavedQuery.fromJson(Map<String, dynamic>.from(item as Map)),
    ]);
    if (library._history.length > historyLimit) {
      library._history.removeRange(historyLimit, library._history.length);
    }
    return library;
  }

  Future<void> recordExecution({
    required String database,
    required String source,
    required bool success,
  }) async {
    final history = [
      SqlHistoryEntry(
        database: database,
        source: source,
        executedAt: DateTime.now(),
        success: success,
      ),
      ..._history,
    ].take(historyLimit).toList();
    await _persist(history: history, saved: _saved);
  }

  Future<void> clearHistory() async {
    await _persist(history: [], saved: _saved);
  }

  Future<void> saveQuery({
    required String database,
    required String name,
    required String source,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty || source.trim().isEmpty) {
      throw ArgumentError('查询名称和 SQL 不能为空');
    }
    final saved = [
      SqlSavedQuery(
        database: database,
        name: trimmedName,
        source: source,
        updatedAt: DateTime.now(),
      ),
      ..._saved.where(
        (item) => item.database != database || item.name != trimmedName,
      ),
    ];
    await _persist(history: _history, saved: saved);
  }

  Future<void> deleteSavedQuery(String database, String name) async {
    final saved = _saved
        .where((item) => item.database != database || item.name != name)
        .toList();
    await _persist(history: _history, saved: saved);
  }

  Future<void> _persist({
    required List<SqlHistoryEntry> history,
    required List<SqlSavedQuery> saved,
  }) async {
    // Commit the file before publishing new state to the workbench.
    final nextHistory = List<SqlHistoryEntry>.of(history);
    final nextSaved = List<SqlSavedQuery>.of(saved);
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({
        'version': 1,
        'history': [for (final item in nextHistory) item.toJson()],
        'saved': [for (final item in nextSaved) item.toJson()],
      }),
      flush: true,
    );
    await temporary.rename(file.path);
    _history
      ..clear()
      ..addAll(nextHistory);
    _saved
      ..clear()
      ..addAll(nextSaved);
  }
}
