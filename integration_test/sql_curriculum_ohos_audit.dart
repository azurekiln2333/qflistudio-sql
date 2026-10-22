import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qfli_sql/sql_content_repository.dart';

import 'support/sql_curriculum_audit.dart';
import 'support/sql_curriculum_runtime.dart';
import 'support/sql_curriculum_store.dart';
import 'support/sql_curriculum_support.dart';

// Install this debug HAP manually. The normal Flutter binding preserves the
// real platform messenger and registered native plugins throughout the run.
const _engineFilter = String.fromEnvironment(
  'QFLI_SQL_CURRICULUM_ENGINES',
  defaultValue: 'sqlite,mysql',
);
const _buildId = String.fromEnvironment('QFLI_SQL_CURRICULUM_BUILD_ID');
const _sourceRevision = String.fromEnvironment('QFLI_SQL_CURRICULUM_REVISION');
const _toolchain = String.fromEnvironment('QFLI_SQL_CURRICULUM_TOOLCHAIN');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _CurriculumAuditApp());
}

class _CurriculumAuditApp extends StatefulWidget {
  const _CurriculumAuditApp();

  @override
  State<_CurriculumAuditApp> createState() => _CurriculumAuditAppState();
}

class _CurriculumAuditAppState extends State<_CurriculumAuditApp> {
  String _status = 'Preparing complete shipped-catalog audit';
  String? _reportPath;
  final _events = <String>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_run()));
  }

  void _event(String line) {
    if (!mounted) return;
    setState(() {
      // Keep the screen responsive; the full event history stays on disk.
      _events.add(line);
      if (_events.length > 60) _events.removeAt(0);
    });
  }

  Future<void> _run() async {
    CurriculumAuditStore? store;
    CurriculumAuditReport? report;
    try {
      store = await CurriculumAuditStore.create(
        storage: await curriculumPrivateStorage(),
        metadata: {
          'buildId': _buildId,
          'sourceRevision': _sourceRevision,
          'toolchain': _toolchain,
          'debug': kDebugMode,
          'dartVersion': Platform.version,
          'requestedEngines': _engineFilter,
        },
        onEvent: _event,
      );
      if (mounted) setState(() => _reportPath = store!.reportFile.path);
      final catalog = await SqlContentRepository(bundle: rootBundle).load();
      report = await runCurriculumAudit(
        cases: curriculumCases(catalog),
        platform: Platform.operatingSystem,
        platformVersion: Platform.operatingSystemVersion,
        selectedEngines: _engineFilter
            .split(',')
            .map((name) => name.trim())
            .where((name) => name.isNotEmpty)
            .toSet(),
        sessionFactory: nativeCurriculumSession,
        checkpoint: (current, kind, details) async {
          await store!.checkpoint(current, kind, details);
          if (!mounted) return;
          final summary = current.toJson();
          setState(
            () => _status =
                '${summary['passedScripts']} passed · '
                '${summary['failedScripts']} failed · '
                '${summary['notExecutedScripts']} not executed / '
                '${summary['catalogScripts']} required scripts',
          );
        },
      );
      await store.emitReport(report);
      if (mounted) {
        setState(
          () => _status = report!.deviceGatePassed
              ? 'PASS · complete OHOS curriculum gate'
              : 'FAIL · complete OHOS curriculum gate',
        );
      }
    } on Object catch (error, stack) {
      debugPrintSynchronously(
        '$curriculumAuditMarker FATAL ${jsonEncode({'error': error.toString(), 'stackTrace': stack.toString(), 'reportPath': store?.reportFile.path, if (report != null) 'report': report.toJson()})}',
      );
      if (report == null && store != null) {
        try {
          await store.setupFailure(error, stack);
        } on Object catch (storageError) {
          debugPrintSynchronously(
            '$curriculumAuditMarker REPORT_WRITE_FAIL $storageError',
          );
        }
      }
      if (mounted) setState(() => _status = 'FAIL · $error');
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(useMaterial3: true),
    home: Scaffold(
      appBar: AppBar(
        title: const Text('SQL · complete native curriculum audit'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(_status, style: const TextStyle(fontSize: 20)),
            const SizedBox(height: 12),
            SelectableText(
              'Report: ${_reportPath ?? 'preparing app-private directory'}',
            ),
            const SizedBox(height: 16),
            SelectableText(
              _events.join('\n\n'),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ],
        ),
      ),
    ),
  );
}
