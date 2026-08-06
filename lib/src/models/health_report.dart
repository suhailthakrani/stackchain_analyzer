import 'analysis_issue.dart';
import 'analysis_result.dart';
import 'severity.dart';

/// Aggregated health report across all analyzers.
class HealthReport {
  HealthReport({
    required this.projectName,
    required this.projectPath,
    required this.results,
    DateTime? generatedAt,
  }) : generatedAt = generatedAt ?? DateTime.now();

  final String projectName;
  final String projectPath;
  final List<AnalysisResult> results;
  final DateTime generatedAt;

  int get overallScore {
    if (results.isEmpty) return 0;
    final total = results.fold<int>(0, (sum, r) => sum + r.score);
    return (total / results.length).round();
  }

  List<AnalysisIssue> get allIssues =>
      results.expand((r) => r.issues).toList();

  int get totalIssues => allIssues.length;

  int get criticalCount =>
      allIssues.where((i) => i.severity == Severity.critical).length;

  int get errorCount =>
      allIssues.where((i) => i.severity == Severity.error).length;

  int get warningCount =>
      allIssues.where((i) => i.severity == Severity.warning).length;

  int get infoCount =>
      allIssues.where((i) => i.severity == Severity.info).length;

  bool get hasFailures => criticalCount > 0 || errorCount > 0;

  Map<String, dynamic> toJson() => {
        'project': projectName,
        'path': projectPath,
        'generatedAt': generatedAt.toIso8601String(),
        'healthScore': overallScore,
        'issueCounts': {
          'total': totalIssues,
          'critical': criticalCount,
          'error': errorCount,
          'warning': warningCount,
          'info': infoCount,
        },
        'analyzers': results.map((r) => r.toJson()).toList(),
      };
}
