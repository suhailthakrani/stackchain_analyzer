import 'dart:io';

import '../models/health_report.dart';
import 'reporter.dart';

/// Prints a Markdown shields.io-style badge line for README embedding.
class BadgeReporter implements Reporter {
  BadgeReporter({StringSink? sink}) : _sink = sink ?? stdout;

  final StringSink _sink;

  @override
  void write(HealthReport report) {
    final score = report.overallScore;
    final color = score >= 80
        ? 'brightgreen'
        : score >= 60
            ? 'yellow'
            : 'red';
    final label = Uri.encodeComponent('stackchain health');
    final message = Uri.encodeComponent('$score%');
    final url =
        'https://img.shields.io/badge/$label-$message-$color';
    _sink.writeln('![StackChain Health]($url)');
    _sink.writeln();
    _sink.writeln('<!-- score=$score project=${report.projectName} -->');
  }
}
