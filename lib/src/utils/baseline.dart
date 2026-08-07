import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/analysis_issue.dart';
import '../models/health_report.dart';

/// Fingerprint helpers and baseline persistence for incremental adoption.
class BaselineStore {
  const BaselineStore();

  /// Stable fingerprint for an issue (path + rule + message).
  static String fingerprint(AnalysisIssue issue) {
    final path = issue.filePath ?? '';
    return '${issue.ruleId}|$path|${issue.message}'.hashCode.toRadixString(16);
  }

  Future<Set<String>> load(String absolutePath) async {
    final file = File(absolutePath);
    if (!await file.exists()) return {};
    try {
      final json = jsonDecode(await file.readAsString());
      if (json is Map<String, dynamic>) {
        final list = json['fingerprints'];
        if (list is List) {
          return list.map((e) => '$e').toSet();
        }
      }
      if (json is List) {
        return json.map((e) => '$e').toSet();
      }
    } on Exception {
      return {};
    }
    return {};
  }

  Future<void> save(String absolutePath, HealthReport report) async {
    final file = File(absolutePath);
    await file.parent.create(recursive: true);
    final fingerprints =
        report.allIssues.map(fingerprint).toSet().toList()..sort();
    final payload = {
      'version': 1,
      'generatedAt': DateTime.now().toIso8601String(),
      'project': report.projectName,
      'issueCount': fingerprints.length,
      'fingerprints': fingerprints,
    };
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
    );
  }

  /// Keep only issues not present in [baseline].
  HealthReport filterNew(HealthReport report, Set<String> baseline) {
    if (baseline.isEmpty) return report;
    final filteredResults = report.results.map((result) {
      final issues = result.issues
          .where((i) => !baseline.contains(fingerprint(i)))
          .toList();
      return result.copyWith(issues: issues);
    }).toList();

    return HealthReport(
      projectName: report.projectName,
      projectPath: report.projectPath,
      results: filteredResults,
      generatedAt: report.generatedAt,
    );
  }

  String resolvePath(String projectPath, String relativeOrAbsolute) {
    if (p.isAbsolute(relativeOrAbsolute)) return relativeOrAbsolute;
    return p.join(projectPath, relativeOrAbsolute);
  }
}
