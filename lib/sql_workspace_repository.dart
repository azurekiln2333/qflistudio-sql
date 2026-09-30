import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/services/app_paths.dart';
import 'package:qfli_studio_core/services/file_service.dart';

import 'sql_database.dart';

class SqlColumn {
  const SqlColumn({
    required this.name,
    required this.type,
    required this.notNull,
    required this.primaryKey,
  });

  final String name;
  final String type;
  final bool notNull;
  final bool primaryKey;
}

class SqlColumnDraft {
  const SqlColumnDraft({
    required this.name,
    required this.type,
    this.notNull = false,
    this.primaryKey = false,
  });

  final String name;
  final String type;
  final bool notNull;
  final bool primaryKey;
}

class SqlTablePage {
  const SqlTablePage({
    required this.columns,
    required this.rows,
    required this.rowIds,
    required this.totalRows,
    required this.editable,
  });

  final List<SqlColumn> columns;
  final List<List<String?>> rows;
  final List<String> rowIds;
  final int totalRows;
  final bool editable;
}

/// Local database files and schema operations for the SQLite workspace.
class SqlWorkspaceRepository {
  const SqlWorkspaceRepository({
    required this.root,
    this.database = const NativeSqliteDatabase(),
  });

  final Directory root;
  final SqlDatabase database;

  static const int pageSize = 100;
  static const types = ['INTEGER', 'TEXT', 'REAL', 'NUMERIC', 'BLOB'];

  List<String> get columnTypes => types;

  static Future<SqlWorkspaceRepository> openDefault() async {
    final storage = await AppPaths.storageDirectory();
    if (storage == null) {
      throw const FileSystemException('无法访问应用数据目录');
    }
    final root = Directory(p.join(storage, 'databases'));
    await root.create(recursive: true);
    return SqlWorkspaceRepository(root: root);
  }

  String databasePath(String name) {
    _validateName(name);
    return p.join(root.path, '$name.sqlite');
  }

  Future<List<String>> listDatabases() async {
    if (!await root.exists()) return [];
    final names = <String>[];
    await for (final item in root.list(followLinks: false)) {
      if (item is File && p.extension(item.path).toLowerCase() == '.sqlite') {
        names.add(p.basenameWithoutExtension(item.path));
      }
    }
    names.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return names;
  }

  Future<void> createDatabase(String name) async {
    final file = File(databasePath(name));
    await root.create(recursive: true);
    if (await file.exists()) throw StateError('数据库已存在：$name');
    _require(
      await database.query(
        databasePath: file.path,
        source: 'PRAGMA user_version',
      ),
    );
  }

  Future<void> deleteDatabase(String name) async {
    final file = File(databasePath(name));
    if (!await file.exists()) throw StateError('数据库不存在：$name');
    await file.delete();
  }

  Future<List<String>> listTables(String databaseName) async {
    final result = _require(
      await database.query(
        databasePath: databasePath(databaseName),
        source:
            "SELECT name FROM sqlite_master WHERE type = 'table' "
            "AND name NOT LIKE 'sqlite_%' ORDER BY name",
      ),
    );
    return [for (final row in result.rows) row.first!];
  }

  Future<List<SqlColumn>> tableColumns(
    String databaseName,
    String table,
  ) async {
    final result = _require(
      await database.query(
        databasePath: databasePath(databaseName),
        source: 'PRAGMA table_info(${quoteIdentifier(table)})',
      ),
    );
    if (result.rows.isEmpty) throw StateError('数据表不存在：$table');
    return [
      for (final row in result.rows)
        SqlColumn(
          name: row[1]!,
          type: row[2] ?? '',
          notNull: row[3] == '1',
          primaryKey: row[5] != '0',
        ),
    ];
  }

  Future<SqlTablePage> loadTable(
    String databaseName,
    String table, {
    int page = 0,
    String? filterColumn,
    String filter = '',
    String? sortColumn,
    bool descending = false,
  }) async {
    if (page < 0) throw ArgumentError.value(page, 'page');
    final columns = await tableColumns(databaseName, table);
    final names = columns.map((column) => column.name).toSet();
    if (filterColumn != null && !names.contains(filterColumn)) {
      throw ArgumentError.value(filterColumn, 'filterColumn');
    }
    if (sortColumn != null && !names.contains(sortColumn)) {
      throw ArgumentError.value(sortColumn, 'sortColumn');
    }
    final where = filterColumn == null || filter.isEmpty
        ? ''
        : ' WHERE CAST(${quoteIdentifier(filterColumn)} AS TEXT) LIKE ?';
    final filters = filterColumn == null || filter.isEmpty
        ? <String?>[]
        : <String?>['%$filter%'];
    final path = databasePath(databaseName);
    final count = _require(
      await database.query(
        databasePath: path,
        source: 'SELECT COUNT(*) FROM ${quoteIdentifier(table)}$where',
        parameters: filters,
      ),
    );
    final total = int.parse(count.rows.single.single!);
    final order = sortColumn == null
        ? ''
        : ' ORDER BY ${quoteIdentifier(sortColumn)} ${descending ? 'DESC' : 'ASC'}';
    final suffix = '$where$order LIMIT ? OFFSET ?';
    final parameters = [...filters, '$pageSize', '${page * pageSize}'];
    final identity = await _tableRowIdentity(databaseName, table, columns);
    final editable = identity != null;
    final result = await database.query(
      databasePath: path,
      source:
          'SELECT ${identity == null ? '' : '${quoteIdentifier(identity)}, '}'
          '* FROM ${quoteIdentifier(table)}$suffix',
      parameters: parameters,
    );
    _require(result);
    if (result.truncated) {
      throw StateError('该页数据超过显示上限，请缩小查询范围');
    }
    return SqlTablePage(
      columns: columns,
      rows: [for (final row in result.rows) editable ? row.sublist(1) : row],
      rowIds: editable ? [for (final row in result.rows) row.first!] : const [],
      totalRows: total,
      editable: editable,
    );
  }

  Future<void> createTable(
    String databaseName,
    String table,
    List<SqlColumnDraft> columns,
  ) async {
    _validateName(table);
    if (columns.isEmpty) throw ArgumentError('至少需要一列');
    final seen = <String>{};
    var primaryKeys = 0;
    final definitions = <String>[];
    for (final column in columns) {
      _validateName(column.name);
      if (!seen.add(column.name.toLowerCase())) {
        throw ArgumentError('列名重复：${column.name}');
      }
      if (!types.contains(column.type)) {
        throw ArgumentError('不支持的列类型：${column.type}');
      }
      if (column.primaryKey) {
        primaryKeys++;
        if (column.type != 'INTEGER') {
          throw ArgumentError('主键列必须使用 INTEGER 类型');
        }
      }
      definitions.add(
        '${quoteIdentifier(column.name)} ${column.type}'
        '${column.primaryKey ? ' PRIMARY KEY' : ''}'
        '${column.notNull && !column.primaryKey ? ' NOT NULL' : ''}',
      );
    }
    if (primaryKeys > 1) throw ArgumentError('只能设置一个主键');
    _require(
      await database.query(
        databasePath: databasePath(databaseName),
        source:
            'CREATE TABLE ${quoteIdentifier(table)} (${definitions.join(', ')})',
      ),
    );
  }

  Future<void> deleteTable(String databaseName, String table) async {
    _require(
      await database.query(
        databasePath: databasePath(databaseName),
        source: 'DROP TABLE ${quoteIdentifier(table)}',
      ),
    );
  }

  Future<void> insertRow(
    String databaseName,
    String table,
    Map<String, String?> values,
  ) async {
    final columns = await tableColumns(databaseName, table);
    _validateColumns(values.keys, columns);
    final names = values.keys.toList();
    final source = names.isEmpty
        ? 'INSERT INTO ${quoteIdentifier(table)} DEFAULT VALUES'
        : 'INSERT INTO ${quoteIdentifier(table)} '
              '(${names.map(quoteIdentifier).join(', ')}) '
              'VALUES (${List.filled(names.length, '?').join(', ')})';
    _require(
      await database.query(
        databasePath: databasePath(databaseName),
        source: source,
        parameters: [for (final name in names) values[name]],
      ),
    );
  }

  Future<void> updateCell(
    String databaseName,
    String table,
    String rowId,
    String column,
    String? value,
  ) async {
    final columns = await tableColumns(databaseName, table);
    _validateColumns([column], columns);
    final identity = await _tableRowIdentity(databaseName, table, columns);
    if (identity == null) throw StateError('该表没有可用的行标识');
    final result = _require(
      await database.query(
        databasePath: databasePath(databaseName),
        source:
            'UPDATE ${quoteIdentifier(table)} '
            'SET ${quoteIdentifier(column)} = ? '
            'WHERE ${quoteIdentifier(identity)} = ?',
        parameters: [value, rowId],
      ),
    );
    if (result.affectedRows != 1) throw StateError('该行已发生变化，请刷新后重试');
  }

  Future<void> deleteRow(
    String databaseName,
    String table,
    String rowId,
  ) async {
    final columns = await tableColumns(databaseName, table);
    final identity = await _tableRowIdentity(databaseName, table, columns);
    if (identity == null) throw StateError('该表没有可用的行标识');
    final result = _require(
      await database.query(
        databasePath: databasePath(databaseName),
        source:
            'DELETE FROM ${quoteIdentifier(table)} '
            'WHERE ${quoteIdentifier(identity)} = ?',
        parameters: [rowId],
      ),
    );
    if (result.affectedRows != 1) throw StateError('该行已发生变化，请刷新后重试');
  }

  Future<SqlQueryResult> runQuery(String databaseName, String source) =>
      database.query(databasePath: databasePath(databaseName), source: source);

  static String quoteIdentifier(String name) {
    _validateName(name);
    return '"${name.replaceAll('"', '""')}"';
  }

  static void _validateName(String name) {
    if (!FileService.isValidEntryName(name) ||
        name != name.trim() ||
        name.contains('\u0000')) {
      throw ArgumentError.value(name, 'name', '名称无效');
    }
  }

  static void _validateColumns(
    Iterable<String> names,
    List<SqlColumn> columns,
  ) {
    final known = columns.map((column) => column.name).toSet();
    for (final name in names) {
      if (!known.contains(name)) throw ArgumentError('列不存在：$name');
    }
  }

  Future<String?> _tableRowIdentity(
    String databaseName,
    String table,
    List<SqlColumn> columns,
  ) async {
    final metadata = _require(
      await database.query(
        databasePath: databasePath(databaseName),
        source: 'PRAGMA main.table_list(${quoteIdentifier(table)})',
      ),
    );
    if (metadata.rows.isEmpty || metadata.rows.any((row) => row[4] == '1')) {
      return null;
    }
    final names = columns.map((column) => column.name.toLowerCase()).toSet();
    for (final alias in const ['rowid', '_rowid_', 'oid']) {
      if (!names.contains(alias)) return alias;
    }
    return null;
  }

  static SqlQueryResult _require(SqlQueryResult result) {
    if (!result.success) {
      throw StateError(result.error ?? 'SQL 执行失败（${result.exitCode}）');
    }
    return result;
  }
}
