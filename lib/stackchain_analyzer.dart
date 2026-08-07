/// StackChain Analyzer — Flutter project health analysis toolkit.
///
/// Use the CLI:
/// ```sh
/// dart run stackchain_analyzer analyze
/// dart run stackchain_analyzer analyze architecture --format json
/// dart run stackchain_analyzer analyze --format sarif
/// dart run stackchain_analyzer analyze --baseline
/// ```
///
/// Or embed analyzers programmatically:
/// ```dart
/// final engine = AnalysisEngine();
/// final report = await engine.run(projectPath: '.');
/// ```
library;

export 'src/analyzers/analyzer.dart';
export 'src/analyzers/analyzer_registry.dart';
export 'src/analyzers/architecture/architecture_analyzer.dart';
export 'src/analyzers/dependencies/dependency_analyzer.dart';
export 'src/analyzers/performance/performance_analyzer.dart';
export 'src/analyzers/quality/quality_analyzer.dart';
export 'src/analyzers/release/release_analyzer.dart';
export 'src/analyzers/security/security_analyzer.dart';
export 'src/analyzers/state/bloc_analyzer.dart';
export 'src/analyzers/state/getx_analyzer.dart';
export 'src/analyzers/state/riverpod_analyzer.dart';
export 'src/commands/analysis_engine.dart';
export 'src/commands/analyze_command.dart';
export 'src/commands/stackchain_runner.dart';
export 'src/config/stackchain_config.dart';
export 'src/models/analysis_issue.dart';
export 'src/models/analysis_result.dart';
export 'src/models/health_report.dart';
export 'src/models/project_context.dart';
export 'src/models/severity.dart';
export 'src/reporters/badge_reporter.dart';
export 'src/reporters/ci_reporter.dart';
export 'src/reporters/console_reporter.dart';
export 'src/reporters/json_reporter.dart';
export 'src/reporters/reporter.dart';
export 'src/reporters/sarif_reporter.dart';
export 'src/utils/baseline.dart';
export 'src/utils/exit_codes.dart';
export 'src/utils/project_detector.dart';
