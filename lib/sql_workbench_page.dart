import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qfli_studio_core/pages/home_page.dart';
import 'package:qfli_studio_core/services/picker_service.dart';
import 'package:qfli_studio_core/store/auth_store.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/store/settings_store.dart';

import 'sql_database.dart';
import 'mysql_workspace_repository.dart';
import 'sql_document_service.dart';
import 'sql_query_library.dart';
import 'sql_workspace_repository.dart';
import 'sqlite_ffi.dart';

class SqlWorkbenchPage extends StatefulWidget {
  const SqlWorkbenchPage({
    super.key,
    required this.store,
    required this.auth,
    required this.settings,
    this.repositoryFactory,
    this.queryLibraryFactory,
  });

  final ProjectStore store;
  final AuthStore auth;
  final SettingsStore settings;
  final Future<SqlWorkspaceRepository> Function()? repositoryFactory;
  final Future<SqlQueryLibrary> Function()? queryLibraryFactory;

  @override
  State<SqlWorkbenchPage> createState() => _SqlWorkbenchPageState();
}

class _SqlWorkbenchPageState extends State<SqlWorkbenchPage> {
  final _queryController = TextEditingController();
  final _filterController = TextEditingController();
  SqlWorkspaceRepository? _repository;
  SqlQueryLibrary? _queryLibrary;
  List<String> _databases = [];
  List<String> _tables = [];
  String? _database;
  String? _table;
  SqlTablePage? _tablePage;
  List<SqlColumn>? _schemaColumns;
  SqlScriptResult? _queryResult;
  List<SqlIndex> _indexes = [];
  String? _loadError;
  String? _tableError;
  String? _schemaError;
  String? _queryLibraryError;
  String? _filterColumn;
  String? _sortColumn;
  bool _descending = false;
  _WorkbenchView _view = _WorkbenchView.data;
  bool _busy = true;
  bool _queryLibraryLoading = true;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
    unawaited(_loadQueryLibrary());
  }

  @override
  void dispose() {
    _queryController.dispose();
    _filterController.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    setState(() {
      _busy = true;
      _loadError = null;
    });
    try {
      final repository =
          await (widget.repositoryFactory?.call() ??
              (SqliteFfi.supported
                  ? SqlWorkspaceRepository.openDefault()
                  : MySqlWorkspaceRepository.openLocal()));
      if (!mounted) return;
      _repository = repository;
      await _refreshTree();
      if (mounted) setState(() => _loadError = null);
    } catch (error) {
      if (mounted) {
        setState(() {
          _repository = null;
          _loadError = _message(error);
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _perform(Future<void> Function() action) async {
    if (!mounted || _busy || _repository == null) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_message(error))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadQueryLibrary() async {
    setState(() {
      _queryLibraryLoading = true;
      _queryLibraryError = null;
      _queryLibrary = null;
    });
    try {
      final library =
          await (widget.queryLibraryFactory?.call() ??
              SqlQueryLibrary.openDefault());
      if (mounted) setState(() => _queryLibrary = library);
    } catch (error) {
      if (mounted) {
        setState(() => _queryLibraryError = _message(error));
      }
    } finally {
      if (mounted) setState(() => _queryLibraryLoading = false);
    }
  }

  Future<void> _performLibrary(
    Future<void> Function(SqlQueryLibrary library) action,
  ) async {
    final library = _queryLibrary;
    if (library == null) return;
    await _perform(() async {
      try {
        await action(library);
        if (mounted) setState(() => _queryLibraryError = null);
      } catch (error) {
        if (mounted) {
          setState(() => _queryLibraryError = _message(error));
        }
        rethrow;
      }
    });
  }

  String _message(Object error) => error
      .toString()
      .replaceFirst('Bad state: ', '')
      .replaceFirst('FileSystemException: ', '');

  Future<void> _refreshTree({String? database, String? table}) async {
    if (!mounted) return;
    final repository = _repository!;
    final databases = await repository.listDatabases();
    final selectedDatabase = databases.contains(database ?? _database)
        ? database ?? _database
        : (databases.isEmpty ? null : databases.first);
    final tables = selectedDatabase == null
        ? <String>[]
        : await repository.listTables(selectedDatabase);
    final selectedTable = tables.contains(table ?? _table)
        ? table ?? _table
        : (tables.isEmpty ? null : tables.first);
    if (!mounted) return;
    setState(() {
      if (selectedDatabase != _database || selectedTable != _table) {
        _tablePage = null;
        _tableError = null;
        _schemaColumns = null;
        _schemaError = null;
        _indexes = [];
        _page = 0;
        _filterColumn = null;
        _filterController.clear();
        _sortColumn = null;
        _descending = false;
      }
      _databases = databases;
      _tables = tables;
      _database = selectedDatabase;
      _table = selectedTable;
      if (selectedTable == null && _view == _WorkbenchView.schema) {
        _view = _WorkbenchView.data;
      }
    });
    if (selectedTable != null) await _refreshTable();
  }

  Future<void> _refreshTable() async {
    if (!mounted) return;
    if (_view == _WorkbenchView.schema) return _refreshSchema();
    final database = _database;
    final table = _table;
    if (database == null || table == null) return;
    try {
      final result = await _repository!.loadTable(
        database,
        table,
        page: _page,
        filterColumn: _filterColumn,
        filter: _filterController.text.trim(),
        sortColumn: _sortColumn,
        descending: _descending,
      );
      if (_page > 0 &&
          _page * SqlWorkspaceRepository.pageSize >= result.totalRows) {
        _page = result.totalRows == 0
            ? 0
            : (result.totalRows - 1) ~/ SqlWorkspaceRepository.pageSize;
        return _refreshTable();
      }
      if (mounted) {
        setState(() {
          _tablePage = result;
          _tableError = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _tablePage = null;
          _tableError = _message(error);
        });
      }
      rethrow;
    }
  }

  Future<void> _refreshSchema() async {
    final database = _database;
    final table = _table;
    if (!mounted || database == null || table == null) return;
    setState(() {
      _tablePage = null;
      _schemaColumns = null;
      _schemaError = null;
      _indexes = [];
    });
    try {
      final columns = await _repository!.tableColumns(database, table);
      final indexes = await _repository!.tableIndexes(database, table);
      if (mounted) {
        setState(() {
          _schemaColumns = columns;
          _indexes = indexes;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _schemaError = _message(error));
      rethrow;
    }
  }

  void _selectDatabase(String name) => unawaited(
    _perform(() async {
      setState(() {
        _database = name;
        _table = null;
        _tablePage = null;
        _tableError = null;
        _schemaColumns = null;
        _schemaError = null;
        _indexes = [];
        _queryResult = null;
        _view = _WorkbenchView.data;
        _page = 0;
        _filterColumn = null;
        _filterController.clear();
        _sortColumn = null;
      });
      await _refreshTree(database: name);
    }),
  );

  void _selectTable(String name) => unawaited(
    _perform(() async {
      setState(() {
        _table = name;
        _tablePage = null;
        _tableError = null;
        _schemaColumns = null;
        _schemaError = null;
        _indexes = [];
        _view = _WorkbenchView.data;
        _page = 0;
        _filterColumn = null;
        _filterController.clear();
        _sortColumn = null;
      });
      await _refreshTable();
    }),
  );

  Future<void> _createDatabase() async {
    final name = await _nameDialog('新建数据库', '数据库名称');
    if (name == null) return;
    await _perform(() async {
      await _repository!.createDatabase(name);
      if (!mounted) return;
      setState(() {
        _table = null;
        _page = 0;
      });
      await _refreshTree(database: name);
    });
  }

  Future<void> _deleteDatabase(String name) async {
    if (!await _confirm('删除数据库', '确定删除“$name”及其中的所有数据吗？')) return;
    await _perform(() async {
      await _repository!.deleteDatabase(name);
      if (_database == name) {
        _database = null;
        _table = null;
        _tablePage = null;
      }
      await _refreshTree();
    });
  }

  Future<void> _createTable() async {
    final database = _database;
    if (database == null) return;
    final spec = await _tableDialog();
    if (spec == null) return;
    await _perform(() async {
      await _repository!.createTable(database, spec.name, spec.columns);
      if (!mounted) return;
      setState(() => _page = 0);
      await _refreshTree(database: database, table: spec.name);
    });
  }

  Future<void> _deleteTable(String table) async {
    final database = _database;
    if (database == null) return;
    if (!await _confirm('删除数据表', '确定删除“$table”及其中的所有行吗？')) return;
    await _perform(() async {
      await _repository!.deleteTable(database, table);
      if (_table == table) {
        _table = null;
        _tablePage = null;
      }
      await _refreshTree(database: database);
    });
  }

  Future<void> _renameTable(String table) async {
    final database = _database;
    if (database == null || _busy) return;
    final name = await _nameDialog(
      '重命名数据表',
      '新表名',
      actionLabel: '重命名',
      initial: table,
    );
    if (name == null || name == table) return;
    await _perform(() async {
      await _repository!.renameTable(database, table, name);
      await _refreshTree(
        database: database,
        table: _table == table ? name : _table,
      );
    });
  }

  Future<void> _showSchema(String table) async {
    await _perform(() async {
      setState(() {
        _table = table;
        _tablePage = null;
        _tableError = null;
        _schemaColumns = null;
        _schemaError = null;
        _indexes = [];
        _view = _WorkbenchView.schema;
        _page = 0;
        _filterColumn = null;
        _sortColumn = null;
        _filterController.clear();
      });
      await _refreshTable();
    });
  }

  Future<void> _addColumn() async {
    final database = _database;
    final table = _table;
    if (_busy || database == null || table == null) return;
    final draft = await _columnDialog();
    if (draft == null) return;
    await _perform(() async {
      await _repository!.addColumn(database, table, draft);
      await _refreshTable();
    });
  }

  Future<void> _renameColumn(SqlColumn column) async {
    final database = _database;
    final table = _table;
    if (_busy || database == null || table == null) return;
    final name = await _nameDialog(
      '重命名列',
      '新列名',
      actionLabel: '重命名',
      initial: column.name,
    );
    if (name == null || name == column.name) return;
    await _perform(() async {
      await _repository!.renameColumn(database, table, column.name, name);
      _resetTableFilters();
      await _refreshTable();
    });
  }

  Future<void> _deleteColumn(SqlColumn column) async {
    final database = _database;
    final table = _table;
    if (_busy || database == null || table == null) return;
    if (!await _confirm('删除列', '确定删除“${column.name}”及该列的所有数据吗？关联索引也可能被修改。'))
      return;
    await _perform(() async {
      await _repository!.deleteColumn(database, table, column.name);
      _resetTableFilters();
      await _refreshTable();
    });
  }

  Future<void> _createIndex() async {
    final database = _database;
    final table = _table;
    final columns = _schemaColumns;
    if (_busy || database == null || table == null || columns == null) return;
    final draft = await _indexDialog(columns);
    if (draft == null) return;
    await _perform(() async {
      await _repository!.createIndex(
        database,
        table,
        draft.name,
        draft.columns,
        unique: draft.unique,
      );
      await _refreshTable();
    });
  }

  Future<void> _deleteIndex(SqlIndex index) async {
    final database = _database;
    final table = _table;
    if (_busy || database == null || table == null) return;
    if (!await _confirm(
      '删除索引',
      '确定删除“${index.name}”吗？'
          '${index.primary ? '该表将失去主键，现有行可能无法编辑。' : ''}',
    ))
      return;
    await _perform(() async {
      await _repository!.deleteIndex(database, table, index.name);
      await _refreshTable();
    });
  }

  void _resetTableFilters() {
    _page = 0;
    _filterColumn = null;
    _filterController.clear();
    _sortColumn = null;
    _descending = false;
  }

  Future<void> _exportTable(String table) async {
    final database = _database;
    if (_busy || database == null) return;
    await _perform(() async {
      final source = await _repository!.exportTableSql(database, table);
      final location = await PickerService.saveDocument(
        suggestedName:
            '${table.replaceAll(RegExp(r'[^a-zA-Z0-9_\u4e00-\u9fff-]'), '_')}.sql',
      );
      if (location == null) return;
      await SqlDocumentService.write(location, source);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('已导出 $table')));
      }
    });
  }

  Future<void> _importSql() async {
    if (_busy) return;
    await _perform(() async {
      final document = await PickerService.pickDocument(extensions: ['sql']);
      if (document == null) return;
      final source = await SqlDocumentService.read(document);
      if (source.trim().isEmpty) throw const FormatException('SQL 文件为空');
      if (!mounted) return;
      if (!await _confirm(
        '导入 SQL',
        '执行“${document.name ?? 'SQL 文件'}”中的 SQL 吗？'
            '目标：${_database ?? 'MySQL 服务器'}。'
            '脚本可能修改或删除数据；执行失败时，前面的语句可能已经生效。',
        actionLabel: '导入',
      ))
        return;
      if (!mounted) return;
      _queryController.text = source;
      setState(() => _view = _WorkbenchView.sql);
      await _executeScript(_database ?? '', source);
    });
  }

  Future<void> _insertRow() async {
    final database = _database;
    final table = _table;
    final page = _tablePage;
    if (_busy || database == null || table == null || page == null) {
      return;
    }
    final values = await _rowDialog(page.columns);
    if (values == null) return;
    await _perform(() async {
      await _repository!.insertRow(database, table, values);
      await _refreshTable();
    });
  }

  Future<void> _editCell(int row, int column) async {
    final database = _database;
    final table = _table;
    final page = _tablePage;
    if (_busy || database == null || table == null || page == null) {
      return;
    }
    final field = page.columns[column];
    final value = await _valueDialog(field, page.rows[row][column]);
    if (value == null) return;
    await _perform(() async {
      await _repository!.updateCell(
        database,
        table,
        page.rowIds[row],
        field.name,
        value.value,
      );
      await _refreshTable();
    });
  }

  Future<void> _deleteRow(int row) async {
    final database = _database;
    final table = _table;
    final page = _tablePage;
    if (_busy ||
        database == null ||
        table == null ||
        page == null ||
        !page.editable) {
      return;
    }
    if (!await _confirm('删除行', '确定删除选中的行吗？')) return;
    await _perform(() async {
      await _repository!.deleteRow(database, table, page.rowIds[row]);
      await _refreshTable();
    });
  }

  Future<void> _runQuery() async {
    final database = _database ?? '';
    final source = _queryController.text.trim();
    if (source.isEmpty) return;
    await _perform(() => _executeScript(database, source));
  }

  Future<void> _executeScript(String database, String source) async {
    final result = await _repository!.runScript(database, source);
    if (!mounted) return;
    setState(() => _queryResult = result);
    try {
      await _queryLibrary?.recordExecution(
        database: database,
        source: source,
        success: result.success,
      );
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) {
        setState(() => _queryLibraryError = _message(error));
      }
    }
    if (!mounted) return;
    setState(() {
      _tablePage = null;
      _tableError = null;
      _resetTableFilters();
    });
    await _refreshTree(database: database);
  }

  Future<void> _saveQuery() async {
    final database = _database ?? '';
    final source = _queryController.text.trim();
    if (_busy || source.isEmpty) return;
    final name = await _nameDialog('保存查询', '查询名称', actionLabel: '保存');
    if (name == null) return;
    await _performLibrary(
      (library) =>
          library.saveQuery(database: database, name: name, source: source),
    );
  }

  void _restoreQuery(String source) {
    _queryController.text = source;
    setState(() => _queryResult = null);
  }

  Future<void> _deleteSavedQuery(SqlSavedQuery query) async {
    if (!await _confirm('删除保存的查询', '确定删除“${query.name}”吗？')) return;
    await _performLibrary(
      (library) => library.deleteSavedQuery(query.database, query.name),
    );
  }

  Future<void> _clearHistory() async {
    if (!await _confirm('清空历史记录', '确定清空所有数据库的查询历史吗？', actionLabel: '清空')) {
      return;
    }
    await _performLibrary((library) => library.clearHistory());
  }

  Future<String?> _nameDialog(
    String title,
    String label, {
    String actionLabel = '创建',
    String initial = '',
  }) async {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (context) => _DialogLifetime(
        onDispose: controller.dispose,
        child: AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(labelText: label),
            onSubmitted: (_) => Navigator.pop(context, controller.text.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _confirm(
    String title,
    String description, {
    String actionLabel = '删除',
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(description),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(actionLabel),
            ),
          ],
        ),
      ) ??
      false;

  Future<_TableSpec?> _tableDialog() async {
    final tableName = TextEditingController();
    final fields = <_ColumnInput>[_ColumnInput()];
    final allocatedFields = <_ColumnInput>[...fields];
    return showDialog<_TableSpec>(
      context: context,
      builder: (context) => _DialogLifetime(
        onDispose: () {
          tableName.dispose();
          for (final field in allocatedFields) {
            field.dispose();
          }
        },
        child: StatefulBuilder(
          builder: (context, redraw) => AlertDialog(
            title: const Text('新建数据表'),
            content: SizedBox(
              width: 560,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: tableName,
                      autofocus: true,
                      decoration: const InputDecoration(labelText: '表名'),
                    ),
                    const SizedBox(height: 16),
                    for (final field in fields)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: field.name,
                                    decoration: const InputDecoration(
                                      labelText: '列名',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  tooltip: '移除列',
                                  onPressed: fields.length == 1
                                      ? null
                                      : () =>
                                            redraw(() => fields.remove(field)),
                                  icon: const Icon(Icons.remove_circle_outline),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              key: ValueKey(
                                '${identityHashCode(field)}-${field.type}',
                              ),
                              initialValue: field.type,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: '类型',
                              ),
                              items: [
                                for (final type in _repository!.columnTypes)
                                  DropdownMenuItem(
                                    value: type,
                                    child: Text(type),
                                  ),
                              ],
                              onChanged: (value) =>
                                  redraw(() => field.type = value!),
                            ),
                            Row(
                              children: [
                                Checkbox(
                                  value: field.primaryKey,
                                  onChanged: (value) => redraw(() {
                                    field.primaryKey = value ?? false;
                                    if (field.primaryKey) {
                                      field.type = 'INTEGER';
                                    }
                                  }),
                                ),
                                const Text('主键'),
                                Checkbox(
                                  value: field.notNull,
                                  onChanged: (value) => redraw(
                                    () => field.notNull = value ?? false,
                                  ),
                                ),
                                const Text('非空'),
                              ],
                            ),
                          ],
                        ),
                      ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => redraw(() {
                          final field = _ColumnInput();
                          fields.add(field);
                          allocatedFields.add(field);
                        }),
                        icon: const Icon(Icons.add),
                        label: const Text('添加列'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(
                  context,
                  _TableSpec(tableName.text.trim(), [
                    for (final field in fields) field.toDraft(),
                  ]),
                ),
                child: const Text('创建'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<SqlColumnDraft?> _columnDialog() async {
    final field = _ColumnInput();
    return showDialog<SqlColumnDraft>(
      context: context,
      builder: (context) => _DialogLifetime(
        onDispose: field.dispose,
        child: StatefulBuilder(
          builder: (context, redraw) => AlertDialog(
            title: const Text('添加列'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: field.name,
                      autofocus: true,
                      decoration: const InputDecoration(labelText: '列名'),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: field.type,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: '类型'),
                      items: [
                        for (final type in _repository!.columnTypes)
                          DropdownMenuItem(value: type, child: Text(type)),
                      ],
                      onChanged: (value) => redraw(() => field.type = value!),
                    ),
                    CheckboxListTile(
                      title: const Text('非空'),
                      contentPadding: EdgeInsets.zero,
                      value: field.notNull,
                      onChanged: (value) =>
                          redraw(() => field.notNull = value ?? false),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, field.toDraft()),
                child: const Text('添加'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<_IndexDraft?> _indexDialog(List<SqlColumn> columns) async {
    final name = TextEditingController();
    final selected = <String>[];
    var unique = false;
    return showDialog<_IndexDraft>(
      context: context,
      builder: (context) => _DialogLifetime(
        onDispose: name.dispose,
        child: StatefulBuilder(
          builder: (context, redraw) => AlertDialog(
            title: const Text('新建索引'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: name,
                      autofocus: true,
                      decoration: const InputDecoration(labelText: '索引名称'),
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('唯一索引'),
                      value: unique,
                      onChanged: (value) =>
                          redraw(() => unique = value ?? false),
                    ),
                    for (final column in columns)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(column.name),
                        value: selected.contains(column.name),
                        onChanged: (value) => redraw(() {
                          if (value == true) {
                            selected.add(column.name);
                          } else {
                            selected.remove(column.name);
                          }
                        }),
                      ),
                    if (selected.isNotEmpty) ...[
                      const Divider(),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text('索引列顺序'),
                      ),
                      for (var index = 0; index < selected.length; index++)
                        Row(
                          children: [
                            Expanded(
                              child: Text('${index + 1}. ${selected[index]}'),
                            ),
                            IconButton(
                              tooltip: '前移',
                              onPressed: index == 0
                                  ? null
                                  : () => redraw(() {
                                      final value = selected.removeAt(index);
                                      selected.insert(index - 1, value);
                                    }),
                              icon: const Icon(Icons.arrow_upward, size: 18),
                            ),
                            IconButton(
                              tooltip: '后移',
                              onPressed: index == selected.length - 1
                                  ? null
                                  : () => redraw(() {
                                      final value = selected.removeAt(index);
                                      selected.insert(index + 1, value);
                                    }),
                              icon: const Icon(Icons.arrow_downward, size: 18),
                            ),
                          ],
                        ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: selected.isEmpty
                    ? null
                    : () => Navigator.pop(
                        context,
                        _IndexDraft(
                          name.text.trim(),
                          List.of(selected),
                          unique,
                        ),
                      ),
                child: const Text('创建'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<Map<String, String?>?> _rowDialog(List<SqlColumn> columns) async {
    columns = columns.where((column) => !column.generated).toList();
    final values = [
      for (final column in columns) _CellInput(initialNull: column.primaryKey),
    ];
    return showDialog<Map<String, String?>>(
      context: context,
      builder: (context) => _DialogLifetime(
        onDispose: () {
          for (final value in values) {
            value.dispose();
          }
        },
        child: StatefulBuilder(
          builder: (context, redraw) => AlertDialog(
            title: const Text('添加行'),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var index = 0; index < columns.length; index++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: values[index].controller,
                                enabled: !values[index].isNull,
                                decoration: InputDecoration(
                                  labelText:
                                      '${columns[index].name} · ${columns[index].type}',
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Checkbox(
                              value: values[index].isNull,
                              onChanged: (value) => redraw(
                                () => values[index].isNull = value ?? false,
                              ),
                            ),
                            const Text('NULL'),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, {
                  for (var index = 0; index < columns.length; index++)
                    columns[index].name: values[index].isNull
                        ? null
                        : values[index].controller.text,
                }),
                child: const Text('添加'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<_EditedValue?> _valueDialog(SqlColumn column, String? initial) async {
    final value = _CellInput(initial: initial, initialNull: initial == null);
    return showDialog<_EditedValue>(
      context: context,
      builder: (context) => _DialogLifetime(
        onDispose: value.dispose,
        child: StatefulBuilder(
          builder: (context, redraw) => AlertDialog(
            title: Text(column.name),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: value.controller,
                  enabled: !value.isNull,
                  autofocus: initial != null,
                  maxLines: 3,
                  minLines: 1,
                  decoration: InputDecoration(labelText: column.type),
                ),
                CheckboxListTile(
                  title: const Text('NULL'),
                  value: value.isNull,
                  onChanged: (checked) =>
                      redraw(() => value.isNull = checked ?? false),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(
                  context,
                  _EditedValue(value.isNull ? null : value.controller.text),
                ),
                child: const Text('保存'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 700;
    return Scaffold(
      drawer: narrow
          ? Drawer(
              child: SafeArea(
                child: Builder(
                  builder: (drawerContext) =>
                      _explorer(drawerContext: drawerContext),
                ),
              ),
            )
          : null,
      appBar: AppBar(
        title: const Text('QFLISQLab'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _busy || _repository == null
                ? null
                : () => unawaited(_perform(_refreshTree)),
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: '项目编辑器',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => HomePage(
                  store: widget.store,
                  auth: widget.auth,
                  settings: widget.settings,
                ),
              ),
            ),
            icon: const Icon(Icons.folder_open_outlined),
          ),
        ],
      ),
      body: _repository == null
          ? Center(
              child: _loadError == null
                  ? const CircularProgressIndicator()
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_loadError!),
                        TextButton.icon(
                          onPressed: _busy
                              ? null
                              : () => unawaited(_initialize()),
                          icon: const Icon(Icons.refresh),
                          label: const Text('重试'),
                        ),
                      ],
                    ),
            )
          : Row(
              children: [
                if (!narrow) ...[
                  SizedBox(width: 252, child: _explorer()),
                  const VerticalDivider(width: 1),
                ],
                Expanded(child: _workspace()),
              ],
            ),
    );
  }

  Widget _explorer({BuildContext? drawerContext}) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Row(
          children: [
            const Expanded(
              child: Text('数据库', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            IconButton(
              tooltip: '新建数据库',
              onPressed: _busy || _repository == null
                  ? null
                  : () => unawaited(_createDatabase()),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      ),
      Expanded(
        child: ListView(
          children: [
            for (final database in _databases) ...[
              ListTile(
                dense: true,
                leading: const Icon(Icons.storage_outlined, size: 20),
                title: Text(database, overflow: TextOverflow.ellipsis),
                selected: database == _database,
                onTap: _busy ? null : () => _selectDatabase(database),
                trailing: PopupMenuButton<String>(
                  enabled: !_busy,
                  tooltip: '数据库操作',
                  onSelected: (action) {
                    if (action == 'delete') {
                      unawaited(_deleteDatabase(database));
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'delete', child: Text('删除数据库')),
                  ],
                ),
              ),
              if (database == _database) ...[
                Padding(
                  padding: const EdgeInsets.only(left: 38, right: 8),
                  child: Row(
                    children: [
                      const Expanded(child: Text('数据表')),
                      IconButton(
                        tooltip: '新建数据表',
                        onPressed: _busy
                            ? null
                            : () => unawaited(_createTable()),
                        icon: const Icon(Icons.add, size: 20),
                      ),
                    ],
                  ),
                ),
                for (final table in _tables)
                  ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.only(left: 42, right: 4),
                    leading: const Icon(Icons.table_chart_outlined, size: 18),
                    title: Text(table, overflow: TextOverflow.ellipsis),
                    selected: table == _table,
                    onTap: _busy
                        ? null
                        : () {
                            if (drawerContext != null) {
                              Navigator.of(drawerContext).pop();
                            }
                            _selectTable(table);
                          },
                    trailing: PopupMenuButton<String>(
                      enabled: !_busy,
                      tooltip: '数据表操作',
                      onSelected: (action) {
                        if (action == 'delete') {
                          unawaited(_deleteTable(table));
                        } else if (action == 'rename') {
                          unawaited(_renameTable(table));
                        } else if (action == 'schema') {
                          if (drawerContext != null) {
                            Navigator.of(drawerContext).pop();
                          }
                          unawaited(_showSchema(table));
                        } else if (action == 'export') {
                          unawaited(_exportTable(table));
                        }
                      },
                      itemBuilder: (_) => [
                        if (_repository!.supportsSchemaTools) ...[
                          const PopupMenuItem(
                            value: 'schema',
                            child: Text('表结构'),
                          ),
                          const PopupMenuItem(
                            value: 'rename',
                            child: Text('重命名'),
                          ),
                        ],
                        if (_repository!.supportsSqlExport)
                          const PopupMenuItem(
                            value: 'export',
                            child: Text('导出 SQL'),
                          ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('删除数据表'),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ],
        ),
      ),
    ],
  );

  Widget _workspace() {
    final compact = MediaQuery.sizeOf(context).width < 480;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _database == null
                      ? (_repository is MySqlWorkspaceRepository
                            ? 'MySQL'
                            : 'SQLite')
                      : _table == null
                      ? _database!
                      : '${_database!} / ${_table!}',
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              SegmentedButton<_WorkbenchView>(
                segments: [
                  ButtonSegment(
                    value: _WorkbenchView.data,
                    label: compact ? null : const Text('数据'),
                    tooltip: '数据',
                    icon: const Icon(Icons.table_rows_outlined),
                  ),
                  if (_repository!.supportsSchemaTools)
                    ButtonSegment(
                      value: _WorkbenchView.schema,
                      label: compact ? null : const Text('结构'),
                      tooltip: '表结构',
                      enabled: _table != null,
                      icon: const Icon(Icons.account_tree_outlined),
                    ),
                  ButtonSegment(
                    value: _WorkbenchView.sql,
                    label: compact ? null : const Text('SQL'),
                    tooltip: 'SQL',
                    icon: const Icon(Icons.code),
                  ),
                ],
                showSelectedIcon: false,
                selected: {_view},
                onSelectionChanged: _busy
                    ? null
                    : (selected) {
                        final view = selected.first;
                        if (view == _WorkbenchView.schema) {
                          unawaited(_showSchema(_table!));
                        } else if (view == _WorkbenchView.data) {
                          unawaited(
                            _perform(() async {
                              setState(() => _view = view);
                              await _refreshTable();
                            }),
                          );
                        } else {
                          setState(() => _view = view);
                        }
                      },
              ),
            ],
          ),
        ),
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: switch (_view) {
            _WorkbenchView.data => _dataPanel(),
            _WorkbenchView.schema => _schemaPanel(),
            _WorkbenchView.sql => _queryPanel(),
          },
        ),
      ],
    );
  }

  Widget _dataPanel() {
    final table = _table;
    final page = _tablePage;
    if (table == null) {
      return Center(
        child: FilledButton.icon(
          onPressed: _busy
              ? null
              : () => unawaited(
                  _database == null ? _createDatabase() : _createTable(),
                ),
          icon: const Icon(Icons.add),
          label: Text(_database == null ? '新建数据库' : '新建数据表'),
        ),
      );
    }
    if (_tableError case final error?) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(error),
            TextButton.icon(
              onPressed: _busy
                  ? null
                  : () => unawaited(_perform(_refreshTable)),
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (page == null) return const Center(child: CircularProgressIndicator());
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 124,
                child: DropdownButtonFormField<String?>(
                  key: ValueKey('filter-${_database!}-${_table!}'),
                  initialValue: _filterColumn,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: '筛选列',
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('全部')),
                    for (final column in page.columns)
                      DropdownMenuItem(
                        value: column.name,
                        child: Text(
                          column.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _filterColumn = value),
                ),
              ),
              SizedBox(
                width: 160,
                child: TextField(
                  controller: _filterController,
                  decoration: const InputDecoration(
                    labelText: '筛选值',
                    isDense: true,
                  ),
                  onSubmitted: (_) => unawaited(
                    _perform(() async {
                      _page = 0;
                      await _refreshTable();
                    }),
                  ),
                ),
              ),
              IconButton(
                tooltip: '应用筛选',
                onPressed: _busy
                    ? null
                    : () => unawaited(
                        _perform(() async {
                          _page = 0;
                          await _refreshTable();
                        }),
                      ),
                icon: const Icon(Icons.search),
              ),
              FilledButton.icon(
                onPressed: _busy ? null : () => unawaited(_insertRow()),
                icon: const Icon(Icons.add),
                label: const Text('添加行'),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                sortColumnIndex: _sortColumn == null
                    ? null
                    : page.columns.indexWhere(
                        (column) => column.name == _sortColumn,
                      ),
                sortAscending: !_descending,
                columns: [
                  for (var index = 0; index < page.columns.length; index++)
                    DataColumn(
                      label: Text(page.columns[index].name),
                      onSort: (columnIndex, ascending) => unawaited(
                        _perform(() async {
                          _sortColumn = page.columns[columnIndex].name;
                          _descending = !ascending;
                          _page = 0;
                          await _refreshTable();
                        }),
                      ),
                    ),
                  if (page.editable) const DataColumn(label: Text('操作')),
                ],
                rows: [
                  for (var row = 0; row < page.rows.length; row++)
                    DataRow(
                      cells: [
                        for (
                          var column = 0;
                          column < page.columns.length;
                          column++
                        )
                          DataCell(
                            ConstrainedBox(
                              constraints: const BoxConstraints(
                                minWidth: 96,
                                maxWidth: 220,
                              ),
                              child: Text(
                                page.rows[row][column] ?? 'NULL',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: page.rows[row][column] == null
                                    ? TextStyle(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.outline,
                                      )
                                    : null,
                              ),
                            ),
                            onTap:
                                page.editable &&
                                    !page.columns[column].generated &&
                                    !_busy
                                ? () => unawaited(_editCell(row, column))
                                : null,
                          ),
                        if (page.editable)
                          DataCell(
                            IconButton(
                              tooltip: '删除行',
                              onPressed: _busy
                                  ? null
                                  : () => unawaited(_deleteRow(row)),
                              icon: const Icon(Icons.delete_outline, size: 19),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                page.totalRows == 0
                    ? '暂无数据 · 0 / 0'
                    : '${_page * SqlWorkspaceRepository.pageSize + 1}'
                          '–${(_page * SqlWorkspaceRepository.pageSize + page.rows.length)}'
                          ' / ${page.totalRows}',
              ),
              IconButton(
                tooltip: '上一页',
                onPressed: _busy || _page == 0
                    ? null
                    : () => unawaited(
                        _perform(() async {
                          _page--;
                          await _refreshTable();
                        }),
                      ),
                icon: const Icon(Icons.chevron_left),
              ),
              IconButton(
                tooltip: '下一页',
                onPressed:
                    _busy ||
                        (_page + 1) * SqlWorkspaceRepository.pageSize >=
                            page.totalRows
                    ? null
                    : () => unawaited(
                        _perform(() async {
                          _page++;
                          await _refreshTable();
                        }),
                      ),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _schemaPanel() {
    final columns = _schemaColumns;
    if (columns == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_schemaError ?? '正在读取表结构', textAlign: TextAlign.center),
              if (_schemaError != null) ...[
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: _busy
                      ? null
                      : () => unawaited(_perform(_refreshSchema)),
                  icon: const Icon(Icons.refresh),
                  label: const Text('重试'),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: _busy ? null : () => unawaited(_addColumn()),
              icon: const Icon(Icons.add),
              label: const Text('添加列'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => unawaited(_renameTable(_table!)),
              icon: const Icon(Icons.drive_file_rename_outline),
              label: const Text('重命名表'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => unawaited(_exportTable(_table!)),
              icon: const Icon(Icons.file_download_outlined),
              label: const Text('导出 SQL'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('列名')),
              DataColumn(label: Text('类型')),
              DataColumn(label: Text('约束')),
              DataColumn(label: Text('操作')),
            ],
            rows: [
              for (final column in columns)
                DataRow(
                  cells: [
                    DataCell(SelectableText(column.name)),
                    DataCell(Text(column.type)),
                    DataCell(
                      Text(
                        [
                          if (column.primaryKey) 'PRIMARY KEY',
                          if (column.notNull) 'NOT NULL',
                          if (column.autoIncrement) 'AUTO_INCREMENT',
                          if (column.generated) 'GENERATED',
                        ].join(', '),
                      ),
                    ),
                    DataCell(
                      PopupMenuButton<String>(
                        tooltip: '列操作',
                        enabled: !_busy,
                        onSelected: (action) {
                          if (action == 'rename') {
                            unawaited(_renameColumn(column));
                          } else {
                            unawaited(_deleteColumn(column));
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'rename', child: Text('重命名列')),
                          PopupMenuItem(value: 'delete', child: Text('删除列')),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: Text('索引', style: Theme.of(context).textTheme.titleSmall),
            ),
            TextButton.icon(
              onPressed: _busy ? null : () => unawaited(_createIndex()),
              icon: const Icon(Icons.add),
              label: const Text('新建索引'),
            ),
          ],
        ),
        if (_indexes.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('暂无索引'),
          ),
        for (final index in _indexes)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(index.primary ? Icons.key : Icons.list_alt),
            title: Text(index.name),
            subtitle: Text(
              '${index.unique ? 'UNIQUE · ' : ''}'
              '${index.columns.join(', ')}',
            ),
            trailing: IconButton(
              tooltip: '删除索引',
              onPressed: _busy ? null : () => unawaited(_deleteIndex(index)),
              icon: const Icon(Icons.delete_outline),
            ),
          ),
      ],
    );
  }

  Widget _queryPanel() => ListView(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
    children: [
      TextField(
        controller: _queryController,
        minLines: 7,
        maxLines: 12,
        onChanged: (_) => setState(() {}),
        style: const TextStyle(fontFamily: 'monospace'),
        decoration: const InputDecoration(labelText: 'SQL 语句'),
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton.icon(
            onPressed:
                _busy ||
                    _queryLibraryLoading ||
                    _queryController.text.trim().isEmpty
                ? null
                : () => unawaited(_runQuery()),
            icon: const Icon(Icons.play_arrow),
            label: const Text('执行'),
          ),
          OutlinedButton.icon(
            onPressed:
                _busy ||
                    _queryLibraryLoading ||
                    _queryLibrary == null ||
                    _queryController.text.trim().isEmpty
                ? null
                : () => unawaited(_saveQuery()),
            icon: const Icon(Icons.bookmark_add_outlined),
            label: const Text('保存查询'),
          ),
          OutlinedButton.icon(
            onPressed: _busy || !_repository!.supportsSqlExport
                ? null
                : () => unawaited(_importSql()),
            icon: const Icon(Icons.file_upload_outlined),
            label: const Text('导入 SQL'),
          ),
        ],
      ),
      if (_queryResult case final result?) ...[
        const SizedBox(height: 16),
        if (result.truncated)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '脚本结果超过上限，部分结果未显示。',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (!result.success)
          Text(
            result.error ?? 'SQL 执行失败',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        for (var index = 0; index < result.results.length; index++) ...[
          if (result.results.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Text(
                '结果 ${index + 1}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
          if (result.results[index].success)
            _queryResultPanel(result.results[index]),
        ],
      ],
      if (_queryLibraryError case final error?) ...[
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Text(
                error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
            TextButton.icon(
              onPressed: _queryLibraryLoading
                  ? null
                  : () => unawaited(_loadQueryLibrary()),
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ],
      if (_queryLibrary case final library?) ...[
        const SizedBox(height: 16),
        _queryLibraryPanel(library),
      ],
    ],
  );

  Widget _queryResultPanel(SqlQueryResult result) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        result.columns.isEmpty
            ? '已执行 · 影响 ${result.affectedRows} 行'
            : '${result.rows.length} 行${result.truncated ? ' · 结果已截断' : ''}',
      ),
      if (result.columns.isNotEmpty)
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: [
              for (final name in result.columns) DataColumn(label: Text(name)),
            ],
            rows: [
              for (final row in result.rows)
                DataRow(
                  cells: [
                    for (final value in row)
                      DataCell(SelectableText(value ?? 'NULL')),
                  ],
                ),
            ],
          ),
        ),
    ],
  );

  Widget _queryLibraryPanel(SqlQueryLibrary library) {
    final saved = library.saved
        .where((query) => query.database == (_database ?? ''))
        .toList();
    final history = library.history
        .where((entry) => entry.database == (_database ?? ''))
        .toList();
    return Column(
      key: const ValueKey('query-library'),
      children: [
        ExpansionTile(
          key: PageStorageKey('saved-$_database'),
          title: const Text('已保存查询'),
          children: [
            if (saved.isEmpty)
              const Padding(padding: EdgeInsets.all(16), child: Text('暂无保存查询')),
            for (final query in saved)
              ListTile(
                dense: true,
                leading: const Icon(Icons.bookmark_outline),
                title: Text(query.name),
                subtitle: Text(
                  query.source,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: _busy ? null : () => _restoreQuery(query.source),
                trailing: IconButton(
                  tooltip: '删除保存的查询',
                  onPressed: _busy
                      ? null
                      : () => unawaited(_deleteSavedQuery(query)),
                  icon: const Icon(Icons.delete_outline),
                ),
              ),
          ],
        ),
        ExpansionTile(
          key: PageStorageKey('history-$_database'),
          title: Row(
            children: [
              const Expanded(child: Text('历史记录')),
              IconButton(
                tooltip: '清空历史记录',
                onPressed: _busy || library.history.isEmpty
                    ? null
                    : () => unawaited(_clearHistory()),
                icon: const Icon(Icons.delete_sweep_outlined),
              ),
            ],
          ),
          children: [
            if (history.isEmpty)
              const Padding(padding: EdgeInsets.all(16), child: Text('暂无历史记录')),
            for (final entry in history)
              ListTile(
                dense: true,
                leading: Icon(
                  entry.success
                      ? Icons.check_circle_outline
                      : Icons.error_outline,
                  color: entry.success
                      ? null
                      : Theme.of(context).colorScheme.error,
                ),
                title: Text(
                  entry.source,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${MaterialLocalizations.of(context).formatShortDate(entry.executedAt.toLocal())} '
                  '${TimeOfDay.fromDateTime(entry.executedAt.toLocal()).format(context)}',
                ),
                onTap: _busy ? null : () => _restoreQuery(entry.source),
              ),
          ],
        ),
      ],
    );
  }
}

enum _WorkbenchView { data, schema, sql }

class _IndexDraft {
  const _IndexDraft(this.name, this.columns, this.unique);

  final String name;
  final List<String> columns;
  final bool unique;
}

class _TableSpec {
  const _TableSpec(this.name, this.columns);

  final String name;
  final List<SqlColumnDraft> columns;
}

class _ColumnInput {
  final name = TextEditingController();
  String type = 'TEXT';
  bool notNull = false;
  bool primaryKey = false;

  SqlColumnDraft toDraft() => SqlColumnDraft(
    name: name.text.trim(),
    type: type,
    notNull: notNull,
    primaryKey: primaryKey,
  );

  void dispose() => name.dispose();
}

class _CellInput {
  _CellInput({String? initial, bool initialNull = false})
    : controller = TextEditingController(text: initial ?? ''),
      isNull = initialNull;

  final TextEditingController controller;
  bool isNull;

  void dispose() => controller.dispose();
}

class _EditedValue {
  const _EditedValue(this.value);

  final String? value;
}

class _DialogLifetime extends StatefulWidget {
  const _DialogLifetime({required this.onDispose, required this.child});

  final VoidCallback onDispose;
  final Widget child;

  @override
  State<_DialogLifetime> createState() => _DialogLifetimeState();
}

class _DialogLifetimeState extends State<_DialogLifetime> {
  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
