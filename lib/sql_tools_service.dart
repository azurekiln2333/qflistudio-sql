import 'dart:async';

import 'package:flutter/foundation.dart';
import 'sql_database.dart';
import 'sql_engine_preference.dart';
import 'sql_execution_context.dart';
import 'sql_query_library.dart';
import 'sql_syntax_validator.dart' as lex;
import 'sql_syntax_validator.dart' show SqlDialect;
import 'sql_workspace_repository.dart';

/// The tools share the editor's dialect-aware scanner, so MySQL `-- ` rules,
/// SQLite backslash literals and delimiters inside comments mean the same thing
/// in the worksheet, the query-plan guard and the editor diagnostics.
export 'sql_syntax_validator.dart' show SqlDialect;

/// A user-facing SQL tool failure with an actionable message.
class SqlToolsException implements Exception {
  const SqlToolsException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Splits SQL text into top-level statements using the shared lexical scanner.
///
/// A statement boundary is only a semicolon outside literals, comments,
/// parentheses and routine bodies, so `';'`, `-- ;` and trigger bodies are not
/// split. This is a lexical split, not a grammar parser.
List<String> splitSqlStatements(
  String source, {
  SqlDialect dialect = SqlDialect.sqlite,
}) {
  final analysis = lex.SqlSyntaxValidator.analyze(source, dialect: dialect);
  if (analysis.truncated ||
      analysis.issues.any(
        (issue) => issue.code == 'statement-boundary-unsupported',
      )) {
    throw const SqlToolsException('当前脚本的语句边界无法可靠统计');
  }
  return [
    for (final statement in analysis.statements)
      source.substring(statement.start, statement.end),
  ];
}

/// Number of executable statements, ignoring trailing separators and comments.
int countSqlStatements(
  String source, {
  SqlDialect dialect = SqlDialect.sqlite,
}) => splitSqlStatements(source, dialect: dialect).length;

/// Command words normalized only at a confirmed lexical statement start.
///
/// Clause/type/expression words are intentionally excluded: in an identifier or
/// alias position their spelling can affect MySQL lookup or result headers.
const Set<String> sqlFormatKeywords = {
  'select',
  'insert',
  'update',
  'delete',
  'create',
  'drop',
  'alter',
  'begin',
  'commit',
  'rollback',
  'with',
  'pragma',
  'explain',
  'values',
  'replace',
};

/// Normalizes recognized command starts and trims surrounding whitespace.
///
/// Statement bodies are copied verbatim. Word spelling alone cannot distinguish
/// a keyword from an identifier/alias, and even changing an unaliased expression
/// changes SQLite result headers. This is deliberately not a grammar formatter.
/// Incomplete or ambiguous lexical analysis preserves the trimmed source.
/// Literal/comment/identifier text and separators are never rewritten or added.
String formatSqlText(String source, {SqlDialect dialect = SqlDialect.sqlite}) {
  if (source.trim().isEmpty) return '';
  final analysis = lex.SqlSyntaxValidator.analyze(source, dialect: dialect);
  if (analysis.truncated || analysis.issues.isNotEmpty) return source.trim();
  final commandStarts = {
    for (final statement in analysis.statements) statement.start,
  };
  final output = StringBuffer();
  var cursor = 0;
  for (final token in analysis.tokens) {
    if (token.start < cursor) continue;
    if (token.start > cursor) {
      output.write(source.substring(cursor, token.start));
    }
    output.write(
      token.kind == lex.SqlTokenKind.word &&
              commandStarts.contains(token.start) &&
              sqlFormatKeywords.contains(token.text.toLowerCase())
          ? token.text.toUpperCase()
          : token.text,
    );
    cursor = token.end;
  }
  if (cursor < source.length) output.write(source.substring(cursor));
  return output.toString().trim();
}

/// Quotes an identifier for the given dialect.
String quoteSqlIdentifier(String name, SqlDialect dialect) {
  if (name.isEmpty) throw const SqlToolsException('标识符不能为空');
  final trimmed = name.trim();
  if (trimmed != name) {
    throw const SqlToolsException('标识符首尾不能有空白');
  }
  if (name.contains('\u0000')) {
    throw const SqlToolsException('标识符不能包含 NUL 字符');
  }
  if (dialect == SqlDialect.mysql) {
    if (name.contains('`')) {
      throw const SqlToolsException('MySQL 标识符不能包含反引号');
    }
    return '`$name`';
  }
  return '"${name.replaceAll('"', '""')}"';
}

/// Quotes a value as a SQL string literal.
///
/// MySQL also honours backslash escapes, so both the quote and the backslash
/// are doubled there. NULL is not a string: use [sqlNullLiteral].
String quoteSqlString(String value, SqlDialect dialect) {
  if (value.contains('\u0000')) {
    throw const SqlToolsException('字符串不能包含 NUL 字符');
  }
  final escaped = dialect == SqlDialect.mysql
      ? value.replaceAll(r'\', r'\\').replaceAll("'", "''")
      : value.replaceAll("'", "''");
  return "'$escaped'";
}

/// The literal that means SQL NULL, never an empty string.
const String sqlNullLiteral = 'NULL';

/// Describes a captured cell so NULL and the empty string stay distinct.
String describeSqlCell(String? value) {
  if (value == null) return 'SQL NULL';
  if (value.isEmpty) return "空字符串 ''";
  return '${value.runes.length} 个字符';
}

/// Produces RFC 4180 CSV where an unquoted empty field is SQL NULL and a
/// quoted empty field (`""`) is an empty string.
String sqlResultToCsv(List<String> columns, List<List<String?>> rows) {
  String field(String? value) {
    if (value == null) return '';
    final text = value;
    if (text.isNotEmpty &&
        !text.contains(RegExp(r'[",\r\n]')) &&
        text.trim() == text) {
      return text;
    }
    return '"${text.replaceAll('"', '""')}"';
  }

  final lines = <String>[
    columns.map(field).join(','),
    for (final row in rows)
      [for (var i = 0; i < columns.length; i++) field(row[i])].join(','),
  ];
  return lines.join('\r\n');
}

/// A single statement the plan tool is willing to explain.
///
/// Plain EXPLAIN describes a plan without running the statement. Rejected forms
/// are the ones that could execute or mutate (`EXPLAIN ANALYZE`, `ANALYZE`,
/// MySQL `ANALYZE TABLE`, file-writing `INTO OUTFILE`/`INTO DUMPFILE`) plus
/// anything the plan tool cannot express unambiguously (multiple statements,
/// empty input). Statement boundaries come from the shared dialect-aware
/// scanner, so a `;` inside a literal or a MySQL `SELECT 1--2` is not mistaken
/// for a separator or a comment.
String buildSqlPlanRequest(String source, SqlDialect dialect) {
  final analysis = lex.SqlSyntaxValidator.analyze(source, dialect: dialect);
  if (analysis.truncated || analysis.issues.isNotEmpty) {
    throw const SqlToolsException('SQL 未通过完整词法检查，请先修正语句或缩短脚本');
  }
  // MySQL executes version comments. A trivia-only lexer cannot prove their
  // contents are one plain query, so never forward them to the plan engine.
  if (dialect == SqlDialect.mysql &&
      analysis.tokens.any(
        (token) =>
            token.kind == lex.SqlTokenKind.blockComment &&
            (token.text.startsWith('/*!') ||
                token.text.toUpperCase().startsWith('/*M!')),
      )) {
    throw const SqlToolsException('执行计划不接受可执行版本注释，请展开为普通查询');
  }
  final statements = analysis.statements;
  if (statements.isEmpty) {
    throw const SqlToolsException('请输入要解析执行计划的一条 SQL 语句');
  }
  if (statements.length > 1) {
    throw const SqlToolsException('执行计划一次只接受一条语句，请先拆分脚本');
  }
  final statement = statements.single;
  final text = source.substring(statement.start, statement.end).trim();
  final tokens = [
    for (final token in analysis.tokens)
      if (!token.isTrivia &&
          token.start >= statement.start &&
          token.end <= statement.end)
        token,
  ];
  final first = tokens.isEmpty || !tokens.first.isWord
      ? ''
      : tokens.first.keyword;
  if (first == 'EXPLAIN') {
    throw const SqlToolsException('EXPLAIN ANALYZE 会真实执行语句，请直接在工作表中手动运行');
  }
  if (first == 'ANALYZE') {
    throw const SqlToolsException('ANALYZE 会写入统计信息，执行计划工具不会运行它');
  }
  const supported = {'SELECT', 'WITH', 'VALUES', 'TABLE'};
  if (!supported.contains(first)) {
    throw SqlToolsException(
      '执行计划工具只解析查询语句（SELECT / WITH / VALUES / TABLE），'
      '当前以 ${first.isEmpty ? '未知记号' : first} 开头',
    );
  }
  var depth = 0;
  var closedCte = false;
  String? withQuery;
  for (var index = 0; index < tokens.length; index++) {
    final token = tokens[index];
    if (token.text == '(') depth++;
    if (token.text == ')') {
      depth--;
      if (depth == 0) closedCte = true;
    }
    if (!token.isWord) continue;
    if (token.keyword == 'INTO' &&
        index + 1 < tokens.length &&
        const {'OUTFILE', 'DUMPFILE'}.contains(tokens[index + 1].keyword)) {
      throw const SqlToolsException('该语句会写入服务器文件，执行计划工具不会解析它');
    }
    if (first == 'WITH' &&
        closedCte &&
        depth == 0 &&
        withQuery == null &&
        const {
          'SELECT',
          'VALUES',
          'TABLE',
          'INSERT',
          'UPDATE',
          'DELETE',
          'REPLACE',
        }.contains(token.keyword)) {
      withQuery = token.keyword;
    }
  }
  if (first == 'WITH' &&
      !const {'SELECT', 'VALUES', 'TABLE'}.contains(withQuery)) {
    throw const SqlToolsException('WITH 执行计划只接受以查询结尾的单条语句');
  }
  if (dialect == SqlDialect.mysql) {
    if (first == 'VALUES' || first == 'TABLE') {
      throw SqlToolsException('本机 MySQL 不支持 $first 形式的 EXPLAIN，请改用 SELECT');
    }
    return 'EXPLAIN $text';
  }
  return 'EXPLAIN QUERY PLAN $text';
}

/// Opens the app-owned local execution context for the retained Tools tab.
///
/// Engine resolution belongs to `SqlExecutionContext`/`SqlEnginePreference`: the
/// tools never invent their own fallback (a selected engine is never silently
/// replaced) and never open cloud. Both optional seams exist for tests.
Future<SqlExecutionContext> openSqlToolsTarget({
  Future<SqlWorkspaceRepository> Function()? openSqlite,
  Future<SqlWorkspaceRepository> Function()? openMysql,
}) =>
    SqlExecutionContext.openLocal(openSqlite: openSqlite, openMysql: openMysql);

/// The dialect used by the text/plan guards for a resolved local engine.
SqlDialect dialectOf(SqlEngineKind engine) => switch (engine) {
  SqlEngineKind.localMysql => SqlDialect.mysql,
  _ => SqlDialect.sqlite,
};

/// A requested execution plan and its raw engine rows.
class SqlPlanOutcome {
  const SqlPlanOutcome({
    required this.engineLabel,
    required this.planSql,
    required this.result,
  });

  final String engineLabel;
  final String planSql;
  final SqlQueryResult result;
}

/// SQLite index metadata that the common repository model cannot represent.
/// Names and constraint origin are reported by SQLite, never synthesized.
class SqliteToolIndex extends SqlIndex {
  const SqliteToolIndex({
    required super.name,
    required super.columns,
    required super.unique,
    required this.origin,
    required this.partial,
  }) : super(primary: origin == 'pk');

  final String origin;
  final bool partial;

  bool get automatic => origin == 'u' || origin == 'pk';
}

/// Retained state and behavior of the SQL section of the Tools tab.
///
/// One controller owns the resolved engine context, the worksheet text, the
/// ordered results and the schema/index caches, so switching destinations keeps
/// them and no second engine API is introduced.
class SqlToolsController extends ChangeNotifier {
  SqlToolsController({
    Future<SqlExecutionContext> Function()? openTarget,
    Future<SqlQueryLibrary> Function()? openLibrary,
    this.libraryEnabled = true,
    this.watchPreference = true,
    Listenable? engineChanges,
  }) : _openTargetProvider = openTarget,
       _engineChanges = engineChanges ?? SqlEnginePreference.changes,
       _openLibrary = openLibrary ?? SqlQueryLibrary.openDefault {
    if (watchPreference) _engineChanges.addListener(_onEngineChanged);
  }

  final Future<SqlExecutionContext> Function()? _openTargetProvider;
  final Future<SqlQueryLibrary> Function() _openLibrary;
  final Listenable _engineChanges;
  final bool libraryEnabled;

  /// False in tests that drive `initialize()` explicitly.
  final bool watchPreference;

  SqlExecutionContext? _target;
  bool _initializing = false;
  bool _busy = false;
  bool _disposed = false;
  String? _contextError;

  /// Bumped for every context change so a result from the previous engine can
  /// never be published into the new context.
  int _epoch = 0;
  bool _reloadPending = false;

  /// Retained SQL text. The widget owns the TextEditingController and mirrors
  /// every change here so a distant tab switch does not lose unsaved input.
  String source = '';
  List<String> _databases = const [];
  String? _database;
  List<String> _tables = const [];
  String? _table;
  List<SqlColumn> _columns = const [];
  List<SqlIndex> _indexes = const [];
  String? _schemaError;
  String? _schemaNote;
  SqlScriptResult? _script;
  SqlPlanOutcome? _plan;
  String? _executionError;
  SqlQueryLibrary? _library;
  String? _libraryError;

  SqlExecutionContext? get target => _target;
  bool get initializing => _initializing;
  bool get busy => _busy;
  String? get contextError => _contextError;
  String get engineLabel => _target?.engineLabel ?? '未连接';
  SqlDialect get dialect => dialectOf(
    _target?.engine ??
        SqlEnginePreference.resolveLocalEngine(SqlEnginePreference.current),
  );

  /// Reads the capability through the shared context, which refuses a stale
  /// context (another surface switched the engine).
  bool get supportsSchemaTools {
    final context = _target;
    if (context == null || !context.isCurrent) return false;
    return context.engine == SqlEngineKind.localMysql &&
        context.repository.supportsSchemaTools;
  }

  /// True when a worksheet action can reach a real local database.
  bool get canExecute =>
      _target != null &&
      _target!.isCurrent &&
      _database != null &&
      !_busy &&
      !_initializing;

  List<String> get databases => _databases;
  String? get database => _database;
  List<String> get tables => _tables;
  String? get table => _table;
  List<SqlColumn> get columns => _columns;
  List<SqlIndex> get indexes => _indexes;
  String? get schemaError => _schemaError;
  String? get schemaNote => _schemaNote;
  SqlScriptResult? get script => _script;
  SqlPlanOutcome? get plan => _plan;
  String? get executionError => _executionError;
  SqlQueryLibrary? get library => _library;
  String? get libraryError => _libraryError;

  /// Engine preference changed elsewhere. Drop the stale engine context and its
  /// results immediately, keep the user's SQL text and the query library, and
  /// reconnect.
  void _onEngineChanged() {
    if (_disposed) return;
    _epoch++;
    _reloadPending = true;
    _clearContext();
    _notify();
    _reconnectWhenIdle();
  }

  void _clearContext() {
    _target = null;
    _databases = const [];
    _database = null;
    _tables = const [];
    _table = null;
    _columns = const [];
    _indexes = const [];
    _schemaError = null;
    _schemaNote = null;
    _script = null;
    _plan = null;
    _executionError = null;
    _contextError = null;
  }

  bool _valid(int epoch, [SqlExecutionContext? context]) =>
      !_disposed &&
      epoch == _epoch &&
      (context == null || (identical(context, _target) && context.isCurrent));

  void _reconnectWhenIdle() {
    if (_reloadPending && !_busy && !_initializing && !_disposed) {
      unawaited(initialize());
    }
  }

  Future<SqlExecutionContext> _openTarget() async =>
      await (_openTargetProvider?.call() ?? openSqlToolsTarget());

  /// Opens the local engine and lists its databases. Errors stay visible.
  Future<void> initialize() async {
    if (_initializing || _busy || _disposed) return;
    final epoch = ++_epoch;
    _reloadPending = false;
    _initializing = true;
    _clearContext();
    _notify();
    try {
      final target = await _openTarget();
      if (!_valid(epoch)) return;
      target.requireCurrent();
      _target = target;
      final databases = await target.repository.listDatabases();
      if (!_valid(epoch, target)) return;
      _databases = List.unmodifiable(databases);
      _database = _databases.isEmpty ? null : _databases.first;
      await _loadTables(epoch, target);
      if (!_valid(epoch, target)) return;
      await _loadSchema(epoch, target);
      if (!_valid(epoch, target)) return;
      await _loadLibrary(epoch, target);
      if (!_valid(epoch, target)) return;
    } catch (error) {
      if (!_valid(epoch)) return;
      _clearContext();
      _contextError = _message(error);
    } finally {
      // Preference changes invalidate publication, never the ownership of an
      // in-flight operation. Only its own finally block releases this lock.
      _initializing = false;
      _notify();
      _reconnectWhenIdle();
    }
  }

  Future<void> _loadLibrary(int epoch, SqlExecutionContext context) async {
    if (!libraryEnabled || _library != null || !_valid(epoch, context)) return;
    try {
      final library = await _openLibrary();
      if (!_valid(epoch, context)) return;
      _library = library;
      _libraryError = null;
    } catch (error) {
      if (!_valid(epoch, context)) return;
      _library = null;
      _libraryError = _message(error);
    }
  }

  Future<void> _loadTables(int epoch, SqlExecutionContext context) async {
    if (!_valid(epoch, context)) return;
    final database = _database;
    if (database == null) {
      _tables = const [];
      _table = null;
      return;
    }
    final tables = await context.repository.listTables(database);
    if (!_valid(epoch, context) || database != _database) return;
    _tables = List.unmodifiable(tables);
    if (!_tables.contains(_table)) {
      _table = _tables.isEmpty ? null : _tables.first;
    }
  }

  Future<void> selectDatabase(String? database) async {
    if (_busy || _initializing || database == _database) return;
    if (database != null && !_databases.contains(database)) return;
    await _run((epoch, context) async {
      _database = database;
      _table = null;
      _clearSchema();
      _script = null;
      _plan = null;
      _executionError = null;
      await _loadTables(epoch, context);
      if (!_valid(epoch, context)) return;
      await _loadSchema(epoch, context);
      if (!_valid(epoch, context)) return;
    });
  }

  Future<void> selectTable(String? table) async {
    if (_busy || _initializing || table == _table) return;
    if (table != null && !_tables.contains(table)) return;
    await _run((epoch, context) async {
      _table = table;
      _clearSchema();
      await _loadSchema(epoch, context);
      if (!_valid(epoch, context)) return;
    });
  }

  void _clearSchema() {
    _columns = const [];
    _indexes = const [];
    _schemaError = null;
    _schemaNote = null;
  }

  /// Reloads the database list, tables and the selected table metadata.
  Future<void> refresh() async {
    if (_busy || _initializing) return;
    await _run((epoch, context) async {
      final databases = await context.repository.listDatabases();
      if (!_valid(epoch, context)) return;
      _databases = List.unmodifiable(databases);
      if (!_databases.contains(_database)) {
        _database = _databases.isEmpty ? null : _databases.first;
        _table = null;
        _script = null;
        _plan = null;
      }
      _clearSchema();
      await _loadTables(epoch, context);
      if (!_valid(epoch, context)) return;
      await _loadSchema(epoch, context);
      if (!_valid(epoch, context)) return;
    });
  }

  /// Executes the retained source through the shared execution context.
  ///
  /// Every call opens its own connection, so the tools expose no standalone
  /// Begin/Commit action: a transaction must be one reviewed script. The context
  /// is revalidated right before dispatch, and a result from a context that has
  /// since changed is discarded instead of shown under the new engine.
  Future<void> runScript() async {
    if (_busy || _initializing || _disposed) return;
    final context = _target;
    final database = _database;
    final source = this.source.trim();
    if (context == null) {
      _executionError = '数据库引擎尚未连接';
      _script = null;
      _notify();
      return;
    }
    if (database == null) {
      _executionError = '请先选择一个本地数据库';
      _script = null;
      _notify();
      return;
    }
    if (source.isEmpty) {
      _executionError = '请输入要执行的 SQL';
      _script = null;
      _notify();
      return;
    }
    _executionError = null;
    _plan = null;
    await _run((epoch, context) async {
      SqlScriptResult result;
      try {
        context.requireCurrent();
        result = await context.runScript(database, source);
      } catch (error) {
        if (!_valid(epoch, context)) return;
        _script = null;
        _executionError = _message(error);
        return;
      }
      if (!_valid(epoch, context)) return;
      _script = result;
      _executionError = null;
      // History persistence is independent: a failure must never erase the
      // valid result the user just received.
      final library = _library;
      if (library != null) {
        try {
          await library.recordExecution(
            database: database,
            source: source,
            success: result.success,
          );
          if (!_valid(epoch, context)) return;
          _libraryError = null;
        } catch (error) {
          if (!_valid(epoch, context)) return;
          _libraryError = _message(error);
        }
      }
      if (!_valid(epoch, context)) return;
      // Earlier statements may have committed; refresh real metadata.
      try {
        await _loadTables(epoch, context);
        if (!_valid(epoch, context)) return;
        await _loadSchema(epoch, context);
        if (!_valid(epoch, context)) return;
      } catch (error) {
        if (!_valid(epoch, context)) return;
        _schemaError = _message(error);
      }
    });
  }

  /// Builds and runs a non-executing plan for exactly one query statement.
  Future<void> explain() async {
    if (_busy || _initializing || _disposed) return;
    final context = _target;
    final database = _database;
    if (context == null) {
      _executionError = '数据库引擎尚未连接';
      _notify();
      return;
    }
    if (database == null) {
      _executionError = '请先选择一个本地数据库';
      _notify();
      return;
    }
    if (!context.isCurrent) {
      _executionError = '数据库引擎已切换，请重新连接后运行。';
      _plan = null;
      _notify();
      _onEngineChanged();
      return;
    }
    final String planSql;
    try {
      planSql = buildSqlPlanRequest(source, dialect);
    } on SqlToolsException catch (error) {
      _executionError = error.message;
      _plan = null;
      _notify();
      return;
    }
    final engineLabel = context.engineLabel;
    _executionError = null;
    _script = null;
    await _run((epoch, context) async {
      final result = await context.runQuery(database, planSql);
      if (!_valid(epoch, context)) return;
      _plan = SqlPlanOutcome(
        engineLabel: engineLabel,
        planSql: planSql,
        result: result,
      );
    });
  }

  Future<void> _loadSchema(int epoch, SqlExecutionContext context) async {
    if (!_valid(epoch, context)) return;
    final database = _database;
    final table = _table;
    if (database == null || table == null) {
      _clearSchema();
      return;
    }
    final SqlWorkspaceRepository repository;
    try {
      repository = context.repository;
    } catch (error) {
      _columns = const [];
      _indexes = const [];
      _schemaNote = _message(error);
      return;
    }
    try {
      final columns = await repository.tableColumns(database, table);
      if (!_valid(epoch, context)) return;
      _columns = List.unmodifiable(columns);
      _schemaError = null;
    } catch (error) {
      if (!_valid(epoch, context)) return;
      _columns = const [];
      _schemaError = _message(error);
    }
    // The engine may have changed while columns were loading. Recheck before
    // dispatching a second metadata command as well as before publishing it.
    if (!_valid(epoch, context)) return;
    try {
      final indexes = context.engine == SqlEngineKind.sqlite
          ? await _loadSqliteIndexes(epoch, context, database, table)
          : await repository.tableIndexes(database, table);
      if (!_valid(epoch, context)) return;
      _indexes = List.unmodifiable(indexes);
      _schemaNote = null;
    } on UnsupportedError catch (error) {
      if (!_valid(epoch, context)) return;
      _indexes = const [];
      _schemaNote = error.message ?? '当前引擎不支持索引查看';
    } catch (error) {
      if (!_valid(epoch, context)) return;
      _indexes = const [];
      _schemaNote = _message(error);
    }
  }

  Future<List<SqlIndex>> _loadSqliteIndexes(
    int epoch,
    SqlExecutionContext context,
    String database,
    String table,
  ) async {
    final listed = await context.runQuery(
      database,
      'PRAGMA main.index_list(${quoteSqlString(table, SqlDialect.sqlite)})',
    );
    if (!_valid(epoch, context)) return const [];
    final rows = _metadataRows(listed, const [
      'name',
      'unique',
      'origin',
      'partial',
    ]);
    final indexes = <SqlIndex>[];
    for (final row in rows) {
      final name = row['name'];
      final origin = row['origin'];
      if (name == null ||
          name.isEmpty ||
          !const {'c', 'u', 'pk'}.contains(origin) ||
          !const {'0', '1'}.contains(row['unique']) ||
          !const {'0', '1'}.contains(row['partial'])) {
        throw const SqlToolsException('SQLite 索引信息不完整，请刷新结构后重试');
      }
      // Every call uses the captured context, including the per-index detail
      // query. A preference change must stop the next dispatch as well as UI
      // publication. String arguments preserve quotes and unusual object names.
      if (!_valid(epoch, context)) return const [];
      final details = await context.runQuery(
        database,
        'PRAGMA main.index_info(${quoteSqlString(name, SqlDialect.sqlite)})',
      );
      if (!_valid(epoch, context)) return const [];
      final columns = <(int, String)>[];
      for (final column in _metadataRows(details, const [
        'seqno',
        'cid',
        'name',
      ])) {
        final sequence = int.tryParse(column['seqno'] ?? '');
        final cid = int.tryParse(column['cid'] ?? '');
        final columnName = column['name'];
        if (sequence == null ||
            sequence < 0 ||
            cid == null ||
            cid < -2 ||
            (cid >= 0 && (columnName == null || columnName.isEmpty))) {
          throw const SqlToolsException('SQLite 索引列信息不完整，请刷新结构后重试');
        }
        columns.add((sequence, columnName ?? (cid == -2 ? '（表达式）' : 'rowid')));
      }
      columns.sort((a, b) => a.$1.compareTo(b.$1));
      if (columns.isEmpty ||
          columns.map((column) => column.$1).toSet().length != columns.length) {
        throw const SqlToolsException('SQLite 索引结构已变更或不完整，请刷新后重试');
      }
      indexes.add(
        SqliteToolIndex(
          name: name,
          columns: List.unmodifiable(columns.map((column) => column.$2)),
          unique: row['unique'] == '1',
          origin: origin!,
          partial: row['partial'] == '1',
        ),
      );
    }
    return indexes;
  }

  List<Map<String, String?>> _metadataRows(
    SqlQueryResult result,
    List<String> requiredColumns,
  ) {
    if (!result.success) {
      throw SqlToolsException(result.error ?? 'SQLite 索引信息不可用');
    }
    if (result.truncated) {
      throw const SqlToolsException('SQLite 索引信息已截断，无法显示完整结构');
    }
    if (requiredColumns.any((column) => !result.columns.contains(column)) ||
        result.rows.any((row) => row.length != result.columns.length)) {
      throw const SqlToolsException('SQLite 返回了无法识别的索引信息');
    }
    return [
      for (final row in result.rows)
        {
          for (var i = 0; i < result.columns.length; i++)
            result.columns[i]: row[i],
        },
    ];
  }

  /// Steps to the next database without wrapping, for keyboard/menu access.
  Future<void> cycleDatabase(int delta) async {
    if (_databases.isEmpty) return;
    final index = _databases.indexOf(_database ?? '');
    final next = (index + delta) % _databases.length;
    await selectDatabase(
      _databases[next < 0 ? next + _databases.length : next],
    );
  }

  /// Builds a reviewed CREATE INDEX statement. Nothing is executed here.
  String? buildCreateIndexSql({
    required String name,
    required List<String> columns,
    required bool unique,
  }) {
    final dialect = this.dialect;
    final table = _table;
    if (table == null) return null;
    if (dialect != SqlDialect.mysql) {
      throw const SqlToolsException('当前引擎的索引操作仅支持查看，不生成变更语句');
    }
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const SqlToolsException('请输入索引名称');
    }
    if (columns.isEmpty) {
      throw const SqlToolsException('请至少选择一列');
    }
    if (columns.toSet().length != columns.length) {
      throw const SqlToolsException('索引列不能重复');
    }
    if (columns.any((name) => !_columns.any((column) => column.name == name))) {
      throw const SqlToolsException('索引列已变更，请刷新结构并重新选择');
    }
    return 'CREATE ${unique ? 'UNIQUE ' : ''}INDEX '
        '${quoteSqlIdentifier(trimmed, dialect)} ON '
        '${quoteSqlIdentifier(table, dialect)} '
        '(${columns.map((column) => quoteSqlIdentifier(column, dialect)).join(', ')});';
  }

  /// Builds a reviewed DROP INDEX statement. Nothing is executed here.
  String? buildDropIndexSql(String index) {
    final table = _table;
    if (table == null) return null;
    if (dialect != SqlDialect.mysql) {
      throw const SqlToolsException('当前引擎的索引操作仅支持查看，不生成变更语句');
    }
    if (_indexes.any((item) => item.name == index && item.primary)) {
      throw const SqlToolsException('主键不使用 DROP INDEX，请在工作表中明确修改表结构');
    }
    return 'DROP INDEX ${quoteSqlIdentifier(index, dialect)} ON '
        '${quoteSqlIdentifier(table, dialect)};';
  }

  /// Builds the offline identifier helper output for the current dialect.
  String identifierHelp(String name) {
    final quoted = quoteSqlIdentifier(name, dialect);
    return '${dialect == SqlDialect.mysql ? 'MySQL' : 'SQLite'}：$quoted';
  }

  /// Builds the offline value helper output (NULL vs empty vs literal).
  String valueHelp(String? value) {
    if (value == null) return '$sqlNullLiteral —— SQL 空值，不是空字符串';
    final literal = quoteSqlString(value, dialect);
    return value.isEmpty ? "$literal —— 空字符串" : literal;
  }

  /// The formatted source, or the original text when nothing is formattable.
  String formattedSource() {
    final formatted = formatSqlText(source, dialect: dialect);
    return formatted.isEmpty ? source : formatted;
  }

  Future<void> _run(
    Future<void> Function(int epoch, SqlExecutionContext context) action,
  ) async {
    if (_busy || _initializing || _disposed) return;
    final context = _target;
    if (context == null) {
      _executionError = '数据库引擎尚未连接';
      _notify();
      return;
    }
    if (!context.isCurrent) {
      _onEngineChanged();
      return;
    }
    final epoch = _epoch;
    _busy = true;
    _notify();
    try {
      await action(epoch, context);
      if (!_valid(epoch, context)) return;
    } catch (error) {
      if (!_valid(epoch, context)) return;
      _executionError = _message(error);
    } finally {
      _busy = false;
      _notify();
      _reconnectWhenIdle();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  static String _message(Object error) => error
      .toString()
      .replaceFirst('Bad state: ', '')
      .replaceFirst('Unsupported operation: ', '')
      .replaceFirst('FileSystemException: ', '')
      .replaceFirst('SqlToolsException: ', '');

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    if (watchPreference) {
      _engineChanges.removeListener(_onEngineChanged);
    }
    super.dispose();
  }
}
