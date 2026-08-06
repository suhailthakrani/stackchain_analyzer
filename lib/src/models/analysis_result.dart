import 'analysis_issue.dart';
import 'severity.dart';

/// Result produced by a single analyzer plugin.
class AnalysisResult {
  const AnalysisResult({
    required this.analyzerName,
    required this.score,
    required this.issues,
    this.summary,
    this.metadata = const {},
  });

  final String analyzerName;

  /// Score from 0–100. Higher is healthier.
  final int score;
  final List<AnalysisIssue> issues;
  final String? summary;
  final Map<String, dynamic> metadata;

  int get criticalCount =>
      issues.where((i) => i.severity == Severity.critical).length;

  int get errorCount =>
      issues.where((i) => i.severity == Severity.error).length;

  int get warningCount =>
      issues.where((i) => i.severity == Severity.warning).length;

  int get infoCount =>
      issues.where((i) => i.severity == Severity.info).length;

  bool get hasFailures => criticalCount > 0 || errorCount > 0;

  Map<String, dynamic> toJson() => {
        'analyzer': analyzerName,
        'score': score,
        'summary': summary,
        'issueCounts': {
          'critical': criticalCount,
          'error': errorCount,
          'warning': warningCount,
          'info': infoCount,
        },
        'issues': issues.map((i) => i.toJson()).toList(),
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  /// Compute a score from issues, starting at [base] and subtracting weights.
  static int computeScore(
    List<AnalysisIssue> issues, {
    int base = 100,
  }) {
    var score = base;
    for (final issue in issues) {
      score -= issue.severity.weight;
    }
    return score.clamp(0, 100);
  }
}
