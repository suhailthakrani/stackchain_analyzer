import '../analyzers/analyzer.dart';
import '../analyzers/analyzer_registry.dart';
import '../models/health_report.dart';
import '../models/project_context.dart';
import '../reporters/ci_reporter.dart';
import '../reporters/console_reporter.dart';
import '../reporters/json_reporter.dart';
import '../reporters/reporter.dart';
import '../utils/exit_codes.dart';
import '../utils/project_detector.dart';

/// Orchestrates project detection, analysis, and reporting.
class AnalysisEngine {
  AnalysisEngine({
    ProjectDetector? detector,
    AnalyzerRegistry? registry,
  })  : _detector = detector ?? ProjectDetector(),
        _registry = registry ?? AnalyzerRegistry();

  final ProjectDetector _detector;
  final AnalyzerRegistry _registry;

  AnalyzerRegistry get registry => _registry;

  /// Run selected analyzers and return a [HealthReport].
  Future<HealthReport> run({
    required String projectPath,
    List<String> analyzerIds = const [],
  }) async {
    final context = await _detector.load(projectPath);
    final analyzers = _registry.resolve(analyzerIds);
    return _analyze(context, analyzers);
  }

  Future<HealthReport> _analyze(
    ProjectContext context,
    List<Analyzer> analyzers,
  ) async {
    final results = [
      for (final analyzer in analyzers) await analyzer.analyze(context),
    ];

    return HealthReport(
      projectName: context.projectName,
      projectPath: context.rootPath,
      results: results,
    );
  }

  Reporter createReporter({
    required ReportFormat format,
    bool color = true,
    bool verbose = false,
  }) {
    return switch (format) {
      ReportFormat.json => JsonReporter(),
      ReportFormat.ci => CiReporter(),
      ReportFormat.console => ConsoleReporter(
          color: color,
          verbose: verbose,
        ),
    };
  }

  /// Map report outcome to a process exit code.
  int exitCodeFor(HealthReport report, {bool failOnWarning = false}) {
    if (report.hasFailures) return ExitCodes.issuesFound;
    if (failOnWarning && report.warningCount > 0) {
      return ExitCodes.issuesFound;
    }
    return ExitCodes.success;
  }
}
