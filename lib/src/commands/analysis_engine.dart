import '../analyzers/analyzer.dart';
import '../analyzers/analyzer_registry.dart';
import '../config/stackchain_config.dart';
import '../models/analysis_issue.dart';
import '../models/analysis_result.dart';
import '../models/health_report.dart';
import '../models/project_context.dart';
import '../reporters/badge_reporter.dart';
import '../reporters/ci_reporter.dart';
import '../reporters/console_reporter.dart';
import '../reporters/json_reporter.dart';
import '../reporters/reporter.dart';
import '../reporters/sarif_reporter.dart';
import '../utils/baseline.dart';
import '../utils/exit_codes.dart';
import '../utils/project_detector.dart';

/// Orchestrates project detection, analysis, and reporting.
class AnalysisEngine {
  AnalysisEngine({
    ProjectDetector? detector,
    AnalyzerRegistry? registry,
    BaselineStore? baselineStore,
  })  : _detector = detector ?? ProjectDetector(),
        _registry = registry ?? AnalyzerRegistry(),
        _baseline = baselineStore ?? const BaselineStore();

  final ProjectDetector _detector;
  final AnalyzerRegistry _registry;
  final BaselineStore _baseline;

  AnalyzerRegistry get registry => _registry;

  /// Run selected analyzers and return a [HealthReport].
  Future<HealthReport> run({
    required String projectPath,
    List<String> analyzerIds = const [],
    StackChainConfig config = StackChainConfig.empty,
    bool useBaseline = false,
    bool updateBaseline = false,
  }) async {
    final context = await _detector.load(projectPath);
    final ids = config.resolveAnalyzerIds(analyzerIds);
    final analyzers = _registry.resolve(ids);
    var report = await _analyze(context, analyzers);
    report = _applyConfig(report, config);

    final baselineFile = _baseline.resolvePath(
      context.rootPath,
      config.baselinePath,
    );

    if (updateBaseline) {
      await _baseline.save(baselineFile, report);
    } else if (useBaseline) {
      final fingerprints = await _baseline.load(baselineFile);
      report = _baseline.filterNew(report, fingerprints);
    }

    return report;
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

  HealthReport _applyConfig(HealthReport report, StackChainConfig config) {
    final results = <AnalysisResult>[];
    for (final result in report.results) {
      final issues = <AnalysisIssue>[];
      for (final issue in result.issues) {
        if (config.isIgnored(
          ruleId: issue.ruleId,
          filePath: issue.filePath,
        )) {
          continue;
        }
        final override = config.severityOverrides[issue.ruleId];
        issues.add(
          override == null
              ? issue
              : AnalysisIssue(
                  ruleId: issue.ruleId,
                  message: issue.message,
                  severity: override,
                  filePath: issue.filePath,
                  line: issue.line,
                  column: issue.column,
                  suggestion: issue.suggestion,
                  context: issue.context,
                ),
        );
      }
      results.add(result.copyWith(issues: issues));
    }
    return HealthReport(
      projectName: report.projectName,
      projectPath: report.projectPath,
      results: results,
      generatedAt: report.generatedAt,
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
      ReportFormat.sarif => SarifReporter(),
      ReportFormat.badge => BadgeReporter(),
      ReportFormat.console => ConsoleReporter(
          color: color,
          verbose: verbose,
        ),
    };
  }

  /// Map report outcome to a process exit code.
  int exitCodeFor(
    HealthReport report, {
    bool failOnWarning = false,
    StackChainConfig config = StackChainConfig.empty,
  }) {
    final warn = failOnWarning || config.failOnWarning;
    if (report.hasFailures) return ExitCodes.issuesFound;
    if (warn && report.warningCount > 0) return ExitCodes.issuesFound;

    if (config.minScore != null && report.overallScore < config.minScore!) {
      return ExitCodes.issuesFound;
    }

    for (final entry in config.analyzerMinScores.entries) {
      final match = report.results.where(
        (r) => r.analyzerName.toLowerCase() == entry.key.toLowerCase() ||
            // match by common id-ish names
            r.analyzerName.toLowerCase().startsWith(entry.key.toLowerCase()),
      );
      for (final result in match) {
        if (result.score < entry.value) return ExitCodes.issuesFound;
      }
    }

    return ExitCodes.success;
  }
}
