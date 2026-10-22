import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/services/code_analysis.dart';

import 'sql_engine_preference.dart';
import 'sql_native_channel.dart';
import 'sql_syntax_validator.dart';
import 'sqlite_ffi.dart';

/// Non-executing SQL grammar/syntax backend used by [SqlCodeAnalyzer].
///
/// Implementations must never execute user SQL, never open a user database and
/// never write project, database or cache files. A missing backend reports an
/// [SqlEngineAnalysis.unavailableReason] instead of an empty success.
abstract interface class SqlSyntaxEngine {
  Future<SqlEngineAnalysis> validate(String text);
}

/// Prepare-only SQLite validation on the isolated in-memory engine.
///
/// Desktop and mobile use the bundled C library through [SqliteFfi]; platforms
/// without FFI (OHOS) use the asynchronous `qfli_sql/native` validation bridge.
/// A missing bridge reports an explicit unavailable reason.
class SqlitePrepareSyntaxEngine implements SqlSyntaxEngine {
  const SqlitePrepareSyntaxEngine({this.libraryPath, this.timeout});

  /// Test/development override for the bundled library, never a fallback engine.
  final String? libraryPath;

  /// Bounded wait so a stalled native bridge cannot block the editor lane.
  final Duration? timeout;

  static const String method = 'validate';

  @override
  Future<SqlEngineAnalysis> validate(String text) async {
    try {
      final raw = await _invoke(
        text,
      ).timeout(timeout ?? const Duration(seconds: 5));
      return decodeResult(raw, text);
    } on Object catch (error) {
      return SqlEngineAnalysis(
        engine: 'sqlite',
        version: '',
        issues: const [],
        skipped: const [],
        statements: 0,
        checked: 0,
        schemaGaps: 0,
        unavailableReason: error is MissingPluginException
            ? '当前平台尚未提供 SQLite 语法校验接口（需要原生桥接实现 $method）'
            : 'SQLite 语法校验后端不可用：$error',
      );
    }
  }

  /// Decodes the shared FFI/OHOS contract without inventing clean defaults.
  /// A damaged response must remain visibly unavailable in the editor.
  static SqlEngineAnalysis decodeResult(Map<String, Object?> raw, String text) {
    Never invalid(String field) =>
        throw FormatException('SQLite 语法校验响应无效：$field');
    int count(String key) {
      final value = raw[key];
      if (value is! int || value < 0) invalid(key);
      return value;
    }

    String string(Map value, String key, {bool empty = false}) {
      final result = value[key];
      if (result is! String || (!empty && result.trim().isEmpty)) invalid(key);
      return result;
    }

    (int, int) range(Map value) {
      final start = value['startOffset'];
      final end = value['endOffset'];
      if (start is! int ||
          end is! int ||
          start < 0 ||
          end < start ||
          end > text.length) {
        invalid('UTF-16 range');
      }
      return (start, end);
    }

    if (raw['engine'] != 'sqlite' ||
        raw['available'] is! bool ||
        raw['truncated'] is! bool ||
        raw['version'] is! String ||
        raw['issues'] is! List ||
        raw['skipped'] is! List ||
        (raw['error'] != null && raw['error'] is! String)) {
      invalid('engine/available/version/issues/skipped/truncated/error');
    }
    final statements = count('statements');
    final checked = count('checked');
    final schemaGaps = count('schemaGaps');
    if (checked > statements || schemaGaps > checked) invalid('coverage');
    final available = raw['available'] as bool;
    final truncated = raw['truncated'] as bool;
    final version = raw['version'] as String;
    if (available && version.trim().isEmpty) invalid('version');
    final issues = <SqlEngineIssue>[];
    for (final item in raw['issues'] as List) {
      if (item is! Map) invalid('issue');
      final (start, end) = range(item);
      if (item['severity'] != 'error' && item['severity'] != 'warning') {
        invalid('severity');
      }
      issues.add(
        SqlEngineIssue(
          startOffset: start,
          endOffset: end,
          message: string(item, 'message'),
          code: string(item, 'code'),
          severity: item['severity'] == 'warning'
              ? SqlEngineIssueSeverity.warning
              : SqlEngineIssueSeverity.error,
        ),
      );
    }
    final skipped = <SqlSkippedStatement>[];
    for (final item in raw['skipped'] as List) {
      if (item is! Map) invalid('skipped statement');
      final (start, end) = range(item);
      skipped.add(
        SqlSkippedStatement(
          startOffset: start,
          endOffset: end,
          keyword: string(item, 'keyword', empty: true),
          reason: string(item, 'reason'),
        ),
      );
    }
    final error = (raw['error'] as String?)?.trim();
    String? reason;
    if (!available) {
      reason = error?.isNotEmpty == true ? error : 'SQLite 语法校验后端未运行';
    } else if (error?.isNotEmpty == true) {
      reason = error;
    } else if (checked == 0 && skipped.isEmpty && !truncated) {
      final lexical = SqlSyntaxValidator.analyze(text);
      if (lexical.truncated ||
          lexical.statements.isNotEmpty ||
          lexical.issues.isNotEmpty ||
          statements != 0) {
        invalid('backend did not check the supplied SQL');
      }
    } else if (checked < statements && skipped.isEmpty && !truncated) {
      reason = 'SQLite 引擎仅检查了 $checked/$statements 条语句，校验未完整完成';
    }
    return SqlEngineAnalysis(
      engine: 'sqlite',
      version: version,
      issues: List.unmodifiable(issues),
      skipped: List.unmodifiable(skipped),
      statements: statements,
      checked: checked,
      schemaGaps: schemaGaps,
      truncated: truncated,
      unavailableReason: reason,
    );
  }

  Future<Map<String, Object?>> _invoke(String text) async {
    if (SqliteFfi.supported) {
      return SqliteFfi.invoke(method, {
        'source': text,
      }, libraryPath: libraryPath);
    }
    final result = await invokeSqliteNative(method, {'source': text});
    if (result is Map) return result.cast<String, Object?>();
    throw PlatformException(
      code: 'sqlite_validate',
      message: '原生桥接返回了无法识别的语法校验结果',
    );
  }
}

/// Offline diagnostics for exact unsaved SQL snapshots.
///
/// Never rereads the saved file, never saves the editor, never executes SQL and
/// never writes project or database files. Lexical analysis covers every owned
/// open SQL buffer; the prepare-only engine check runs on the active buffer only
/// so a large workspace cannot stall the editor lane.
class SqlCodeAnalyzer implements CodeAnalyzer {
  const SqlCodeAnalyzer({
    this.engine = const SqlitePrepareSyntaxEngine(),
    this.maxEngineUnits = 512 * 1024,
  });

  final SqlSyntaxEngine engine;

  /// Engine checking is skipped above this many UTF-16 code units.
  final int maxEngineUnits;

  static const String source = 'SQL 语法';

  @override
  Future<CodeAnalysisResult> analyze(CodeAnalysisRequest request) async {
    final root = p.normalize(p.absolute(request.projectPath));
    final activePath = p.normalize(p.absolute(request.activeFilePath));
    if (!_isSqlPath(activePath) || !_owned(root, activePath)) {
      return const CodeAnalysisResult(unavailableReason: 'SQL 文件不在当前项目内');
    }
    final documents = <CodeDocumentSnapshot>[];
    for (final document in request.documents) {
      final path = p.normalize(p.absolute(document.path));
      if (!_isSqlPath(path) || !_owned(root, path)) continue;
      documents.add(
        CodeDocumentSnapshot(
          path: path,
          text: document.text,
          revision: document.revision,
        ),
      );
    }
    CodeDocumentSnapshot? active;
    for (final document in documents) {
      if (p.equals(document.path, activePath)) active = document;
    }
    if (active == null) {
      return const CodeAnalysisResult(unavailableReason: '没有当前 SQL 文件的未保存快照');
    }

    final dialect = await _dialect(root);
    final lexical = await Isolate.run(() {
      final results =
          <({String path, List<SqlLexicalIssue> issues, bool truncated})>[];
      for (final document in documents) {
        final analysis = SqlSyntaxValidator.analyze(
          document.text,
          dialect: dialect,
        );
        results.add((
          path: document.path,
          issues: analysis.issues,
          truncated: analysis.truncated,
        ));
      }
      return results;
    });

    final diagnostics = <CodeDiagnostic>[];
    final reasons = <String>[];
    for (final entry in lexical) {
      for (final issue in entry.issues) {
        diagnostics.add(
          CodeDiagnostic(
            filePath: entry.path,
            startOffset: issue.start,
            endOffset: issue.end,
            message: issue.message,
            severity: switch (issue.severity) {
              SqlIssueSeverity.error => CodeDiagnosticSeverity.error,
              SqlIssueSeverity.warning => CodeDiagnosticSeverity.warning,
              SqlIssueSeverity.information =>
                CodeDiagnosticSeverity.information,
            },
            source: source,
            code: issue.code,
          ),
        );
      }
    }

    if (dialect == SqlDialect.mysql) {
      reasons.add('MySQL 方言仅做本地词法检查，未连接 MySQL 服务端校验语法');
    } else if (active.text.length > maxEngineUnits) {
      reasons.add('当前文件超过引擎校验上限（$maxEngineUnits UTF-16 单元），仅做词法检查');
    } else if (active.text.contains('\x00')) {
      reasons.add('文本包含 NUL 字符，未做引擎语法校验');
    } else {
      SqlEngineAnalysis? result;
      try {
        result = await engine.validate(active.text);
      } on Object catch (error) {
        reasons.add('SQLite 语法校验后端不可用：$error');
      }
      if (result == null) {
        // Reason already recorded; lexical diagnostics stay visible.
      } else if (result.unavailableReason != null) {
        reasons.add(result.unavailableReason!);
      }
      for (final issue in result?.issues ?? const <SqlEngineIssue>[]) {
        diagnostics.add(
          CodeDiagnostic(
            filePath: active.path,
            startOffset: issue.startOffset.clamp(0, active.text.length),
            endOffset: issue.endOffset.clamp(0, active.text.length),
            message: issue.message,
            severity: issue.severity == SqlEngineIssueSeverity.warning
                ? CodeDiagnosticSeverity.warning
                : CodeDiagnosticSeverity.error,
            source: 'SQLite 引擎',
            code: issue.code,
            // The engine label is recorded in SQL source only; the diagnostic
            // source stays stable so Problems grouping is predictable.
          ),
        );
      }
      for (final skipped in result?.skipped ?? const <SqlSkippedStatement>[]) {
        final start = skipped.startOffset.clamp(0, active.text.length);
        diagnostics.add(
          CodeDiagnostic(
            filePath: active.path,
            startOffset: start,
            endOffset: (start + skipped.keyword.length).clamp(
              start,
              active.text.length,
            ),
            message: skipped.reason,
            severity: CodeDiagnosticSeverity.information,
            source: 'SQLite 引擎',
            code: 'statement-skipped',
          ),
        );
      }
      if ((result?.schemaGaps ?? 0) > 0) {
        diagnostics.add(
          CodeDiagnostic(
            filePath: active.path,
            startOffset: 0,
            endOffset: 0,
            message:
                '${result!.schemaGaps} 条语句引用了隔离校验库中不存在的对象，'
                '缺失的 schema 上下文阻止了完整校验，部分语法及类型问题可能尚未检查',
            severity: CodeDiagnosticSeverity.information,
            source: 'SQLite 引擎',
            code: 'schema-gap',
          ),
        );
      }
      if (result?.truncated == true) {
        diagnostics.add(
          CodeDiagnostic(
            filePath: active.path,
            startOffset: 0,
            endOffset: 0,
            message: '引擎未完整校验文本；部分语句因错误、缺失上下文或资源上限而跳过',
            severity: CodeDiagnosticSeverity.information,
            source: 'SQLite 引擎',
            code: 'engine-truncated',
          ),
        );
      }
    }

    if (lexical.any((entry) => entry.truncated)) {
      reasons.add('部分文件超出词法扫描上限，未完整检查');
    }

    return CodeAnalysisResult(
      diagnostics: List.unmodifiable(diagnostics),
      unavailableReason: reasons.isEmpty ? null : reasons.join('；'),
    );
  }

  static bool _isSqlPath(String path) =>
      p.extension(path).toLowerCase() == '.sql';

  static bool _owned(String root, String path) {
    if (p.equals(root, path)) return false;
    return p.isWithin(root, path);
  }

  /// MySQL is decided by the project's own engine marker (and the current app
  /// engine selection). A MySQL project is never checked with SQLite grammar.
  static Future<SqlDialect> _dialect(String root) async {
    try {
      final marker = File(p.join(root, '.qfli', 'mysql.json'));
      if (await marker.exists()) {
        final data = jsonDecode(await marker.readAsString());
        if (data is Map && data['schema'] is String) return SqlDialect.mysql;
      }
    } on Object {
      // An unreadable marker is still a MySQL project marker.
      return SqlDialect.mysql;
    }
    return SqlEnginePreference.current == SqlEngineKind.localMysql
        ? SqlDialect.mysql
        : SqlDialect.sqlite;
  }
}
