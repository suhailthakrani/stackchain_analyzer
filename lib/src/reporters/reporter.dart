import '../models/health_report.dart';

/// Output format for analysis reports.
enum ReportFormat {
  console,
  json,
  ci,
  sarif,
  badge;

  static ReportFormat parse(String value) {
    return ReportFormat.values.firstWhere(
      (f) => f.name == value.toLowerCase(),
      orElse: () => ReportFormat.console,
    );
  }
}

/// Contract for health report writers.
abstract class Reporter {
  void write(HealthReport report);
}
