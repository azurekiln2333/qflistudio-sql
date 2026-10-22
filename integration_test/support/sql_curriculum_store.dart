import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/services/app_paths.dart';

import 'sql_curriculum_audit.dart';

const curriculumAuditMarker = 'QFLI_SQL_CURRICULUM_AUDIT';

/// AppPaths can fall back to a working directory. Phone evidence must instead
/// stay within the actual application sandbox, even when a plugin is missing.
Future<Directory> curriculumPrivateStorage() async {
  final path = await AppPaths.storageDirectory();
  if (path == null) throw StateError('App-private storage is unavailable.');
  final directory = Directory(await Directory(path).resolveSymbolicLinks());
  if (Platform.operatingSystem == 'ohos' &&
      (!p.posix.isWithin('/data/storage/el2/base', directory.path) ||
          !p.posix.split(directory.path).contains('files'))) {
    throw StateError(
      'Refusing non-private OHOS report storage: ${directory.path}',
    );
  }
  return directory;
}

/// Report files and append-only events are flushed before execution continues.
/// A unique run directory is never reused or removed by the audit.
class CurriculumAuditStore {
  CurriculumAuditStore._({
    required this.directory,
    required this.runId,
    required this.metadata,
    required this.writeLog,
    this.onEvent,
  });

  static Future<CurriculumAuditStore> create({
    required Directory storage,
    Map<String, Object?> metadata = const {},
    void Function(String)? writeLog,
    void Function(String)? onEvent,
  }) async {
    final parent = await Directory(
      p.join(storage.path, 'sql-curriculum-audit'),
    ).create(recursive: true);
    final runId =
        '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}_'
        '${Random.secure().nextInt(0x7fffffff).toRadixString(16)}';
    final directory = await parent.createTemp('$runId-');
    return CurriculumAuditStore._(
      directory: directory,
      runId: p.basename(directory.path),
      metadata: Map.unmodifiable(metadata),
      writeLog: writeLog ?? debugPrintSynchronously,
      onEvent: onEvent,
    );
  }

  final Directory directory;
  final String runId;
  final Map<String, Object?> metadata;
  final void Function(String) writeLog;
  final void Function(String)? onEvent;
  int _sequence = 0;

  File get reportFile => File(p.join(directory.path, 'report.json'));
  File get eventFile => File(p.join(directory.path, 'events.jsonl'));

  Map<String, Object?> _document(CurriculumAuditReport report) => {
    ...report.toJson(),
    'runId': runId,
    'reportPath': reportFile.path,
    'eventPath': eventFile.path,
    'build': metadata,
  };

  Future<void> checkpoint(
    CurriculumAuditReport report,
    String kind,
    Map<String, Object?> details,
  ) async {
    await _event(kind, details, document: _document(report));
  }

  Future<void> _writeReport(Map<String, Object?> document) async {
    final pending = File('${reportFile.path}.tmp');
    await pending.writeAsString(jsonEncode(document), flush: true);
    await pending.rename(reportFile.path);
  }

  Future<void> setupFailure(Object error, StackTrace stack) async {
    final failure = {
      'formatVersion': 1,
      'audit': curriculumAuditMarker,
      'runId': runId,
      'reportPath': reportFile.path,
      'status': 'fail',
      'catalogGatePassed': false,
      'deviceGatePassed': false,
      'denominatorAvailable': false,
      'fatalError': error.toString(),
      'stackTrace': stack.toString(),
      'build': metadata,
    };
    await _writeReport(failure);
    await _event('SETUP_FAIL', failure);
  }

  /// The full final JSON is also reconstructable from numbered log chunks.
  /// Its persistent copy remains authoritative if the device log ring wraps.
  Future<void> emitReport(CurriculumAuditReport report) async {
    final document = _document(report);
    try {
      await _event('REPORT', document, document: document);
    } on Object catch (error) {
      // Disk exhaustion must not prevent recovery through the independent
      // device log. This is explicitly log-only evidence of the failed run.
      final event = {
        'runId': runId,
        'sequence': ++_sequence,
        'kind': 'REPORT',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'reportPath': reportFile.path,
        'logOnly': true,
        'persistError': error.toString(),
        'details': document,
      };
      _log('REPORT', event, jsonEncode(event));
      rethrow;
    }
  }

  Future<void> _event(
    String kind,
    Map<String, Object?> details, {
    Map<String, Object?>? document,
  }) async {
    final event = {
      'runId': runId,
      'sequence': ++_sequence,
      'kind': kind,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'reportPath': reportFile.path,
      'details': details,
    };
    final payload = jsonEncode(event);
    await eventFile.writeAsString(
      '$payload\n',
      mode: FileMode.append,
      flush: true,
    );
    // The report is authoritative. Persist its event first, so a failed append
    // can never leave a newly published PASS report on disk.
    if (document != null) await _writeReport(document);
    _log(kind, event, payload);
    onEvent?.call(
      kind == 'REPORT'
          ? 'REPORT saved to ${reportFile.path}; ${payload.length} JSON characters'
          : '$kind ${jsonEncode(details)}',
    );
  }

  void _log(String kind, Map<String, Object?> event, String payload) {
    if (utf8.encode(payload).length <= 2800) {
      writeLog('$curriculumAuditMarker $kind $payload');
      return;
    }
    final chunks = <String>[];
    for (var start = 0; start < payload.length;) {
      var end = min(start + 400, payload.length);
      // Never cut a Unicode surrogate pair in half between JSON chunks.
      if (end < payload.length &&
          payload.codeUnitAt(end - 1) >= 0xd800 &&
          payload.codeUnitAt(end - 1) <= 0xdbff) {
        end--;
      }
      chunks.add(payload.substring(start, end));
      start = end;
    }
    writeLog(
      '$curriculumAuditMarker $kind ${jsonEncode({'runId': runId, 'sequence': event['sequence'], 'reportPath': reportFile.path, 'chunked': true, 'parts': chunks.length})}',
    );
    for (var index = 0; index < chunks.length; index++) {
      writeLog(
        '$curriculumAuditMarker DETAIL ${jsonEncode({'runId': runId, 'sequence': event['sequence'], 'kind': kind, 'part': index + 1, 'parts': chunks.length, 'jsonChunk': chunks[index]})}',
      );
    }
  }
}
