import 'dart:convert';

import 'package:stackchain_analyzer/stackchain_analyzer.dart';
import 'package:test/test.dart';

import 'support/fixture_paths.dart';

void main() {
  test('AnalysisEngine produces a health report', () async {
    final engine = AnalysisEngine(
      registry: AnalyzerRegistry(
        analyzers: [
          ArchitectureAnalyzer(),
          SecurityAnalyzer(),
          DependencyAnalyzer(checkPubDev: false),
        ],
      ),
    );

    final report = await engine.run(projectPath: fixtureFlutterRoot);
    expect(report.projectName, 'sample_app');
    expect(report.results, hasLength(3));
    expect(report.overallScore, inInclusiveRange(0, 100));
    expect(report.totalIssues, greaterThan(0));
    expect(engine.exitCodeFor(report), ExitCodes.issuesFound);
  });

  test('HealthReport serializes to JSON', () async {
    final engine = AnalysisEngine(
      registry: AnalyzerRegistry(
        analyzers: [QualityAnalyzer()],
      ),
    );
    final report = await engine.run(projectPath: fixtureFlutterRoot);
    final json = report.toJson();
    expect(json['project'], 'sample_app');
    expect(json['healthScore'], isA<int>());
    // Ensure encodeable
    expect(jsonEncode(json), contains('sample_app'));
  });

  test('AnalyzerRegistry resolves known ids', () {
    final registry = AnalyzerRegistry();
    expect(registry.findById('architecture'), isNotNull);
    expect(registry.resolve(['security', 'release']), hasLength(2));
    expect(() => registry.resolve(['nope']), throwsArgumentError);
  });

  test('AnalysisResult.computeScore subtracts severity weights', () {
    final issues = [
      const AnalysisIssue(
        ruleId: 't',
        message: 'x',
        severity: Severity.critical,
      ),
      const AnalysisIssue(
        ruleId: 't',
        message: 'y',
        severity: Severity.info,
      ),
    ];
    expect(AnalysisResult.computeScore(issues), 100 - 25 - 1);
  });
}
