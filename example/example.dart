/// Minimal example for StackChain Analyzer.
///
/// Run from the package root:
/// ```sh
/// dart run example/example.dart
/// ```
library;

import 'package:stackchain_analyzer/stackchain_analyzer.dart';

Future<void> main() async {
  final engine = AnalysisEngine(
    registry: AnalyzerRegistry(
      analyzers: [
        ArchitectureAnalyzer(),
        SecurityAnalyzer(),
        QualityAnalyzer(),
        DependencyAnalyzer(checkPubDev: false),
      ],
    ),
  );

  // Point at any Flutter project path.
  const projectPath = 'test/fixtures/sample_flutter';

  try {
    final report = await engine.run(projectPath: projectPath);

    // Human-readable terminal report
    ConsoleReporter(color: false).write(report);

    // Machine-readable JSON (useful for CI dashboards)
    // JsonReporter().write(report);

    // ignore: avoid_print
    print('Overall health: ${report.overallScore}/100');
    // ignore: avoid_print
    print('Issues: ${report.totalIssues}');
  } on StateError catch (e) {
    // ignore: avoid_print
    print(e.message); // "This is not a Flutter project"
  }
}
