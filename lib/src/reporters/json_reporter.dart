import 'dart:convert';
import 'dart:io';

import '../models/health_report.dart';
import 'reporter.dart';

/// Machine-readable JSON reporter.
class JsonReporter implements Reporter {
  JsonReporter({IOSink? sink, this.pretty = true}) : _sink = sink ?? stdout;

  final IOSink _sink;
  final bool pretty;

  @override
  void write(HealthReport report) {
    final encoder = pretty
        ? const JsonEncoder.withIndent('  ')
        : const JsonEncoder();
    _sink.writeln(encoder.convert(report.toJson()));
  }
}
