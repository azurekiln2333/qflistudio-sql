import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qfli_studio_core/i18n/studio_localizations.dart';
import 'package:qfli_studio_core/pages/tools_grid.dart' show commonTools;
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/widgets/tool_widgets.dart'
    show ToolsSectionHeading;

import 'mysql_sharing_card.dart';
import 'mysql_sharing_controller.dart';
import 'sql_database.dart';
import 'sql_query_library.dart';
import 'sql_tools_service.dart';

/// Product-owned body for the shared FunctionsTab's single toolbar.
Widget buildSqlToolsTab(ProjectStore store, VoidCallback onOpenTerminal) =>
    SqlToolsBody(store: store, onOpenTerminal: onOpenTerminal);

/// App-local dependencies for the actual product tools builder. Tests can keep
/// the home/profile routing intact while supplying controlled native engines.
class SqlToolsScope extends InheritedWidget {
  const SqlToolsScope({
    super.key,
    required this.createController,
    required super.child,
  });

  final SqlToolsController Function() createController;

  @override
  bool updateShouldNotify(SqlToolsScope oldWidget) => false;
}

/// SQL capabilities rendered directly inside the 功能 destination.
///
/// There is deliberately no intermediate "专用功能" landing page and no pushed
/// route for SQL work: the worksheet, query plan, schema/index inspection and
/// the offline text/value helpers are all usable in this tab. The shared
/// `commonTools` entries and the terminal callback keep their own routes.
class SqlToolsBody extends StatefulWidget {
  const SqlToolsBody({
    super.key,
    required this.store,
    required this.onOpenTerminal,
    this.controller,
    this.queryLibraryFactory,
    this.sharingController,
  });

  final ProjectStore store;
  final VoidCallback onOpenTerminal;

  /// Boundary seam for widget tests; production resolves the real engine.
  final SqlToolsController? controller;

  final MySqlSharingController? sharingController;

  /// Lets the tab reuse the app query library and its injected cache.
  final Future<SqlQueryLibrary> Function()? queryLibraryFactory;

  @override
  State<SqlToolsBody> createState() => _SqlToolsBodyState();
}

class _SqlToolsBodyState extends State<SqlToolsBody> {
  late final SqlToolsController _controller;
  late final bool _ownsController = widget.controller == null;

  final _sheetController = TextEditingController();
  final _identifierController = TextEditingController();
  final _valueController = TextEditingController();
  final _indexNameController = TextEditingController();
  final Set<String> _indexColumns = {};
  bool _indexUnique = false;
  bool _valueIsNull = false;
  String? _indexPreview;
  String? _formatPreview;
  (Object?, String?, String?)? _schemaIdentity;

  @override
  void initState() {
    super.initState();
    _controller =
        widget.controller ??
        context
            .getInheritedWidgetOfExactType<SqlToolsScope>()
            ?.createController() ??
        SqlToolsController(openLibrary: widget.queryLibraryFactory);
    _controller.addListener(_onControllerChanged);
    _sheetController.text = _controller.source;
    _sheetController.addListener(() {
      _controller.source = _sheetController.text;
      _formatPreview = null;
      // Rebuild for the statement counter and the enabled states only.
      if (mounted) setState(() {});
    });
    _identifierController.addListener(() => setState(() {}));
    _valueController.addListener(() => setState(() {}));
    _indexNameController.addListener(() => setState(() {}));
    unawaited(_controller.initialize());
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    if (_ownsController) _controller.dispose();
    _sheetController.dispose();
    _identifierController.dispose();
    _valueController.dispose();
    _indexNameController.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final identity = (
      _controller.target,
      _controller.database,
      _controller.table,
    );
    if (_schemaIdentity != identity) {
      _schemaIdentity = identity;
      _resetIndexBuilder();
      _formatPreview = null;
    }
    setState(() {});
  }

  Future<void> _copy(String text, String message) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _fillWorksheet(String text) {
    _sheetController.text = text;
    _controller.source = text;
    setState(() {});
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已填入工作表，请确认后再执行')));
  }

  void _resetIndexBuilder() {
    _indexColumns.clear();
    _indexNameController.clear();
    _indexUnique = false;
    _indexPreview = null;
  }

  void _format() {
    final controller = _sheetController;
    final value = controller.value;
    final formatted = formatSqlText(value.text, dialect: _controller.dialect);
    if (formatted.isEmpty || formatted == value.text) return;
    controller.value = TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = StudioLocalizations.of(context);
    return ListView(
      key: const PageStorageKey('sql-tools-scroll'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        _heading('快捷入口', Icons.widgets_outlined),
        ListTile(
          leading: const Icon(Icons.terminal),
          title: const Text('终端'),
          subtitle: const Text('在本机沙盒中运行命令'),
          trailing: const Icon(Icons.chevron_right),
          onTap: widget.onOpenTerminal,
        ),
        _heading(l10n.sqlTools, Icons.play_circle_outline),
        _worksheetCard(),
        _heading('查询计划', Icons.account_tree_outlined),
        _planCard(),
        _heading('结构与索引', Icons.schema_outlined),
        _schemaCard(),
        _heading('文本与值工具', Icons.text_fields_outlined),
        _textToolsCard(),
        MySqlSharingCard(controller: widget.sharingController),
        _heading('通用', Icons.build_outlined),
        for (final tool in commonTools)
          ListTile(
            leading: Icon(tool.icon),
            title: Text(tool.title),
            subtitle: Text(tool.description),
            trailing: const Icon(Icons.chevron_right),
            onTap:
                tool.onTap ??
                () => Navigator.of(
                  context,
                ).push(MaterialPageRoute<void>(builder: tool.builder!)),
          ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 24, 16, 0),
          child: Text(
            'SQL 工具只连接本机数据库引擎，所有离线文本计算都在本机完成。'
            '每次执行使用独立连接：需要事务时，请在一次执行中写 BEGIN…COMMIT。',
          ),
        ),
      ],
    );
  }

  Widget _heading(String title, IconData icon) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
    child: ToolsSectionHeading(icon: icon, title: title),
  );

  Widget _card({required String key, required List<Widget> children}) => Card(
    key: ValueKey(key),
    margin: const EdgeInsets.symmetric(horizontal: 4),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    ),
  );

  Widget _engineContext() {
    final controller = _controller;
    final busy = controller.busy || controller.initializing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '引擎：${controller.engineLabel}'
          '${controller.database == null ? '' : ' · 数据库：${controller.database}'}',
          key: const ValueKey('sql-tools-engine'),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        Text(
          controller.target == null
              ? '尚未连接本地数据库引擎'
              : controller.dialect == SqlDialect.mysql
              ? '脚本按本机 MySQL 方言执行'
              : '脚本按 SQLite 方言执行，文件位于应用数据目录',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (controller.contextError case final error?)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    '数据库引擎不可用：$error',
                    key: const ValueKey('sql-tools-context-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () => unawaited(controller.initialize()),
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                key: const ValueKey('sql-tools-database'),
                isExpanded: true,
                initialValue: controller.databases.contains(controller.database)
                    ? controller.database
                    : null,
                decoration: const InputDecoration(
                  labelText: '数据库',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final name in controller.databases)
                    DropdownMenuItem<String>(value: name, child: Text(name)),
                ],
                onChanged: busy || controller.databases.isEmpty
                    ? null
                    : (value) {
                        _resetIndexBuilder();
                        unawaited(controller.selectDatabase(value));
                      },
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: '刷新数据库结构',
              onPressed: busy ? null : () => unawaited(controller.refresh()),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
      ],
    );
  }

  Widget _worksheetCard() {
    final controller = _controller;
    final busy = controller.busy || controller.initializing;
    String statementCount;
    try {
      statementCount =
          '可执行语句：${countSqlStatements(controller.source, dialect: controller.dialect)} 条'
          '${controller.source.trim().isEmpty ? '（工作表为空）' : ''}';
    } on SqlToolsException {
      statementCount = '语句数量暂无法可靠统计；完整脚本仍可交由引擎执行。';
    }
    return _card(
      key: 'sql-tools-worksheet-card',
      children: [
        _engineContext(),
        if (controller.busy || controller.initializing)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('sql-tools-worksheet'),
          controller: _sheetController,
          minLines: 6,
          maxLines: null,
          keyboardType: TextInputType.multiline,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          decoration: const InputDecoration(
            labelText: 'SQL 脚本',
            hintText: 'SELECT * FROM demo;',
            border: OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          statementCount,
          key: const ValueKey('sql-tools-statement-count'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              key: const ValueKey('sql-tools-run'),
              onPressed: busy || !controller.canExecute
                  ? null
                  : () => unawaited(controller.runScript()),
              icon: const Icon(Icons.play_arrow),
              label: const Text('执行'),
            ),
            OutlinedButton.icon(
              key: const ValueKey('sql-tools-explain'),
              onPressed: busy || !controller.canExecute
                  ? null
                  : () => unawaited(controller.explain()),
              icon: const Icon(Icons.account_tree_outlined),
              label: const Text('查询计划'),
            ),
            OutlinedButton.icon(
              key: const ValueKey('sql-tools-format'),
              onPressed: _controller.source.trim().isEmpty ? null : _format,
              icon: const Icon(Icons.format_align_left),
              label: const Text('整理语句开头'),
            ),
            TextButton.icon(
              key: const ValueKey('sql-tools-clear'),
              onPressed: () {
                _sheetController.clear();
                setState(() {});
              },
              icon: const Icon(Icons.clear),
              label: const Text('清空'),
            ),
          ],
        ),
        if (controller.executionError case final error?)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              error,
              key: const ValueKey('sql-tools-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (controller.script case final script?) ...[
          const SizedBox(height: 12),
          _scriptPanel(script),
        ],
        if (controller.libraryError case final error?)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '查询记录保存失败：$error（本次结果仍有效）',
              key: const ValueKey('sql-tools-library-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (controller.library case final library?
            when library.history.isNotEmpty) ...[
          const SizedBox(height: 12),
          ExpansionTile(
            key: const PageStorageKey('sql-tools-history'),
            tilePadding: EdgeInsets.zero,
            title: Text('最近执行（${library.history.length}）'),
            children: [
              for (final entry in library.history.take(5))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    entry.success
                        ? Icons.check_circle_outline
                        : Icons.error_outline,
                  ),
                  title: Text(
                    entry.source,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(entry.database),
                  onTap: controller.busy
                      ? null
                      : () {
                          _sheetController.text = entry.source;
                          controller.source = entry.source;
                          setState(() {});
                        },
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _scriptPanel(SqlScriptResult script) {
    final results = script.results;
    final failed = !script.success;
    return Column(
      key: const ValueKey('sql-tools-results'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (script.truncated)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '脚本结果超过上限，部分结果未返回。',
              key: const ValueKey('sql-tools-truncated'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (!script.available)
          Text(
            'SQL 引擎不可用（退出码 ${script.exitCode}）：${script.error ?? '未知原因'}',
            key: const ValueKey('sql-tools-unavailable'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (results.isEmpty && !failed) const Text('脚本已执行，没有结果集。'),
        for (var index = 0; index < results.length; index++) ...[
          if (results.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              child: Text(
                '结果 ${index + 1} / ${results.length}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
          _resultPanel(results[index]),
        ],
        if (failed)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _formatFailure(script.summary),
              key: const ValueKey('sql-tools-script-failure'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (failed && results.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '脚本未全部完成，前面的语句可能已经生效。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }

  String _formatFailure(SqlQueryResult result) {
    final parts = <String>[
      if (!result.available) '引擎不可用（退出码 ${result.exitCode}）',
      if (result.sqlState case final state?) 'SQLSTATE $state',
      result.error ?? 'SQL 执行失败',
    ];
    return parts.join(' · ');
  }

  /// Renders one captured result. The workbench keeps its own private renderer;
  /// this product-owned copy exists because both surfaces show real results.
  Widget _resultPanel(SqlQueryResult result) {
    if (!result.success) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          _formatFailure(result),
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          result.columns.isEmpty
              ? '已执行 · 影响 ${result.affectedRows} 行'
              : '${result.rows.length} 行'
                    '${result.truncated ? ' · 结果已截断，未显示的行不会被导出' : ''}',
        ),
        if (result.columns.isNotEmpty)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: [
                for (final name in result.columns)
                  DataColumn(label: Text(name)),
              ],
              rows: [
                for (final row in result.rows)
                  DataRow(
                    cells: [
                      for (final value in row)
                        DataCell(
                          SelectableText(
                            value ?? 'NULL',
                            style: value == null
                                ? const TextStyle(fontStyle: FontStyle.italic)
                                : null,
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        if (result.columns.isNotEmpty && result.rows.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('sql-tools-copy-csv'),
              onPressed: () => unawaited(
                _copy(
                  sqlResultToCsv(result.columns, result.rows),
                  result.truncated ? '已复制已显示的行（结果被截断）' : '已复制结果 CSV',
                ),
              ),
              icon: const Icon(Icons.copy_all_outlined),
              label: const Text('复制 CSV'),
            ),
          ),
      ],
    );
  }

  Widget _planCard() {
    final plan = _controller.plan;
    return _card(
      key: 'sql-tools-plan-card',
      children: [
        const Text('只解析执行计划，不运行工作表里的原语句；请在工作表中填写一条查询后点“查询计划”。'),
        if (plan == null)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('还没有执行计划结果。'),
          )
        else ...[
          const SizedBox(height: 8),
          Text(
            '引擎：${plan.engineLabel}',
            key: const ValueKey('sql-tools-plan-engine'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          SelectableText(
            plan.planSql,
            key: const ValueKey('sql-tools-plan-sql'),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
          const SizedBox(height: 8),
          if (!plan.result.success)
            Text(
              _formatFailure(plan.result),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            )
          else if (plan.result.columns.isEmpty)
            const Text('引擎未返回执行计划行。')
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                key: const ValueKey('sql-tools-plan-table'),
                columns: [
                  for (final name in plan.result.columns)
                    DataColumn(label: Text(name)),
                ],
                rows: [
                  for (final row in plan.result.rows)
                    DataRow(
                      cells: [
                        for (final value in row)
                          DataCell(
                            SelectableText(
                              value ?? 'NULL',
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                              ),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
        ],
      ],
    );
  }

  Widget _schemaCard() {
    final controller = _controller;
    final busy = controller.busy || controller.initializing;
    final columns = controller.columns;
    final indexes = controller.indexes;
    final hasTable = controller.table != null;
    return _card(
      key: 'sql-tools-schema-card',
      children: [
        DropdownButtonFormField<String>(
          key: const ValueKey('sql-tools-table'),
          isExpanded: true,
          initialValue: controller.tables.contains(controller.table)
              ? controller.table
              : null,
          decoration: const InputDecoration(
            labelText: '数据表',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          items: [
            for (final name in controller.tables)
              DropdownMenuItem<String>(value: name, child: Text(name)),
          ],
          onChanged: busy || controller.tables.isEmpty
              ? null
              : (value) {
                  _resetIndexBuilder();
                  unawaited(controller.selectTable(value));
                },
        ),
        if (!hasTable)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('当前数据库没有可查看的数据表。'),
          ),
        if (controller.schemaError case final error?)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '结构读取失败：$error',
              key: const ValueKey('sql-tools-schema-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (columns.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            '列（${columns.length}）',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              key: const ValueKey('sql-tools-columns'),
              columns: const [
                DataColumn(label: Text('列')),
                DataColumn(label: Text('类型')),
                DataColumn(label: Text('可空')),
                DataColumn(label: Text('主键')),
                DataColumn(label: Text('标记')),
              ],
              rows: [
                for (final column in columns)
                  DataRow(
                    cells: [
                      DataCell(SelectableText(column.name)),
                      DataCell(SelectableText(column.type)),
                      DataCell(Text(column.notNull ? '否' : '是')),
                      DataCell(Text(column.primaryKey ? '是' : '否')),
                      DataCell(
                        Text(
                          [
                            if (column.generated) '生成列',
                            if (column.autoIncrement) '自增',
                          ].join(' '),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                '索引（${indexes.length}）',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            TextButton.icon(
              key: const ValueKey('sql-tools-refresh-schema'),
              onPressed: busy || !hasTable
                  ? null
                  : () => unawaited(controller.refresh()),
              icon: const Icon(Icons.refresh),
              label: const Text('刷新结构'),
            ),
          ],
        ),
        if (controller.schemaNote case final note?)
          Text(
            note,
            key: const ValueKey('sql-tools-index-note'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        for (final index in indexes)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              index.primary ? Icons.key : Icons.linear_scale_outlined,
            ),
            title: Text(index.name),
            subtitle: Text(
              '${index.columns.join(', ')}'
              '${index.unique ? ' · 唯一' : ''}'
              '${index.primary ? ' · 主键' : ''}'
              '${index is SqliteToolIndex && index.automatic ? ' · 约束自动索引' : ''}'
              '${index is SqliteToolIndex && index.partial ? ' · 部分索引' : ''}',
            ),
            trailing: controller.supportsSchemaTools && !index.primary
                ? TextButton(
                    onPressed: busy
                        ? null
                        : () {
                            try {
                              final sql = controller.buildDropIndexSql(
                                index.name,
                              );
                              if (sql == null) return;
                              setState(() => _indexPreview = sql);
                            } on SqlToolsException catch (error) {
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(error.message)),
                              );
                            }
                          },
                    child: const Text('生成语句'),
                  )
                : null,
          ),
        if (hasTable && controller.dialect == SqlDialect.sqlite)
          const Text(
            'SQLite 支持查看索引；索引变更请在工作表中编写并确认 SQL。',
            key: ValueKey('sql-tools-index-generator-note'),
          ),
        if (controller.supportsSchemaTools && columns.isNotEmpty) ...[
          const Divider(height: 24),
          Text('索引生成', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('sql-tools-index-name'),
            controller: _indexNameController,
            decoration: const InputDecoration(
              labelText: '索引名称',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final column in columns)
                FilterChip(
                  label: Text(column.name),
                  selected: _indexColumns.contains(column.name),
                  onSelected: busy
                      ? null
                      : (selected) => setState(() {
                          if (selected) {
                            _indexColumns.add(column.name);
                          } else {
                            _indexColumns.remove(column.name);
                          }
                        }),
                ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('唯一索引'),
            value: _indexUnique,
            onChanged: busy
                ? null
                : (value) => setState(() => _indexUnique = value),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                key: const ValueKey('sql-tools-build-create-index'),
                onPressed: busy
                    ? null
                    : () {
                        try {
                          final sql = controller.buildCreateIndexSql(
                            name: _indexNameController.text,
                            columns: [
                              for (final column in columns)
                                if (_indexColumns.contains(column.name))
                                  column.name,
                            ],
                            unique: _indexUnique,
                          );
                          if (sql == null) return;
                          setState(() => _indexPreview = sql);
                        } on SqlToolsException catch (error) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(error.message)),
                          );
                        }
                      },
                icon: const Icon(Icons.linear_scale_outlined),
                label: const Text('生成创建索引语句'),
              ),
            ],
          ),
        ],
        if (_indexPreview case final preview?) ...[
          const SizedBox(height: 12),
          Container(
            key: const ValueKey('sql-tools-index-preview'),
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              preview,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
          const Text('生成的语句不会自动执行；请确认后填入工作表并点“执行”。'),
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: () => _fillWorksheet(preview),
                icon: const Icon(Icons.edit_note),
                label: const Text('填入工作表'),
              ),
              TextButton.icon(
                onPressed: () => unawaited(_copy(preview, '已复制语句')),
                icon: const Icon(Icons.copy_outlined),
                label: const Text('复制'),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _textToolsCard() {
    final controller = _controller;
    String identifierOutput;
    String valueOutput;
    try {
      identifierOutput = _identifierController.text.isEmpty
          ? '输入标识符后显示当前的引用写法'
          : controller.identifierHelp(_identifierController.text);
    } on SqlToolsException catch (error) {
      identifierOutput = error.message;
    }
    try {
      valueOutput = _valueIsNull
          ? controller.valueHelp(null)
          : controller.valueHelp(_valueController.text);
    } on SqlToolsException catch (error) {
      valueOutput = error.message;
    }
    return _card(
      key: 'sql-tools-text-card',
      children: [
        Text(
          '标识符引用（${controller.dialect == SqlDialect.mysql ? 'MySQL 反引号' : 'SQLite 双引号'}）',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey('sql-tools-identifier'),
          controller: _identifierController,
          decoration: const InputDecoration(
            labelText: '表名 / 列名',
            isDense: true,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 6),
        SelectableText(
          identifierOutput,
          key: const ValueKey('sql-tools-identifier-output'),
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        ),
        const Divider(height: 24),
        Text('字符串与 NULL', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey('sql-tools-value'),
          controller: _valueController,
          enabled: !_valueIsNull,
          decoration: const InputDecoration(
            labelText: '值',
            isDense: true,
            border: OutlineInputBorder(),
          ),
        ),
        SwitchListTile(
          key: const ValueKey('sql-tools-value-null'),
          contentPadding: EdgeInsets.zero,
          title: const Text('按 SQL NULL 处理'),
          subtitle: const Text('NULL 与空字符串不是同一个值'),
          value: _valueIsNull,
          onChanged: (value) => setState(() => _valueIsNull = value),
        ),
        SelectableText(
          valueOutput,
          key: const ValueKey('sql-tools-value-output'),
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        ),
        const Divider(height: 24),
        Text('格式化', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        const Text(
          '只统一已知 SQL 关键字的大小写；字符串、引号标识符和注释原样保留，'
          '无法识别的写法不会被改写。',
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('sql-tools-format-preview'),
              onPressed: controller.source.trim().isEmpty
                  ? null
                  : () => setState(
                      () => _formatPreview = formatSqlText(
                        controller.source,
                        dialect: controller.dialect,
                      ),
                    ),
              icon: const Icon(Icons.description_outlined),
              label: const Text('预览格式化结果'),
            ),
          ],
        ),
        if (_formatPreview case final preview?
            when controller.source.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            key: const ValueKey('sql-tools-format-preview-output'),
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              preview,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ],
      ],
    );
  }
}
