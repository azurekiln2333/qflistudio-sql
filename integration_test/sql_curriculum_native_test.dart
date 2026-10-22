import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:qfli_sql/sql_content_repository.dart';

import 'support/sql_curriculum_audit.dart';
import 'support/sql_curriculum_runtime.dart';
import 'support/sql_curriculum_support.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'every shipped native example and exercise has exhaustive evidence',
    (tester) async {
      final catalog = await SqlContentRepository(bundle: rootBundle).load();
      final cases = curriculumCases(catalog);
      final report = await runCurriculumAudit(
        cases: cases,
        platform: Platform.operatingSystem,
        platformVersion: Platform.operatingSystemVersion,
        sessionFactory: nativeCurriculumSession,
        checkpoint: (_, kind, details) async {
          debugPrintSynchronously(
            'QFLI_SQL_CURRICULUM_NATIVE $kind ${jsonEncode(details)}',
          );
        },
      );
      expect(report.cases.length, catalog.examples.length);
      expect(
        report.catalogGatePassed,
        isTrue,
        reason: jsonEncode(report.toJson()),
      );
    },
    timeout: const Timeout(Duration(minutes: 30)),
  );
}
