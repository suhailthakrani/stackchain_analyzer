import 'dart:io';

import '../models/analysis_issue.dart';
import '../models/health_report.dart';
import '../models/severity.dart';
import '../utils/ansi_colors.dart';
import '../utils/score_bar.dart';
import 'reporter.dart';

/// Beautiful terminal health report.
class ConsoleReporter implements Reporter {
  ConsoleReporter({
    IOSink? sink,
    this.color = true,
    this.verbose = false,
  }) : _sink = sink ?? stdout;

  final IOSink _sink;
  final bool color;
  final bool verbose;

  @override
  void write(HealthReport report) {
    final c = color;
    _sink.writeln();
    _sink.writeln(AnsiColors.bold(AnsiColors.cyan('StackChain Analyzer', enabled: c), enabled: c));
    _sink.writeln(AnsiColors.dim('─' * 40, enabled: c));
    _sink.writeln();
    _sink.writeln('${AnsiColors.bold('Project:', enabled: c)} ${report.projectName}');
    _sink.writeln(AnsiColors.dim(report.projectPath, enabled: c));
    _sink.writeln();
    _sink.writeln(AnsiColors.bold('Health Score:', enabled: c));
    _sink.writeln();

    final maxName = report.results.fold<int>(
      0,
      (m, r) => r.analyzerName.length > m ? r.analyzerName.length : m,
    );

    for (final result in report.results) {
      final pad = ' ' * (maxName - result.analyzerName.length + 2);
      final bar = ScoreBar.render(result.score);
      final scoreColor = _scoreColor(result.score, c);
      _sink.writeln(
        '  ${result.analyzerName}$pad$bar ${scoreColor('${result.score}')}',
      );
    }

    _sink.writeln();
    final overall = report.overallScore;
    _sink.writeln(
      '  ${AnsiColors.bold('Overall', enabled: c)}       '
      '${ScoreBar.render(overall)} ${_scoreColor(overall, c)('$overall')}',
    );
    _sink.writeln();
    _sink.writeln(AnsiColors.dim('─' * 40, enabled: c));
    _sink.writeln();
    _sink.writeln(
      AnsiColors.bold('${report.totalIssues} Issues Found', enabled: c),
    );
    _sink.writeln();
    _sink.writeln(
      '  ${AnsiColors.red('Critical', enabled: c)}: ${report.criticalCount}',
    );
    _sink.writeln(
      '  ${AnsiColors.red('Error', enabled: c)}:    ${report.errorCount}',
    );
    _sink.writeln(
      '  ${AnsiColors.yellow('Warning', enabled: c)}:  ${report.warningCount}',
    );
    _sink.writeln(
      '  ${AnsiColors.blue('Info', enabled: c)}:     ${report.infoCount}',
    );
    _sink.writeln();

    if (report.allIssues.isEmpty) {
      _sink.writeln(AnsiColors.green('✓ No issues detected.', enabled: c));
      _sink.writeln();
      return;
    }

    // Group by analyzer
    for (final result in report.results) {
      if (result.issues.isEmpty) continue;
      _sink.writeln(AnsiColors.bold(result.analyzerName, enabled: c));
      _sink.writeln(AnsiColors.dim('─' * result.analyzerName.length, enabled: c));

      final sorted = [...result.issues]
        ..sort((a, b) => b.severity.weight.compareTo(a.severity.weight));

      for (final issue in sorted) {
        _writeIssue(issue, c);
        if (!verbose && issue.severity == Severity.info) {
          // still show info, but keep compact
        }
      }
      _sink.writeln();
    }
  }

  void _writeIssue(AnalysisIssue issue, bool c) {
    final label = _severityLabel(issue.severity, c);
    _sink.writeln();
    _sink.writeln('$label ${AnsiColors.dim(issue.ruleId, enabled: c)}');
    if (issue.filePath != null) {
      final loc = issue.line != null
          ? '${issue.filePath}:${issue.line}'
          : issue.filePath!;
      _sink.writeln('  ${AnsiColors.cyan(loc, enabled: c)}');
    }
    _sink.writeln('  ${issue.message}');
    if (issue.context != null) {
      _sink.writeln('  ${AnsiColors.dim(issue.context!, enabled: c)}');
    }
    if (issue.suggestion != null) {
      _sink.writeln(
        '  ${AnsiColors.green('Suggestion:', enabled: c)} ${issue.suggestion}',
      );
    }
  }

  String _severityLabel(Severity severity, bool c) {
    return switch (severity) {
      Severity.critical => AnsiColors.red('CRITICAL:', enabled: c),
      Severity.error => AnsiColors.red('ERROR:', enabled: c),
      Severity.warning => AnsiColors.yellow('WARNING:', enabled: c),
      Severity.info => AnsiColors.blue('INFO:', enabled: c),
    };
  }

  String Function(String) _scoreColor(int score, bool c) {
    if (score >= 80) return (s) => AnsiColors.green(s, enabled: c);
    if (score >= 60) return (s) => AnsiColors.yellow(s, enabled: c);
    return (s) => AnsiColors.red(s, enabled: c);
  }
}
