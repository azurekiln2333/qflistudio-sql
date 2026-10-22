import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

import 'sql_syntax_validator.dart';

final class _ScriptResult extends Struct {
  @Int32()
  external int available;
  @Int32()
  external int exitCode;
  @Int32()
  external int truncated;
  external Pointer<Utf8> output;
  external Pointer<Utf8> error;
}

typedef _ValidationAuthorizer =
    Int32 Function(
      Pointer<Void>,
      Int32,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
    );

// SQLite invokes this synchronously on the isolate doing prepare. These action
// codes are the public PRAGMA/ATTACH/DETACH/CREATE_VTABLE/DROP_VTABLE/FUNCTION
// constants.
int _denyValidationEffects(
  Pointer<Void> context,
  int action,
  Pointer<Utf8> first,
  Pointer<Utf8> second,
  Pointer<Utf8> database,
  Pointer<Utf8> trigger,
) {
  if (const {19, 24, 25, 29, 30}.contains(action)) return 1; // SQLITE_DENY
  if (action == 31 && second != nullptr) {
    final name = second.toDartString().toLowerCase();
    if (const {
      'load_extension',
      'readfile',
      'writefile',
      'sqlite_readfile',
      'sqlite_writefile',
      'edit',
      'shell',
      'eval',
      'fts3_tokenizer',
    }.contains(name)) {
      return 1;
    }
  }
  return 0; // SQLITE_OK
}

/// Invokes the retained SQLite C engine on a worker isolate.
class SqliteFfi {
  static bool get supported =>
      Platform.isAndroid ||
      Platform.isIOS ||
      Platform.isWindows ||
      Platform.isLinux ||
      Platform.isMacOS;

  static Future<Map<String, Object?>> invoke(
    String method,
    Map<String, Object?> arguments, {
    String? libraryPath,
  }) => Isolate.run(() {
    final bindings = _Bindings(_openLibrary(libraryPath));
    final source = arguments['source'] as String;
    // Prepare-only validation is isolated by construction: it never opens a
    // caller database. A supplied path is refused so a wiring mistake cannot
    // turn diagnostics into a write against user data.
    if (method == 'validate') {
      final path = arguments['databasePath'];
      if (path != null && path != '' && path != ':memory:') {
        throw ArgumentError.value(
          path,
          'databasePath',
          'Prepare-only SQL validation never opens a user database.',
        );
      }
      if (source.contains('\x00')) {
        throw const FormatException('SQL source cannot contain NUL.');
      }
      if (source.length > 512 * 1024) {
        throw const FormatException(
          'SQL source exceeds the syntax-check limit.',
        );
      }
      return using((arena) => bindings.validate(arena, source));
    }
    final databasePath = arguments['databasePath'] as String;
    if (source.contains('\x00') || databasePath.contains('\x00')) {
      throw const FormatException(
        'SQL source and database path cannot contain NUL.',
      );
    }
    return using((arena) {
      final sql = source.toNativeUtf8(allocator: arena);
      final path = databasePath.toNativeUtf8(allocator: arena);
      if (method == 'execute') {
        final result = arena<_ScriptResult>();
        try {
          if (bindings.execute(sql, path, 1024 * 1024, result) == 0) {
            throw StateError('SQLite script invocation failed.');
          }
          return <String, Object?>{
            'available': result.ref.available != 0,
            'exitCode': result.ref.exitCode,
            'output': _text(result.ref.output),
            'error': _text(result.ref.error),
            'truncated': result.ref.truncated != 0,
          };
        } finally {
          bindings.freeResult(result);
        }
      }
      if (method == 'executeScript') return bindings.script(arena, path, sql);
      if (method != 'query') throw ArgumentError.value(method, 'method');
      return bindings.query(
        arena,
        path,
        sql,
        (arguments['params'] as List?)?.cast<String?>() ?? const [],
      );
    });
  });

  static String _text(Pointer<Utf8> value, {int? length}) =>
      value == nullptr ? '' : value.toDartString(length: length);
}

DynamicLibrary _openLibrary(String? explicitPath) {
  final configured =
      explicitPath ?? Platform.environment['QFLI_SQLITE_LIBRARY'];
  if (configured != null) return DynamicLibrary.open(configured);
  if (Platform.isIOS || Platform.isMacOS) return DynamicLibrary.process();
  final name = Platform.isWindows ? 'qfli_sqlite.dll' : 'libqfli_sqlite.so';
  if (Platform.isAndroid) return DynamicLibrary.open(name);
  final app = p.dirname(Platform.resolvedExecutable);
  for (final path in [
    p.join(app, name),
    p.join(app, 'lib', name),
    p.join(
      Directory.current.path,
      'native',
      'build',
      Platform.operatingSystem,
      name,
    ),
  ]) {
    if (File(path).existsSync()) return DynamicLibrary.open(path);
  }
  throw StateError('The bundled SQLite C library was not found.');
}

class _Bindings {
  _Bindings(DynamicLibrary library)
    : execute = library
          .lookupFunction<
            Int32 Function(
              Pointer<Utf8>,
              Pointer<Utf8>,
              Size,
              Pointer<_ScriptResult>,
            ),
            int Function(
              Pointer<Utf8>,
              Pointer<Utf8>,
              int,
              Pointer<_ScriptResult>,
            )
          >('qfli_sql_execute'),
      freeResult = library
          .lookupFunction<
            Void Function(Pointer<_ScriptResult>),
            void Function(Pointer<_ScriptResult>)
          >('qfli_sql_result_free'),
      open = library
          .lookupFunction<
            Int32 Function(
              Pointer<Utf8>,
              Pointer<Pointer<Void>>,
              Int32,
              Pointer<Utf8>,
            ),
            int Function(
              Pointer<Utf8>,
              Pointer<Pointer<Void>>,
              int,
              Pointer<Utf8>,
            )
          >('sqlite3_open_v2'),
      close = library
          .lookupFunction<
            Int32 Function(Pointer<Void>),
            int Function(Pointer<Void>)
          >('sqlite3_close'),
      busyTimeout = library
          .lookupFunction<
            Int32 Function(Pointer<Void>, Int32),
            int Function(Pointer<Void>, int)
          >('sqlite3_busy_timeout'),
      setAuthorizer = library
          .lookupFunction<
            Int32 Function(
              Pointer<Void>,
              Pointer<NativeFunction<_ValidationAuthorizer>>,
              Pointer<Void>,
            ),
            int Function(
              Pointer<Void>,
              Pointer<NativeFunction<_ValidationAuthorizer>>,
              Pointer<Void>,
            )
          >('sqlite3_set_authorizer'),
      prepare = library
          .lookupFunction<
            Int32 Function(
              Pointer<Void>,
              Pointer<Utf8>,
              Int32,
              Pointer<Pointer<Void>>,
              Pointer<Pointer<Utf8>>,
            ),
            int Function(
              Pointer<Void>,
              Pointer<Utf8>,
              int,
              Pointer<Pointer<Void>>,
              Pointer<Pointer<Utf8>>,
            )
          >('sqlite3_prepare_v2'),
      step = library
          .lookupFunction<
            Int32 Function(Pointer<Void>),
            int Function(Pointer<Void>)
          >('sqlite3_step'),
      finalize = library
          .lookupFunction<
            Int32 Function(Pointer<Void>),
            int Function(Pointer<Void>)
          >('sqlite3_finalize'),
      parameterCount = library
          .lookupFunction<
            Int32 Function(Pointer<Void>),
            int Function(Pointer<Void>)
          >('sqlite3_bind_parameter_count'),
      bindNull = library
          .lookupFunction<
            Int32 Function(Pointer<Void>, Int32),
            int Function(Pointer<Void>, int)
          >('sqlite3_bind_null'),
      bindText = library
          .lookupFunction<
            Int32 Function(
              Pointer<Void>,
              Int32,
              Pointer<Utf8>,
              Int32,
              Pointer<Void>,
            ),
            int Function(Pointer<Void>, int, Pointer<Utf8>, int, Pointer<Void>)
          >('sqlite3_bind_text'),
      columnCount = library
          .lookupFunction<
            Int32 Function(Pointer<Void>),
            int Function(Pointer<Void>)
          >('sqlite3_column_count'),
      columnName = library
          .lookupFunction<
            Pointer<Utf8> Function(Pointer<Void>, Int32),
            Pointer<Utf8> Function(Pointer<Void>, int)
          >('sqlite3_column_name'),
      columnType = library
          .lookupFunction<
            Int32 Function(Pointer<Void>, Int32),
            int Function(Pointer<Void>, int)
          >('sqlite3_column_type'),
      columnText = library
          .lookupFunction<
            Pointer<Utf8> Function(Pointer<Void>, Int32),
            Pointer<Utf8> Function(Pointer<Void>, int)
          >('sqlite3_column_text'),
      columnBytes = library
          .lookupFunction<
            Int32 Function(Pointer<Void>, Int32),
            int Function(Pointer<Void>, int)
          >('sqlite3_column_bytes'),
      changes = library
          .lookupFunction<
            Int32 Function(Pointer<Void>),
            int Function(Pointer<Void>)
          >('sqlite3_changes'),
      errorMessage = library
          .lookupFunction<
            Pointer<Utf8> Function(Pointer<Void>),
            Pointer<Utf8> Function(Pointer<Void>)
          >('sqlite3_errmsg'),
      libraryVersion = library
          .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
            'sqlite3_libversion',
          ),
      // `sqlite3_error_offset` exists since SQLite 3.38. Older libraries (for
      // example a process-image SQLite) simply report no precise offset.
      errorOffset = _optionalIntQuery(library, 'sqlite3_error_offset');

  final int Function(Pointer<Utf8>, Pointer<Utf8>, int, Pointer<_ScriptResult>)
  execute;
  final void Function(Pointer<_ScriptResult>) freeResult;
  final int Function(Pointer<Utf8>, Pointer<Pointer<Void>>, int, Pointer<Utf8>)
  open;
  final int Function(Pointer<Void>) close,
      step,
      finalize,
      parameterCount,
      columnCount,
      changes;
  final int Function(Pointer<Void>, int) busyTimeout,
      bindNull,
      columnType,
      columnBytes;
  final int Function(
    Pointer<Void>,
    Pointer<NativeFunction<_ValidationAuthorizer>>,
    Pointer<Void>,
  )
  setAuthorizer;
  final int Function(
    Pointer<Void>,
    Pointer<Utf8>,
    int,
    Pointer<Pointer<Void>>,
    Pointer<Pointer<Utf8>>,
  )
  prepare;
  final int Function(Pointer<Void>, int, Pointer<Utf8>, int, Pointer<Void>)
  bindText;
  final Pointer<Utf8> Function(Pointer<Void>, int) columnName, columnText;
  final Pointer<Utf8> Function(Pointer<Void>) errorMessage;
  final Pointer<Utf8> Function() libraryVersion;
  final int Function(Pointer<Void>)? errorOffset;

  Map<String, Object?> query(
    Arena arena,
    Pointer<Utf8> path,
    Pointer<Utf8> source,
    List<String?> parameters,
  ) {
    final database = arena<Pointer<Void>>();
    try {
      final failure = _open(path, database);
      if (failure != null) return failure;
      return _statement(
        arena,
        database.value,
        source,
        parameters,
        _Budget(),
      ).result;
    } finally {
      if (database.value != nullptr) close(database.value);
    }
  }

  /// Prepare-only syntax validation against a throwaway in-memory database.
  ///
  /// Never calls `sqlite3_step`, never opens a caller database, and refuses the
  /// statements whose preparation can have side effects. Statements that only
  /// fail because the isolated schema is empty are counted as schema gaps, not
  /// as syntax errors, and an engine failure is reported instead of "clean".
  Map<String, Object?> validate(Arena arena, String source) {
    final version = SqliteFfi._text(libraryVersion());
    final bytes = utf8.encode(source);
    final input = source.toNativeUtf8(allocator: arena);
    final database = arena<Pointer<Void>>();
    final memory = ':memory:'.toNativeUtf8(allocator: arena);
    final issues = <Map<String, Object?>>[];
    final skipped = <Map<String, Object?>>[];
    var statements = 0;
    var checked = 0;
    var schemaGaps = 0;
    var truncated = false;

    void skipRemaining(int cursor, String keyword, String reason) {
      truncated = true;
      skipped.add({
        'startOffset': _utf16Length(bytes, cursor),
        'endOffset': source.length,
        'keyword': keyword,
        'reason': '$reason；此范围及其后续 SQL 未完整检查',
      });
    }

    try {
      if (open(memory, database, 6, nullptr) != 0) {
        return _validationError(
          version,
          0,
          database.value == nullptr
              ? 'SQLite 隔离数据库打开失败'
              : SqliteFfi._text(errorMessage(database.value)),
        );
      }
      final authorizer = Pointer.fromFunction<_ValidationAuthorizer>(
        _denyValidationEffects,
        1,
      );
      if (setAuthorizer(database.value, authorizer, nullptr) != 0) {
        return _validationError(version, 0, 'SQLite 隔离校验防护无法启用');
      }

      var cursor = 0;
      var attempts = 0;
      final elapsed = Stopwatch()..start();
      while (true) {
        cursor = _skipValidationTrivia(bytes, cursor);
        if (cursor >= bytes.length) break;
        final keyword = _validationKeyword(bytes, cursor);
        if (attempts >= 512 || elapsed.elapsedMilliseconds >= 250) {
          // The unparsed remainder is one discovered range, not a fabricated
          // count of every SQL statement it might contain.
          statements++;
          skipRemaining(cursor, keyword, '引擎达到语句数量或时间上限');
          break;
        }
        attempts++;
        final blockedReason = SqlPrepareGuard.blockedKeywords[keyword];
        if (blockedReason != null) {
          statements++;
          // Without preparing this statement there is no authoritative tail.
          // Never guess a separator and resume at SQL inside a literal/body.
          skipRemaining(cursor, keyword, blockedReason);
          break;
        }

        final start = Pointer<Utf8>.fromAddress(input.address + cursor);
        final handle = arena<Pointer<Void>>();
        final tail = arena<Pointer<Utf8>>();
        final code = prepare(
          database.value,
          start,
          bytes.length - cursor,
          handle,
          tail,
        );
        // Finalization can alter the connection error state. Capture all
        // preparation diagnostics before releasing the statement handle.
        final message = SqliteFfi._text(errorMessage(database.value));
        final rawOffset = errorOffset?.call(database.value) ?? -1;
        final hasStatement = handle.value != nullptr;
        if (hasStatement) finalize(handle.value);
        if (code == 0 && !hasStatement) break;
        statements++;
        checked++;
        if (code != 0) {
          String reason;
          if (code == 23 || message.contains('not authorized')) {
            reason = '隔离校验已拒绝可能访问外部状态的操作';
          } else if (_isSchemaGap(message)) {
            schemaGaps++;
            reason = '隔离校验库缺少 schema 上下文：$message';
          } else if (_isSyntaxFailure(code, message)) {
            final position = _utf16Length(
              bytes,
              rawOffset < 0 ? cursor : cursor + rawOffset,
            );
            issues.add({
              'startOffset': position,
              'endOffset': position,
              'message': message,
              'code': rawOffset < 0 ? 'sqlite-syntax' : 'sqlite-syntax-offset',
              'severity': 'error',
            });
            reason = 'SQLite 发现语法错误';
          } else {
            reason = 'SQLite 无法完成隔离解析：$message';
          }
          // An error tail is not necessarily a complete statement boundary.
          skipRemaining(cursor, keyword, reason);
          break;
        }
        final next = tail.value.address - input.address;
        if (tail.value == nullptr || next <= cursor || next > bytes.length) {
          skipRemaining(cursor, keyword, 'SQLite 未返回有效的后续语句边界');
          break;
        }
        cursor = next;
      }
    } finally {
      if (database.value != nullptr) close(database.value);
    }
    return {
      'available': true,
      'engine': 'sqlite',
      'version': version,
      'statements': statements,
      'checked': checked,
      'schemaGaps': schemaGaps,
      'truncated': truncated,
      'issues': issues,
      'skipped': skipped,
      'error': '',
    };
  }

  /// Engine-level failure: nothing was checked, so no clean result is possible.
  Map<String, Object?> _validationError(
    String version,
    int statements,
    String message,
  ) => {
    'available': false,
    'engine': 'sqlite',
    'version': version,
    'statements': statements,
    'checked': 0,
    'schemaGaps': 0,
    'truncated': false,
    'issues': <Map<String, Object?>>[],
    'skipped': <Map<String, Object?>>[],
    'error': message,
  };

  Map<String, Object?> script(
    Arena arena,
    Pointer<Utf8> path,
    Pointer<Utf8> source,
  ) {
    final database = arena<Pointer<Void>>();
    final results = <Map<String, Object?>>[];
    var summary = _emptyResult();
    try {
      final failure = _open(path, database);
      if (failure != null) return {...failure, 'results': results};
      var remaining = source;
      final budget = _Budget();
      while (SqliteFfi._text(remaining).trim().isNotEmpty) {
        final item = _statement(
          arena,
          database.value,
          remaining,
          const [],
          budget,
          allowTrailing: true,
          allowExecution: results.length < 512,
        );
        if (!item.hasStatement && item.result['exitCode'] == 0) break;
        summary = item.result;
        if (item.hasStatement && results.length < 512) results.add(summary);
        if (summary['truncated'] == true) {
          summary = {
            ...summary,
            'exitCode': 1,
            'error': 'SQL script output exceeds the display limits.',
          };
        }
        if (summary['exitCode'] != 0 ||
            summary['truncated'] == true ||
            item.tail == nullptr ||
            item.tail.address <= remaining.address) {
          break;
        }
        remaining = item.tail;
      }
      return {...summary, 'results': results};
    } finally {
      if (database.value != nullptr) close(database.value);
    }
  }

  Map<String, Object?>? _open(
    Pointer<Utf8> path,
    Pointer<Pointer<Void>> database,
  ) {
    if (open(path, database, 6, nullptr) != 0) {
      return {
        ..._emptyResult(),
        'exitCode': 1,
        'error': database.value == nullptr
            ? 'SQLite database open failed.'
            : SqliteFfi._text(errorMessage(database.value)),
      };
    }
    busyTimeout(database.value, 3000);
    return null;
  }

  ({Map<String, Object?> result, Pointer<Utf8> tail, bool hasStatement})
  _statement(
    Arena arena,
    Pointer<Void> database,
    Pointer<Utf8> source,
    List<String?> parameters,
    _Budget budget, {
    bool allowTrailing = false,
    bool allowExecution = true,
  }) {
    final statement = arena<Pointer<Void>>();
    final tail = arena<Pointer<Utf8>>();
    final columns = <String>[];
    final rows = <List<String?>>[];
    var affectedRows = 0;
    var truncated = false;
    var error = '';
    var hasStatement = false;
    try {
      do {
        if (prepare(database, source, -1, statement, tail) != 0) {
          error = SqliteFfi._text(errorMessage(database));
          break;
        }
        hasStatement = statement.value != nullptr;
        if (!allowTrailing && SqliteFfi._text(tail.value).trim().isNotEmpty) {
          error = 'Only one SQL statement is allowed in a grid query.';
          break;
        }
        if (statement.value == nullptr) {
          if (parameters.isNotEmpty) {
            error = 'SQL parameter count does not match the supplied values.';
          }
          break;
        }
        // SQLite distinguishes real statements from trailing comments and
        // empty separators. Refuse only an actual extra statement, before step;
        // the finally block still finalizes its prepared handle.
        if (!allowExecution) {
          error = 'SQL script exceeds the 512 statement limit.';
          break;
        }
        if (parameters.length != parameterCount(statement.value)) {
          error = 'SQL parameter count does not match the supplied values.';
          break;
        }
        for (var index = 0; index < parameters.length; index++) {
          final value = parameters[index];
          final code = value == null
              ? bindNull(statement.value, index + 1)
              : bindText(
                  statement.value,
                  index + 1,
                  value.toNativeUtf8(allocator: arena),
                  utf8.encode(value).length,
                  Pointer<Void>.fromAddress(-1),
                );
          if (code != 0) {
            error = SqliteFfi._text(errorMessage(database));
            break;
          }
        }
        if (error.isNotEmpty) break;
        final count = columnCount(statement.value);
        for (var index = 0; index < count; index++) {
          columns.add(SqliteFfi._text(columnName(statement.value, index)));
        }
        while (true) {
          final code = step(statement.value);
          if (code == 101) {
            affectedRows = count == 0 ? changes(database) : 0;
            break;
          }
          if (code != 100) {
            error = SqliteFfi._text(errorMessage(database));
            break;
          }
          if (budget.rows >= 500) {
            truncated = true;
            break;
          }
          final row = <String?>[];
          for (var index = 0; index < count; index++) {
            if (columnType(statement.value, index) == 5) {
              row.add(null);
              continue;
            }
            final text = columnText(statement.value, index);
            final length = columnBytes(statement.value, index);
            if (text == nullptr || budget.bytes + length > 1024 * 1024) {
              truncated = true;
              break;
            }
            budget.bytes += length;
            row.add(SqliteFfi._text(text, length: length));
          }
          if (truncated) break;
          rows.add(row);
          budget.rows++;
        }
      } while (false);
    } finally {
      if (statement.value != nullptr) finalize(statement.value);
    }
    return (
      tail: tail.value,
      hasStatement: hasStatement,
      result: {
        'available': true,
        'exitCode': error.isEmpty ? 0 : 1,
        'error': error,
        'columns': columns,
        'rows': rows,
        'affectedRows': affectedRows,
        'truncated': truncated,
      },
    );
  }
}

/// Looks up an optional scalar `int sqlite3_x(sqlite3*)` entry point.
int Function(Pointer<Void>)? _optionalIntQuery(
  DynamicLibrary library,
  String symbol,
) {
  try {
    return library.lookupFunction<
      Int32 Function(Pointer<Void>),
      int Function(Pointer<Void>)
    >(symbol);
  } on Object {
    return null;
  }
}

/// Errors that only mean "the isolated schema does not have this object yet".
/// They do not prove the SQL text is invalid, so they are never reported as
/// syntax failures and never presented as a clean result.
bool _isSchemaGap(String message) {
  final text = message.toLowerCase();
  const markers = [
    'no such table',
    'no such column',
    'no such function',
    'no such collation sequence',
    'no such index',
    'no such trigger',
    'no such view',
    'has no column named',
    'unknown database',
    'no such module',
  ];
  return markers.any(text.contains);
}

bool _isSyntaxFailure(int code, String message) {
  if (code != 1) return false; // SQLITE_ERROR
  final text = message.toLowerCase();
  return text.contains('syntax error') ||
      text.contains('unrecognized token') ||
      text == 'incomplete input';
}

// Only leading trivia is skipped here. SQLite's prepare tail is the sole
// statement boundary, including for triggers and quoted semicolons.
int _skipValidationTrivia(
  List<int> bytes,
  int cursor, {
  bool separators = true,
}) {
  while (cursor < bytes.length) {
    final byte = bytes[cursor];
    if (byte == 0x20 ||
        (byte >= 0x09 && byte <= 0x0D) ||
        (separators && byte == 0x3B)) {
      cursor++;
    } else if (byte == 0x2D &&
        cursor + 1 < bytes.length &&
        bytes[cursor + 1] == 0x2D) {
      cursor += 2;
      while (cursor < bytes.length && bytes[cursor] != 0x0A) {
        cursor++;
      }
    } else if (byte == 0x2F &&
        cursor + 1 < bytes.length &&
        bytes[cursor + 1] == 0x2A) {
      cursor += 2;
      while (cursor + 1 < bytes.length &&
          !(bytes[cursor] == 0x2A && bytes[cursor + 1] == 0x2F)) {
        cursor++;
      }
      cursor = cursor + 1 < bytes.length ? cursor + 2 : bytes.length;
    } else {
      break;
    }
  }
  return cursor;
}

// A prefix check can refuse a dangerous statement, but never supplies its end.
// The authorizer remains the guard for every statement sent to SQLite.
String _validationKeyword(List<int> bytes, int cursor) {
  for (var prefix = 0; prefix < 4; prefix++) {
    cursor = _skipValidationTrivia(bytes, cursor, separators: false);
    final start = cursor;
    while (cursor < bytes.length &&
        ((bytes[cursor] >= 0x41 && bytes[cursor] <= 0x5A) ||
            (bytes[cursor] >= 0x61 && bytes[cursor] <= 0x7A))) {
      cursor++;
    }
    if (cursor == start) return '';
    if (cursor < bytes.length) {
      final next = bytes[cursor];
      if ((next >= 0x30 && next <= 0x39) ||
          next == 0x5F ||
          next == 0x24 ||
          next >= 0x80) {
        return ''; // An identifier beginning with a keyword is not that keyword.
      }
    }
    final keyword = String.fromCharCodes(
      bytes.sublist(start, cursor),
    ).toUpperCase();
    if (!const {'EXPLAIN', 'QUERY', 'PLAN'}.contains(keyword)) return keyword;
  }
  return '';
}

/// Converts a UTF-8 **byte** offset into a UTF-16 code-unit offset.
///
/// `sqlite3_error_offset` reports bytes; the editor contract is UTF-16 with CRLF
/// counted as two code units. A malformed prefix (only possible for an engine
/// bug) yields the last valid boundary so the range can never exceed the text.
int _utf16Length(List<int> bytes, int byteOffset) {
  final limit = byteOffset.clamp(0, bytes.length);
  var units = 0;
  var index = 0;
  while (index < limit) {
    final byte = bytes[index];
    if (byte < 0x80) {
      units++;
      index++;
    } else if (byte >= 0xC2 && byte <= 0xDF && index + 1 < limit) {
      units++;
      index += 2;
    } else if (byte >= 0xE0 && byte <= 0xEF && index + 2 < limit) {
      units++;
      index += 3;
    } else if (byte >= 0xF0 && byte <= 0xF4 && index + 3 < limit) {
      units += 2;
      index += 4;
    } else {
      break;
    }
  }
  return units;
}

Map<String, Object?> _emptyResult() => {
  'available': true,
  'exitCode': 0,
  'error': '',
  'columns': <String>[],
  'rows': <List<String?>>[],
  'affectedRows': 0,
  'truncated': false,
};

class _Budget {
  int rows = 0;
  int bytes = 0;
}
