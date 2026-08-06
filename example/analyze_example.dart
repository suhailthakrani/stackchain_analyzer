/// Example: run StackChain Analyzer programmatically.
///
/// ```sh
/// dart run example/analyze_example.dart
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

  try {
    final report = await engine.run(
      projectPath: 'test/fixtures/sample_flutter',
    );

    ConsoleReporter(color: false).write(report);
    JsonReporter().write(report);
  } on StateError catch (e) {
    // ignore: avoid_print
    print(e.message);
  }
}
