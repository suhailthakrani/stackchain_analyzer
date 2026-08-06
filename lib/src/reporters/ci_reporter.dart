import 'dart:io';

import '../models/health_report.dart';
import '../models/severity.dart';
import '../utils/ansi_colors.dart';
import 'reporter.dart';

/// Compact CI/CD-friendly reporter (GitHub Actions annotations style).
class CiReporter implements Reporter {
  CiReporter({IOSink? sink}) : _sink = sink ?? stdout;

  final IOSink _sink;

  @override
  void write(HealthReport report) {
    _sink.writeln('::group::StackChain Analyzer — ${report.projectName}');
    _sink.writeln('health_score=${report.overallScore}');
    _sink.writeln('issues_total=${report.totalIssues}');
    _sink.writeln('issues_critical=${report.criticalCount}');
    _sink.writeln('issues_error=${report.errorCount}');
    _sink.writeln('issues_warning=${report.warningCount}');
    _sink.writeln('issues_info=${report.infoCount}');

    for (final result in report.results) {
      _sink.writeln(
        'analyzer_${result.analyzerName.toLowerCase()}_score=${result.score}',
      );
    }
    _sink.writeln('::endgroup::');

    for (final issue in report.allIssues) {
      final file = issue.filePath ?? 'unknown';
      final line = issue.line ?? 1;
      final level = switch (issue.severity) {
        Severity.critical || Severity.error => 'error',
        Severity.warning => 'warning',
        Severity.info => 'notice',
      };
      final message = issue.message.replaceAll('\n', ' ');
      _sink.writeln(
        '::$level file=$file,line=$line,title=${issue.ruleId}::$message',
      );
    }

    if (report.hasFailures) {
      _sink.writeln(
        AnsiColors.red('StackChain Analyzer: FAILED', enabled: false),
      );
    } else {
      _sink.writeln('StackChain Analyzer: PASSED');
    }
  }
}
