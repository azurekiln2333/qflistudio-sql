import 'dart:convert';
import 'dart:io';

import 'sql_database.dart';
import 'sql_workspace_repository.dart';

/// Oracle MySQL operations. The injected client owns the local server lifecycle.
/// Here, SqlDatabase.databasePath is a schema name, not a SQLite file path.
class MySqlWorkspaceRepository extends SqlWorkspaceRepository {
  const MySqlWorkspaceRepository({
    required Directory runtimeDirectory,
    required super.database,
  }) : super(root: runtimeDirectory);

  @override
  List<String> get columnTypes => const [
    'INTEGER',
    'BIGINT',
    'VARCHAR(255)',
    'TEXT',
    'DECIMAL(20,6)',
    'DOUBLE',
    'BOOLEAN',
    'DATE',
    'DATETIME',
    'BLOB',
  ];

  @override
  String databasePath(String name) {
    _identifier(name);
    return name;
  }

  @override
  Future<List<String>> listDatabases() async {
    final result = await _query(
      '',
      "SELECT SCHEMA_NAME FROM information_schema.SCHEMATA "
          "WHERE SCHEMA_NAME NOT IN "
          "('mysql', 'information_schema', 'performance_schema', 'sys') "
          'ORDER BY SCHEMA_NAME',
    );
    return [for (final row in result.rows) row.single!];
  }

  @override
  Future<void> createDatabase(String name) async {
    await _query(
      '',
      'CREATE DATABASE ${_identifier(name)} '
          'CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci',
    );
  }

  @override
  Future<void> deleteDatabase(String name) async {
    _requireUserDatabase(name);
    await _query('', 'DROP DATABASE ${_identifier(name)}');
  }

  @override
  Future<List<String>> listTables(String databaseName) async {
    final result = await _query(
      databaseName,
      'SELECT TABLE_NAME FROM information_schema.TABLES '
      "WHERE TABLE_SCHEMA = ? AND TABLE_TYPE = 'BASE TABLE' "
      'ORDER BY TABLE_NAME',
      [databaseName],
    );
    return [for (final row in result.rows) row.single!];
  }

  @override
  Future<List<SqlColumn>> tableColumns(
    String databaseName,
    String table,
  ) async {
    _identifier(table);
    final result = await _query(
      databaseName,
      'SELECT COLUMN_NAME, COLUMN_TYPE, IS_NULLABLE, COLUMN_KEY '
      'FROM information_schema.COLUMNS '
      'WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ? ORDER BY ORDINAL_POSITION',
      [databaseName, table],
    );
    if (result.rows.isEmpty) throw StateError('数据表不存在：$table');
    return [
      for (final row in result.rows)
        SqlColumn(
          name: row[0]!,
          type: row[1]!,
          notNull: row[2] == 'NO',
          primaryKey: row[3] == 'PRI',
        ),
    ];
  }

  @override
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
    _validateColumns([?filterColumn, ?sortColumn], columns);
    final hasFilter = filterColumn != null && filter.isNotEmpty;
    final where = hasFilter
        ? ' WHERE CAST(${_identifier(filterColumn)} AS CHAR) LIKE ?'
        : '';
    final parameters = hasFilter ? <String?>['%$filter%'] : <String?>[];
    final count = await _query(
      databaseName,
      'SELECT COUNT(*) FROM ${_identifier(table)}$where',
      parameters,
    );
    final keys = columns.where((column) => column.primaryKey).toList();
    // Primary-key tie breakers keep pages stable when the selected sort repeats.
    final ordering = [
      if (sortColumn != null)
        '${_identifier(sortColumn)} ${descending ? 'DESC' : 'ASC'}',
      for (final key in keys)
        if (key.name != sortColumn) '${_identifier(key.name)} ASC',
    ];
    final order = ordering.isEmpty ? '' : ' ORDER BY ${ordering.join(', ')}';
    final result = await _query(
      databaseName,
      'SELECT ${columns.map(_projection).join(', ')} '
      'FROM ${_identifier(table)}$where$order '
      'LIMIT ${SqlWorkspaceRepository.pageSize} '
      'OFFSET ${page * SqlWorkspaceRepository.pageSize}',
      parameters,
    );
    final indexes = [
      for (final key in keys)
        columns.indexWhere((column) => column.name == key.name),
    ];
    return SqlTablePage(
      columns: columns,
      rows: result.rows,
      rowIds: keys.isEmpty
          ? const []
          : [
              for (final row in result.rows)
                jsonEncode([
                  for (var index = 0; index < keys.length; index++)
                    [keys[index].name, row[indexes[index]]],
                ]),
            ],
      totalRows: int.parse(count.rows.single.single!),
      editable: keys.isNotEmpty,
    );
  }

  @override
  Future<void> createTable(
    String databaseName,
    String table,
    List<SqlColumnDraft> columns,
  ) async {
    if (columns.isEmpty) throw ArgumentError('至少需要一列');
    final seen = <String>{};
    final definitions = <String>[];
    final keys = <String>[];
    for (final column in columns) {
      final name = _identifier(column.name);
      if (!seen.add(column.name.toLowerCase())) {
        throw ArgumentError('列名重复：${column.name}');
      }
      if (!columnTypes.contains(column.type)) {
        throw ArgumentError('不支持的列类型：${column.type}');
      }
      if (column.primaryKey) keys.add(name);
      definitions.add(
        '$name ${column.type}'
        '${column.notNull || column.primaryKey ? ' NOT NULL' : ''}',
      );
    }
    if (keys.length == 1) {
      final key = columns.singleWhere((column) => column.primaryKey);
      if (key.type == 'INTEGER' || key.type == 'BIGINT') {
        final index = columns.indexOf(key);
        definitions[index] = '${definitions[index]} AUTO_INCREMENT';
      }
    }
    if (keys.isNotEmpty) definitions.add('PRIMARY KEY (${keys.join(', ')})');
    await _query(
      databaseName,
      'CREATE TABLE ${_identifier(table)} (${definitions.join(', ')}) '
      'ENGINE = InnoDB',
    );
  }

  @override
  Future<void> deleteTable(String databaseName, String table) async {
    _requireUserDatabase(databaseName);
    await _query(databaseName, 'DROP TABLE ${_identifier(table)}');
  }

  @override
  Future<void> insertRow(
    String databaseName,
    String table,
    Map<String, String?> values,
  ) async {
    final columns = await tableColumns(databaseName, table);
    _validateColumns(values.keys, columns);
    final names = values.keys.toList();
    for (final name in names) {
      _validateValue(
        columns.singleWhere((column) => column.name == name),
        values[name],
      );
    }
    await _query(
      databaseName,
      'INSERT INTO ${_identifier(table)} '
      '(${names.map(_identifier).join(', ')}) '
      'VALUES (${names.map((name) => _placeholder(columns.singleWhere((column) => column.name == name))).join(', ')})',
      [for (final name in names) values[name]],
    );
  }

  @override
  Future<void> updateCell(
    String databaseName,
    String table,
    String rowId,
    String column,
    String? value,
  ) async {
    final columns = await tableColumns(databaseName, table);
    _validateColumns([column], columns);
    final metadata = columns.singleWhere((item) => item.name == column);
    _validateValue(metadata, value);
    final identity = _decodeIdentity(rowId, columns);
    final result = await _query(
      databaseName,
      'UPDATE ${_identifier(table)} SET ${_identifier(column)} = ${_placeholder(metadata)} '
      'WHERE ${_predicate(identity, columns)}',
      [value, ...identity.values],
    );
    // The native client must use CLIENT_FOUND_ROWS for unchanged cell values.
    if (result.affectedRows != 1) throw StateError('该行已发生变化，请刷新后重试');
  }

  @override
  Future<void> deleteRow(
    String databaseName,
    String table,
    String rowId,
  ) async {
    final columns = await tableColumns(databaseName, table);
    final identity = _decodeIdentity(rowId, columns);
    final result = await _query(
      databaseName,
      'DELETE FROM ${_identifier(table)} WHERE ${_predicate(identity, columns)}',
      identity.values.toList(),
    );
    if (result.affectedRows != 1) throw StateError('该行已发生变化，请刷新后重试');
  }

  @override
  Future<SqlQueryResult> runQuery(String databaseName, String source) =>
      database.query(databasePath: databasePath(databaseName), source: source);

  Future<SqlQueryResult> _query(
    String schema,
    String source, [
    List<String?> parameters = const [],
  ]) async {
    if (schema.isNotEmpty) databasePath(schema);
    final result = await database.query(
      databasePath: schema,
      source: source,
      parameters: parameters,
    );
    if (!result.success) {
      throw StateError(result.error ?? 'SQL 执行失败（${result.exitCode}）');
    }
    if (result.truncated) throw StateError('数据超过显示上限，请缩小查询范围');
    return result;
  }

  static String _identifier(String name) {
    if (name.isEmpty ||
        name != name.trim() ||
        name.contains('\u0000') ||
        name.runes.length > 64) {
      throw ArgumentError.value(name, 'name', '名称无效');
    }
    return '`${name.replaceAll('`', '``')}`';
  }

  static void _requireUserDatabase(String name) {
    if (const {
      'mysql',
      'information_schema',
      'performance_schema',
      'sys',
    }.contains(name.toLowerCase())) {
      throw ArgumentError('不能删除 MySQL 系统对象');
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

  static Map<String, String> _decodeIdentity(
    String rowId,
    List<SqlColumn> columns,
  ) {
    final keys = columns.where((column) => column.primaryKey).toList();
    if (keys.isEmpty) throw StateError('该表没有可用的主键');
    final Object? decoded;
    try {
      decoded = jsonDecode(rowId);
    } on FormatException {
      throw ArgumentError('行标识无效，请刷新后重试');
    }
    if (decoded is! List || decoded.length != keys.length) {
      throw ArgumentError('行标识无效，请刷新后重试');
    }
    final values = <String, String>{};
    for (var index = 0; index < keys.length; index++) {
      final part = decoded[index];
      if (part is! List ||
          part.length != 2 ||
          part[0] != keys[index].name ||
          part[1] is! String) {
        throw ArgumentError('行标识已过期，请刷新后重试');
      }
      values[keys[index].name] = part[1] as String;
    }
    return values;
  }

  static String _predicate(
    Map<String, String> identity,
    List<SqlColumn> columns,
  ) => identity.keys
      .map((name) {
        final column = columns.singleWhere((column) => column.name == name);
        _validateValue(column, identity[name]);
        return '${_identifier(name)} = ${_placeholder(column)}';
      })
      .join(' AND ');

  static bool _binary(SqlColumn column) => RegExp(
    r'^(tinyblob|blob|mediumblob|longblob|binary|varbinary|bit)(\(|$)',
    caseSensitive: false,
  ).hasMatch(column.type);

  static String _placeholder(SqlColumn column) =>
      _binary(column) ? 'UNHEX(?)' : '?';

  static String _projection(SqlColumn column) {
    final name = _identifier(column.name);
    return _binary(column) ? 'HEX($name) AS $name' : name;
  }

  static void _validateValue(SqlColumn column, String? value) {
    if (_binary(column) &&
        value != null &&
        !RegExp(r'^[0-9a-fA-F]*$').hasMatch(value)) {
      throw ArgumentError('${column.name} 需要十六进制字节');
    }
  }
}
