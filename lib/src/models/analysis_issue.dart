import 'severity.dart';

/// A single finding produced by an analyzer.
class AnalysisIssue {
  const AnalysisIssue({
    required this.ruleId,
    required this.message,
    required this.severity,
    this.filePath,
    this.line,
    this.column,
    this.suggestion,
    this.context,
  });

  final String ruleId;
  final String message;
  final Severity severity;
  final String? filePath;
  final int? line;
  final int? column;
  final String? suggestion;
  final String? context;

  Map<String, dynamic> toJson() => {
        'ruleId': ruleId,
        'message': message,
        'severity': severity.name,
        if (filePath != null) 'filePath': filePath,
        if (line != null) 'line': line,
        if (column != null) 'column': column,
        if (suggestion != null) 'suggestion': suggestion,
        if (context != null) 'context': context,
      };

  factory AnalysisIssue.fromJson(Map<String, dynamic> json) {
    return AnalysisIssue(
      ruleId: json['ruleId'] as String,
      message: json['message'] as String,
      severity: Severity.fromString(json['severity'] as String),
      filePath: json['filePath'] as String?,
      line: json['line'] as int?,
      column: json['column'] as int?,
      suggestion: json['suggestion'] as String?,
      context: json['context'] as String?,
    );
  }

  @override
  String toString() {
    final loc = filePath != null
        ? '$filePath${line != null ? ':$line' : ''}'
        : '';
    return '[${severity.label}] $ruleId${loc.isNotEmpty ? ' ($loc)' : ''}: $message';
  }
}
