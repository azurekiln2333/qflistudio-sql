/// Pure, bounded SQL lexical analysis shared by editor diagnostics and the SQL
/// text tools.
///
/// This layer never executes SQL, never touches databases or files, and does
/// not claim to be a full grammar, type or schema checker. It reports only what
/// a literal/comment/delimiter scan can prove, plus the statement boundaries
/// that the native prepare-only validator needs.
///
/// Offsets are zero-based, half-open UTF-16 code-unit ranges into the exact
/// analyzed text, so CRLF line endings, supplementary-plane characters and
/// Chinese text keep their real editor positions.
library;

/// SQL dialect rules that change the lexical meaning of the source.
enum SqlDialect {
  /// Bundled SQLite: double quotes quote identifiers, `--` always comments,
  /// backslash has no escape meaning inside string literals.
  sqlite,

  /// Oracle MySQL conventions as seen in the common default SQL mode: `#` and
  /// `-- ` (whitespace required) start comments, double quotes delimit string
  /// literals, and backslash escapes are interpreted.
  ///
  /// A server session may set `NO_BACKSLASH_ESCAPES` or `ANSI_QUOTES`, so these
  /// are the scanner's documented assumptions, not a universal MySQL truth. The
  /// scanner never connects to a server and cannot read a session's real mode.
  mysql,
}

/// Token categories that both dialects produce.
enum SqlTokenKind {
  whitespace,
  lineComment,
  blockComment,
  string,
  identifier,
  number,
  word,
  parameter,
  operator,
  punctuation,
}

/// One scanned token. [start] and [end] are UTF-16 code-unit offsets.
class SqlToken {
  const SqlToken({
    required this.kind,
    required this.start,
    required this.end,
    required this.text,
    this.terminated = true,
  });

  final SqlTokenKind kind;
  final int start;
  final int end;
  final String text;

  /// Whether a quoted token reached an unescaped closing delimiter.
  final bool terminated;

  int get length => end - start;

  bool get isTrivia =>
      kind == SqlTokenKind.whitespace ||
      kind == SqlTokenKind.lineComment ||
      kind == SqlTokenKind.blockComment;

  bool get isWord => kind == SqlTokenKind.word;

  /// Uppercase keyword form used for keyword comparisons only.
  String get keyword => text.toUpperCase();
}

enum SqlIssueSeverity { error, warning, information }

/// A lexical problem with an exact editor range.
class SqlLexicalIssue {
  const SqlLexicalIssue({
    required this.start,
    required this.end,
    required this.message,
    required this.code,
    this.severity = SqlIssueSeverity.error,
  });

  final int start;
  final int end;
  final String message;
  final String code;
  final SqlIssueSeverity severity;
}

/// One top-level statement range, without surrounding trivia.
class SqlStatement {
  const SqlStatement({
    required this.start,
    required this.end,
    required this.leadingKeywords,
  });

  final int start;
  final int end;

  /// Uppercase words at the start of the statement, trivia excluded, at most
  /// four entries (`CREATE OR REPLACE TRIGGER` style prefixes included).
  final List<String> leadingKeywords;

  bool get isEmpty => end <= start;

  String get leading => leadingKeywords.isEmpty ? '' : leadingKeywords.first;
}

/// Bounded result of a full lexical pass.
class SqlLexicalAnalysis {
  const SqlLexicalAnalysis({
    required this.tokens,
    required this.issues,
    required this.statements,
    required this.truncated,
  });

  final List<SqlToken> tokens;
  final List<SqlLexicalIssue> issues;
  final List<SqlStatement> statements;

  /// True when the input exceeded the scanner budget, so the tail was not
  /// analyzed. A truncated scan is never reported as clean.
  final bool truncated;
}

/// Non-executing grammar validation produced by an isolated engine.
enum SqlEngineIssueSeverity { error, warning }

class SqlEngineIssue {
  const SqlEngineIssue({
    required this.startOffset,
    required this.endOffset,
    required this.message,
    required this.code,
    this.severity = SqlEngineIssueSeverity.error,
  });

  final int startOffset;
  final int endOffset;
  final String message;
  final String code;
  final SqlEngineIssueSeverity severity;
}

/// A statement deliberately excluded from engine validation.
class SqlSkippedStatement {
  const SqlSkippedStatement({
    required this.startOffset,
    required this.endOffset,
    required this.keyword,
    required this.reason,
  });

  final int startOffset;
  final int endOffset;
  final String keyword;
  final String reason;
}

/// Result of the prepare-only engine check.
class SqlEngineAnalysis {
  const SqlEngineAnalysis({
    required this.engine,
    required this.version,
    required this.issues,
    required this.skipped,
    required this.statements,
    required this.checked,
    required this.schemaGaps,
    this.truncated = false,
    this.unavailableReason,
  });

  /// Engine actually consulted, for example `sqlite`.
  final String engine;

  /// Runtime version reported by the engine, empty when unknown.
  final String version;

  /// Real syntax failures only; missing-schema results are counted instead.
  final List<SqlEngineIssue> issues;

  final List<SqlSkippedStatement> skipped;
  final int statements;
  final int checked;

  /// Statements that prepared into a "no such ..." schema error inside the
  /// isolated empty database. These are not syntax failures and must not be
  /// reported as clean either.
  final int schemaGaps;

  final bool truncated;

  /// Non-null when the backend did not run. Diagnostics must never be presented
  /// as a successful empty result in that case.
  final String? unavailableReason;

  bool get ran => unavailableReason == null;
}

/// Guarded subset of SQLite statements accepted by the prepare-only validator.
abstract final class SqlPrepareGuard {
  /// Keywords that are refused before `sqlite3_prepare*` is called.
  ///
  /// SQLite documents that some PRAGMAs act during prepare, and `EXPLAIN` does
  /// not suppress those effects. ATTACH/DETACH would open other database
  /// files, VACUUM/REINDEX/ANALYZE rewrite or read user state.
  static const Map<String, String> blockedKeywords = {
    'ATTACH': 'ATTACH 会打开其他数据库文件，已在隔离校验中跳过',
    'DETACH': 'DETACH 会关闭数据库连接，已在隔离校验中跳过',
    'PRAGMA': 'PRAGMA 可能在 prepare 阶段修改数据库状态，已在隔离校验中跳过',
    'VACUUM': 'VACUUM 会重建数据库文件，已在隔离校验中跳过',
    'REINDEX': 'REINDEX 会写入索引数据，已在隔离校验中跳过',
    'ANALYZE': 'ANALYZE 会写入统计信息，已在隔离校验中跳过',
  };

  /// Keywords that are transparent for the guard decision.
  static const Set<String> _modifiers = {'EXPLAIN', 'QUERY', 'PLAN'};

  /// The statement keyword the guard evaluates, skipping `EXPLAIN [QUERY PLAN]`.
  static String target(List<String> leadingKeywords) {
    var index = 0;
    while (index < leadingKeywords.length &&
        _modifiers.contains(leadingKeywords[index])) {
      index++;
    }
    return index < leadingKeywords.length ? leadingKeywords[index] : '';
  }

  /// Blocked reason for [statement], or null when prepare-only checking is safe.
  static String? blockedReason(SqlStatement statement) =>
      blockedKeywords[target(statement.leadingKeywords)];
}

/// Bounded scanner and lexical validator.
abstract final class SqlSyntaxValidator {
  /// Maximum number of scanned characters. Larger inputs are analyzed only up to
  /// this budget and report `truncated`.
  static const int maxScanUnits = 1024 * 1024;

  /// Maximum number of reported lexical issues.
  static const int maxIssues = 200;

  /// Scans [source] with dialect rules and reports only provable problems.
  static SqlLexicalAnalysis analyze(
    String source, {
    SqlDialect dialect = SqlDialect.sqlite,
    int maxUnits = maxScanUnits,
  }) {
    final truncated = source.length > maxUnits;
    final text = truncated ? source.substring(0, maxUnits) : source;
    final tokens = tokenize(text, dialect: dialect);
    final issues = <SqlLexicalIssue>[];
    final openParens = <SqlToken>[];

    void add(
      int start,
      int end,
      String message,
      String code, {
      SqlIssueSeverity severity = SqlIssueSeverity.error,
    }) {
      if (issues.length >= maxIssues) return;
      issues.add(
        SqlLexicalIssue(
          start: start.clamp(0, text.length),
          end: end.clamp(0, text.length),
          message: message,
          code: code,
          severity: severity,
        ),
      );
    }

    for (final token in tokens) {
      switch (token.kind) {
        case SqlTokenKind.string:
          if (!truncated && !token.terminated) {
            add(
              token.start,
              token.end,
              '字符串字面量未结束；请补齐结束引号',
              'unterminated-string',
            );
          }
        case SqlTokenKind.identifier:
          if (!truncated && !token.terminated) {
            add(
              token.start,
              token.end,
              '引号标识符未结束；请补齐结束引号',
              'unterminated-identifier',
            );
          }
        case SqlTokenKind.blockComment:
          if (!truncated &&
              (!token.text.endsWith('*/') || token.text.length < 4)) {
            add(
              token.start,
              token.end,
              '块注释未结束；请补齐 */',
              'unterminated-block-comment',
            );
          }
        case SqlTokenKind.punctuation:
          if (token.text == '(') {
            openParens.add(token);
          } else if (token.text == ')') {
            if (openParens.isEmpty) {
              add(
                token.start,
                token.end,
                '括号不匹配：这里有一个多余的右括号',
                'unmatched-close-paren',
              );
            } else {
              openParens.removeLast();
            }
          }
        case SqlTokenKind.whitespace:
        case SqlTokenKind.lineComment:
          break;
        case SqlTokenKind.number:
        case SqlTokenKind.word:
        case SqlTokenKind.parameter:
        case SqlTokenKind.operator:
          break;
      }
    }
    // A scan cutoff is not the source's EOF: unseen text may close a token or
    // parenthesis. Only a complete scan can prove those missing delimiters.
    if (!truncated) {
      for (final token in openParens.reversed) {
        add(
          token.start,
          token.end,
          '括号不匹配：左括号缺少配对的右括号',
          'unmatched-open-paren',
        );
      }
    }
    for (var index = 0; index < text.length; index++) {
      if (text.codeUnitAt(index) != 0) continue;
      add(
        index,
        index + 1,
        '文本包含 NUL 字符；SQLite 与 MySQL 会在此处截断 SQL',
        'nul-character',
      );
      break;
    }
    if (truncated) {
      add(
        maxUnits,
        maxUnits,
        '文本超过 ${maxUnits ~/ 1024} KiB，超出部分未做词法检查',
        'scan-truncated',
        severity: SqlIssueSeverity.information,
      );
    }
    final ranges = _statements(
      tokens,
      onAmbiguousTrigger: (token) => add(
        token.start,
        token.end,
        '触发器中的 BEGIN/END 可能是列名，词法语句边界无法确认；请以引擎校验为准',
        'statement-boundary-unsupported',
        severity: SqlIssueSeverity.information,
      ),
    );
    issues.sort((left, right) => left.start.compareTo(right.start));
    return SqlLexicalAnalysis(
      tokens: tokens,
      issues: List.unmodifiable(issues),
      statements: ranges,
      truncated: truncated,
    );
  }

  /// Splits [tokens] into top-level statements, honoring literals, comments,
  /// parentheses and SQLite trigger bodies. Naive `split(';')` is never used.
  static List<SqlStatement> statements(List<SqlToken> tokens) =>
      _statements(tokens);

  static List<SqlStatement> _statements(
    List<SqlToken> tokens, {
    void Function(SqlToken)? onAmbiguousTrigger,
  }) {
    final result = <SqlStatement>[];
    final keywords = <String>[];
    var start = -1;
    var end = -1;
    var parenDepth = 0;
    var blockDepth = 0;
    var caseDepth = 0;
    var sawTrigger = false;

    void close([int? terminator]) {
      final stop = terminator == null || end < terminator ? end : terminator;
      if (start >= 0 && stop > start) {
        result.add(
          SqlStatement(
            start: start,
            end: stop,
            leadingKeywords: List.unmodifiable(keywords.take(4)),
          ),
        );
      }
      keywords.clear();
      start = -1;
      end = -1;
      parenDepth = 0;
      blockDepth = 0;
      caseDepth = 0;
      sawTrigger = false;
    }

    for (var tokenIndex = 0; tokenIndex < tokens.length; tokenIndex++) {
      final token = tokens[tokenIndex];
      if (token.isTrivia) continue;
      final terminates =
          token.kind == SqlTokenKind.punctuation &&
          token.text == ';' &&
          parenDepth == 0 &&
          blockDepth == 0 &&
          caseDepth == 0;
      if (!terminates) {
        if (start < 0) start = token.start;
        end = token.end;
      }
      // EXPLAIN QUERY PLAN CREATE TEMP TRIGGER needs six prefix words. Match
      // the declaration itself: a table named "trigger" is not a trigger.
      if (token.isWord && keywords.length < 6) {
        keywords.add(token.keyword);
        sawTrigger = sawTrigger || _isTriggerPrefix(keywords);
      }
      if (token.kind == SqlTokenKind.punctuation) {
        switch (token.text) {
          case '(':
            parenDepth++;
          case ')':
            if (parenDepth > 0) parenDepth--;
          case ';':
            // The terminator is not part of the statement range.
            if (terminates) close(token.start);
        }
        continue;
      }
      if (!sawTrigger || !token.isWord) continue;
      switch (token.keyword) {
        case 'BEGIN':
          if (blockDepth > 0) onAmbiguousTrigger?.call(token);
          blockDepth++;
        case 'CASE':
          caseDepth++;
        case 'END':
          var next = tokenIndex + 1;
          while (next < tokens.length && tokens[next].isTrivia) {
            next++;
          }
          if (next < tokens.length &&
              (tokens[next].text == '=' || tokens[next].text == '.')) {
            onAmbiguousTrigger?.call(token);
          }
          if (caseDepth > 0) {
            caseDepth--;
          } else if (blockDepth > 0) {
            blockDepth--;
          }
      }
    }
    close();
    return List.unmodifiable(result);
  }

  static bool _isTriggerPrefix(List<String> keywords) {
    var index = 0;
    if (keywords.first == 'EXPLAIN') {
      index++;
      if (index < keywords.length && keywords[index] == 'QUERY') {
        if (index + 1 >= keywords.length || keywords[index + 1] != 'PLAN') {
          return false;
        }
        index += 2;
      }
    }
    if (index >= keywords.length || keywords[index++] != 'CREATE') return false;
    if (index < keywords.length &&
        (keywords[index] == 'TEMP' || keywords[index] == 'TEMPORARY')) {
      index++;
    }
    return index + 1 == keywords.length && keywords[index] == 'TRIGGER';
  }

  /// Bounded tokenizer over [source].
  static List<SqlToken> tokenize(
    String source, {
    SqlDialect dialect = SqlDialect.sqlite,
  }) {
    final tokens = <SqlToken>[];
    final length = source.length;
    var index = 0;

    void emit(
      SqlTokenKind kind,
      int start,
      int end, {
      bool terminated = true,
    }) => tokens.add(
      SqlToken(
        kind: kind,
        start: start,
        end: end,
        text: source.substring(start, end),
        terminated: terminated,
      ),
    );

    while (index < length) {
      final start = index;
      final unit = source.codeUnitAt(index);

      if (_isSpace(unit)) {
        index++;
        while (index < length && _isSpace(source.codeUnitAt(index))) {
          index++;
        }
        emit(SqlTokenKind.whitespace, start, index);
        continue;
      }

      if (unit == 0x2D &&
          index + 1 < length &&
          source.codeUnitAt(index + 1) == 0x2D) {
        final follows = index + 2 < length
            ? source.codeUnitAt(index + 2)
            : 0x0A;
        final comments =
            dialect == SqlDialect.sqlite || _isSpace(follows) || follows == 0;
        if (comments) {
          index = _lineEnd(source, index + 2);
          emit(SqlTokenKind.lineComment, start, index);
          continue;
        }
      }
      if (unit == 0x23 && dialect == SqlDialect.mysql) {
        index = _lineEnd(source, index + 1);
        emit(SqlTokenKind.lineComment, start, index);
        continue;
      }
      if (unit == 0x2F &&
          index + 1 < length &&
          source.codeUnitAt(index + 1) == 0x2A) {
        final close = source.indexOf('*/', index + 2);
        index = close < 0 ? length : close + 2;
        emit(SqlTokenKind.blockComment, start, index);
        continue;
      }
      if (unit == 0x27) {
        final quoted = _quoted(
          source,
          index,
          0x27,
          backslash: dialect == SqlDialect.mysql,
        );
        index = quoted.end;
        emit(SqlTokenKind.string, start, index, terminated: quoted.terminated);
        continue;
      }
      if (unit == 0x22) {
        final isString = dialect == SqlDialect.mysql;
        final quoted = _quoted(source, index, 0x22, backslash: isString);
        index = quoted.end;
        emit(
          isString ? SqlTokenKind.string : SqlTokenKind.identifier,
          start,
          index,
          terminated: quoted.terminated,
        );
        continue;
      }
      if (unit == 0x60) {
        final quoted = _quoted(source, index, 0x60, backslash: false);
        index = quoted.end;
        emit(
          SqlTokenKind.identifier,
          start,
          index,
          terminated: quoted.terminated,
        );
        continue;
      }
      if (unit == 0x5B && dialect == SqlDialect.sqlite) {
        final close = source.indexOf(']', index + 1);
        index = close < 0 ? length : close + 1;
        emit(SqlTokenKind.identifier, start, index, terminated: close >= 0);
        continue;
      }
      if (unit == 0x3F) {
        index++;
        while (index < length && _isDigit(source.codeUnitAt(index))) {
          index++;
        }
        emit(SqlTokenKind.parameter, start, index);
        continue;
      }
      if ((unit == 0x3A || unit == 0x40 || unit == 0x24) &&
          index + 1 < length &&
          _isWordStart(source.codeUnitAt(index + 1))) {
        index++;
        while (index < length && _isWordPart(source.codeUnitAt(index))) {
          index++;
        }
        emit(SqlTokenKind.parameter, start, index);
        continue;
      }
      if (_isDigit(unit) ||
          (unit == 0x2E &&
              index + 1 < length &&
              _isDigit(source.codeUnitAt(index + 1)))) {
        index = _number(source, index);
        emit(SqlTokenKind.number, start, index);
        continue;
      }
      if (_isWordStart(unit)) {
        index++;
        while (index < length && _isWordPart(source.codeUnitAt(index))) {
          index++;
        }
        emit(SqlTokenKind.word, start, index);
        continue;
      }
      if (unit == 0x28 ||
          unit == 0x29 ||
          unit == 0x2C ||
          unit == 0x3B ||
          unit == 0x2E) {
        index++;
        emit(SqlTokenKind.punctuation, start, index);
        continue;
      }
      index = _operator(source, index);
      emit(SqlTokenKind.operator, start, index);
    }
    return List.unmodifiable(tokens);
  }

  static int _lineEnd(String source, int index) {
    while (index < source.length) {
      final unit = source.codeUnitAt(index);
      if (unit == 0x0A) return index + 1;
      index++;
    }
    return index;
  }

  /// Scans one quoted region starting at [start]. Doubled delimiters always
  /// escape; backslashes only escape in MySQL string literals.
  static ({int end, bool terminated}) _quoted(
    String source,
    int start,
    int delimiter, {
    required bool backslash,
  }) {
    var index = start + 1;
    while (index < source.length) {
      final unit = source.codeUnitAt(index);
      if (backslash && unit == 0x5C) {
        index += 2;
        continue;
      }
      if (unit == delimiter) {
        if (index + 1 < source.length &&
            source.codeUnitAt(index + 1) == delimiter) {
          index += 2;
          continue;
        }
        return (end: index + 1, terminated: true);
      }
      index++;
    }
    return (end: source.length, terminated: false);
  }

  static int _number(String source, int start) {
    var index = start;
    if (source.codeUnitAt(index) == 0x30 && index + 1 < source.length) {
      final next = source.codeUnitAt(index + 1);
      if (next == 0x78 || next == 0x58) {
        index += 2;
        while (index < source.length && _isHex(source.codeUnitAt(index))) {
          index++;
        }
        return index;
      }
    }
    while (index < source.length && _isDigit(source.codeUnitAt(index))) {
      index++;
    }
    if (index < source.length && source.codeUnitAt(index) == 0x2E) {
      index++;
      while (index < source.length && _isDigit(source.codeUnitAt(index))) {
        index++;
      }
    }
    if (index < source.length) {
      final unit = source.codeUnitAt(index);
      if (unit == 0x65 || unit == 0x45) {
        var lookahead = index + 1;
        if (lookahead < source.length) {
          final sign = source.codeUnitAt(lookahead);
          if (sign == 0x2B || sign == 0x2D) lookahead++;
        }
        if (lookahead < source.length &&
            _isDigit(source.codeUnitAt(lookahead))) {
          index = lookahead;
          while (index < source.length && _isDigit(source.codeUnitAt(index))) {
            index++;
          }
        }
      }
    }
    return index;
  }

  static const List<String> _multiOperators = [
    '<=>',
    '->>',
    '->',
    '<<',
    '>>',
    '<=',
    '>=',
    '<>',
    '!=',
    '||',
    '&&',
    ':=',
    '!<',
    '!>',
  ];

  static int _operator(String source, int start) {
    for (final operator in _multiOperators) {
      if (source.startsWith(operator, start)) return start + operator.length;
    }
    final unit = source.codeUnitAt(start);
    if (unit >= 0xD800 && unit <= 0xDBFF && start + 1 < source.length) {
      return start + 2;
    }
    return start + 1;
  }

  static bool _isSpace(int unit) =>
      unit == 0x20 ||
      unit == 0x09 ||
      unit == 0x0A ||
      unit == 0x0D ||
      unit == 0x0B ||
      unit == 0x0C;

  static bool _isDigit(int unit) => unit >= 0x30 && unit <= 0x39;

  static bool _isHex(int unit) =>
      _isDigit(unit) ||
      (unit >= 0x41 && unit <= 0x46) ||
      (unit >= 0x61 && unit <= 0x66);

  static bool _isWordStart(int unit) =>
      (unit >= 0x41 && unit <= 0x5A) ||
      (unit >= 0x61 && unit <= 0x7A) ||
      unit == 0x5F ||
      (unit >= 0x80 && unit != 0xA0);

  static bool _isWordPart(int unit) =>
      _isWordStart(unit) || _isDigit(unit) || unit == 0x24;
}
