import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/services/app_paths.dart';

import 'mysql_database.dart';
import 'sql_database.dart';
import 'sql_workspace_repository.dart';

/// Oracle MySQL operations. The injected client owns the local server lifecycle.
/// Here, SqlDatabase.databasePath is a schema name, not a SQLite file path.
class MySqlWorkspaceRepository extends SqlWorkspaceRepository {
  const MySqlWorkspaceRepository({
    required Directory runtimeDirectory,
    required super.database,
  }) : super(root: runtimeDirectory);

  static Future<MySqlWorkspaceRepository> openLocal() async {
    final storage = await AppPaths.storageDirectory();
    if (storage == null) {
      throw const FileSystemException('无法访问应用数据目录');
    }
    final runtime = Directory(p.join(storage, 'mysql'));
    await runtime.create(recursive: true);
    return MySqlWorkspaceRepository(
      runtimeDirectory: runtime,
      database: const NativeMySqlDatabase(),
    );
  }

  @override
  bool get supportsSchemaTools => true;

  @override
  bool get supportsSqlExport => true;

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
      'SELECT c.COLUMN_NAME, c.COLUMN_TYPE, c.IS_NULLABLE, '
      'EXISTS (SELECT 1 FROM information_schema.STATISTICS s '
      'WHERE s.TABLE_SCHEMA = c.TABLE_SCHEMA AND s.TABLE_NAME = c.TABLE_NAME '
      "AND s.INDEX_NAME = 'PRIMARY' AND s.COLUMN_NAME = c.COLUMN_NAME) AS IS_PRIMARY, c.EXTRA "
      'FROM information_schema.COLUMNS c '
      'WHERE c.TABLE_SCHEMA = ? AND c.TABLE_NAME = ? ORDER BY c.ORDINAL_POSITION',
      [databaseName, table],
    );
    if (result.rows.isEmpty) throw StateError('数据表不存在：$table');
    return [
      for (final row in result.rows)
        SqlColumn(
          name: row[0]!,
          type: row[1]!,
          notNull: row[2] == 'NO',
          primaryKey: row[3] == '1',
          generated:
              row.length > 4 &&
              (row[4]?.contains('VIRTUAL GENERATED') == true ||
                  row[4]?.contains('STORED GENERATED') == true),
          autoIncrement:
              row.length > 4 && row[4]?.contains('auto_increment') == true,
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
  Future<void> renameTable(
    String databaseName,
    String table,
    String name,
  ) async {
    _requireUserDatabase(databaseName);
    await _query(
      databaseName,
      'RENAME TABLE ${_identifier(table)} TO ${_identifier(name)}',
    );
  }

  @override
  Future<void> addColumn(
    String databaseName,
    String table,
    SqlColumnDraft column,
  ) async {
    _requireUserDatabase(databaseName);
    if (!columnTypes.contains(column.type)) {
      throw ArgumentError('不支持的列类型：${column.type}');
    }
    if (column.primaryKey) throw ArgumentError('添加列时不支持设置主键');
    await _query(
      databaseName,
      'ALTER TABLE ${_identifier(table)} ADD COLUMN '
      '${_identifier(column.name)} ${column.type}'
      '${column.notNull ? ' NOT NULL' : ' NULL'}',
    );
  }

  @override
  Future<void> renameColumn(
    String databaseName,
    String table,
    String column,
    String name,
  ) async {
    _requireUserDatabase(databaseName);
    _validateColumns([column], await tableColumns(databaseName, table));
    await _query(
      databaseName,
      'ALTER TABLE ${_identifier(table)} RENAME COLUMN '
      '${_identifier(column)} TO ${_identifier(name)}',
    );
  }

  @override
  Future<void> deleteColumn(
    String databaseName,
    String table,
    String column,
  ) async {
    _requireUserDatabase(databaseName);
    _validateColumns([column], await tableColumns(databaseName, table));
    await _query(
      databaseName,
      'ALTER TABLE ${_identifier(table)} DROP COLUMN ${_identifier(column)}',
    );
  }

  @override
  Future<List<SqlIndex>> tableIndexes(String databaseName, String table) async {
    await tableColumns(databaseName, table);
    final result = await _query(
      databaseName,
      'SELECT INDEX_NAME, NON_UNIQUE, COLUMN_NAME, EXPRESSION '
      'FROM information_schema.STATISTICS '
      'WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ? '
      'ORDER BY INDEX_NAME, SEQ_IN_INDEX',
      [databaseName, table],
    );
    final grouped = <String, List<List<String?>>>{};
    for (final row in result.rows) {
      grouped.putIfAbsent(row[0]!, () => []).add(row);
    }
    return [
      for (final entry in grouped.entries)
        SqlIndex(
          name: entry.key,
          columns: [for (final row in entry.value) row[2] ?? row[3] ?? ''],
          unique: entry.value.first[1] == '0',
          primary: entry.key == 'PRIMARY',
        ),
    ];
  }

  @override
  Future<void> createIndex(
    String databaseName,
    String table,
    String name,
    List<String> columns, {
    bool unique = false,
  }) async {
    _requireUserDatabase(databaseName);
    if (columns.isEmpty || columns.toSet().length != columns.length) {
      throw ArgumentError('请选择不重复的索引列');
    }
    _validateColumns(columns, await tableColumns(databaseName, table));
    await _query(
      databaseName,
      'CREATE ${unique ? 'UNIQUE ' : ''}INDEX ${_identifier(name)} '
      'ON ${_identifier(table)} (${columns.map(_identifier).join(', ')})',
    );
  }

  @override
  Future<void> deleteIndex(
    String databaseName,
    String table,
    String name,
  ) async {
    _requireUserDatabase(databaseName);
    final indexes = await tableIndexes(databaseName, table);
    if (!indexes.any((index) => index.name == name)) {
      throw ArgumentError('索引不存在：$name');
    }
    await _query(
      databaseName,
      'ALTER TABLE ${_identifier(table)} DROP '
      '${name == 'PRIMARY' ? 'PRIMARY KEY' : 'INDEX ${_identifier(name)}'}',
    );
  }

  @override
  Future<void> insertRow(
    String databaseName,
    String table,
    Map<String, String?> values,
  ) async {
    final columns = await tableColumns(databaseName, table);
    _validateColumns(values.keys, columns);
    if (values.keys.any(
      (name) => columns.singleWhere((column) => column.name == name).generated,
    )) {
      throw ArgumentError('生成列不能直接写入');
    }
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
    if (metadata.generated) throw ArgumentError('生成列不能直接写入');
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
      database.query(
        databasePath: databaseName.isEmpty ? '' : databasePath(databaseName),
        source: source,
      );

  @override
  Future<SqlScriptResult> runScript(String databaseName, String source) async {
    final client = database;
    if (client is SqlScriptDatabase) {
      return (client as SqlScriptDatabase).executeScript(
        databasePath: databaseName.isEmpty ? '' : databasePath(databaseName),
        source: source,
      );
    }
    final result = await runQuery(databaseName, source);
    return SqlScriptResult(summary: result, results: [result]);
  }

  @override
  Future<String> exportTableSql(String databaseName, String table) async {
    final engine = await _query(
      databaseName,
      'SELECT ENGINE FROM information_schema.TABLES '
      'WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ?',
      [databaseName, table],
    );
    if (engine.rows.isEmpty) throw StateError('数据表不存在：$table');
    if (engine.rows.single.single?.toUpperCase() != 'INNODB') {
      throw UnsupportedError('快照导出仅支持 InnoDB 表，未生成导出文件');
    }
    final metadata = await tableColumns(databaseName, table);
    final columns = metadata.where((column) => !column.generated).toList();
    if (columns.any(
      (column) => RegExp(
        r'^(geometry|point|linestring|polygon|multipoint|multilinestring|multipolygon|geometrycollection)(\(|$)',
        caseSensitive: false,
      ).hasMatch(column.type),
    )) {
      throw UnsupportedError('空间类型需要专用备份工具，未生成导出文件');
    }
    final projections = [
      for (final column in columns)
        'CAST(${_binary(column) ? 'HEX(${_identifier(column.name)})' : 'HEX(CAST(${_identifier(column.name)} AS CHAR CHARACTER SET utf8mb4))'} '
            'AS CHAR CHARACTER SET utf8mb4)',
    ];
    // Read all rows in one connection so unkeyed tables cannot drift across pages.
    final snapshot = await runScript(
      databaseName,
      "SET SESSION time_zone = '+00:00'; "
      'START TRANSACTION WITH CONSISTENT SNAPSHOT, READ ONLY; '
      'SHOW CREATE TABLE ${_identifier(table)}; '
      'SELECT ${projections.isEmpty ? '1' : projections.join(', ')} '
      'FROM ${_identifier(table)}; COMMIT;',
    );
    if (!snapshot.success) {
      throw StateError(snapshot.error ?? 'SQL 导出失败');
    }
    if (snapshot.truncated ||
        snapshot.results.any((result) => result.truncated)) {
      throw StateError('表数据超过导出上限（1,000 行 / 1 MiB），未生成导出文件');
    }
    if (snapshot.results.length != 5) {
      throw StateError('数据库未返回完整导出结果，未生成导出文件');
    }
    final output = StringBuffer()
      ..writeln('-- QFLISQLab Oracle MySQL table export')
      ..writeln('-- NULL is SQL NULL; values use hexadecimal literals.')
      ..writeln('SET NAMES utf8mb4;')
      ..writeln("SET SESSION time_zone = '+00:00';")
      ..writeln("SET SESSION sql_mode = 'NO_AUTO_VALUE_ON_ZERO';")
      ..writeln('${snapshot.results[2].rows.single[1]};');
    var outputBytes = utf8.encode(output.toString()).length;
    final rows = snapshot.results[3].rows;
    if (rows.isNotEmpty) {
      final insert =
          'INSERT INTO ${_identifier(table)} '
          '(${columns.map((column) => _identifier(column.name)).join(', ')}) VALUES';
      output.writeln(insert);
      outputBytes += utf8.encode(insert).length + 1;
    }
    for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
      final row = rows[rowIndex];
      final values = [
        for (var index = 0; index < columns.length; index++)
          row[index] == null
              ? 'NULL'
              : _binary(columns[index])
              ? "X'${row[index]}'"
              : "CONVERT(X'${row[index]}' USING utf8mb4)",
      ];
      final statement =
          '(${values.join(', ')})'
          '${rowIndex == rows.length - 1 ? ';' : ','}';
      outputBytes += utf8.encode(statement).length + 1;
      if (outputBytes > 1024 * 1024) {
        throw StateError('SQL 导出超过 1 MiB 上限，未生成导出文件');
      }
      output.writeln(statement);
    }
    return output.toString();
  }

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
