import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:stackchain_analyzer/stackchain_analyzer.dart';
import 'package:test/test.dart';

import 'support/fixture_paths.dart';

void main() {
  group('StackChainConfig', () {
    test('loads ignore rules and severity overrides', () async {
      final dir = await Directory.systemTemp.createTemp('stackchain_cfg_');
      final file = File(p.join(dir.path, '.stackchain.yaml'));
      await file.writeAsString('''
ignore:
  - quality.todo
  - rule: deps.outdated
    path: "lib/generated/**"
severity_overrides:
  perf.missing_const: info
fail:
  on_warning: true
  min_score: 50
thresholds:
  security: 40
''');

      final config = await StackChainConfig.load(projectPath: dir.path);
      expect(config.failOnWarning, isTrue);
      expect(config.minScore, 50);
      expect(config.analyzerMinScores['security'], 40);
      expect(
        config.isIgnored(ruleId: 'quality.todo', filePath: 'lib/a.dart'),
        isTrue,
      );
      expect(
        config.isIgnored(
          ruleId: 'deps.outdated',
          filePath: 'lib/generated/foo.dart',
        ),
        isTrue,
      );
      expect(
        config.isIgnored(
          ruleId: 'deps.outdated',
          filePath: 'lib/main.dart',
        ),
        isFalse,
      );
      expect(config.severityOverrides['perf.missing_const'], Severity.info);

      await dir.delete(recursive: true);
    });
  });

  group('BaselineStore', () {
    test('save / load / filterNew', () async {
      final dir = await Directory.systemTemp.createTemp('stackchain_bl_');
      final baselinePath = p.join(dir.path, 'baseline.json');

      final engine = AnalysisEngine(
        registry: AnalyzerRegistry(
          analyzers: [QualityAnalyzer()],
        ),
      );
      final report = await engine.run(projectPath: fixtureFlutterRoot);
      expect(report.totalIssues, greaterThan(0));

      const store = BaselineStore();
      await store.save(baselinePath, report);
      final fingerprints = await store.load(baselinePath);
      expect(fingerprints, isNotEmpty);

      final filtered = store.filterNew(report, fingerprints);
      expect(filtered.totalIssues, 0);

      await dir.delete(recursive: true);
    });
  });

  group('SARIF + badge reporters', () {
    test('SARIF emits schema and results', () async {
      final engine = AnalysisEngine(
        registry: AnalyzerRegistry(analyzers: [SecurityAnalyzer()]),
      );
      final report = await engine.run(projectPath: fixtureFlutterRoot);
      final buffer = StringBuffer();
      SarifReporter(sink: _StringSink(buffer)).write(report);
      final out = buffer.toString();
      expect(out, contains(r'$schema'));
      expect(out, contains('stackchain_analyzer'));
      expect(out, contains('runs'));
    });

    test('badge reporter prints shields markdown', () {
      final report = HealthReport(
        projectName: 'demo',
        projectPath: '/tmp',
        results: const [
          AnalysisResult(analyzerName: 'Quality', score: 90, issues: []),
        ],
      );
      final buffer = StringBuffer();
      BadgeReporter(sink: _StringSink(buffer)).write(report);
      expect(buffer.toString(), contains('img.shields.io'));
      expect(buffer.toString(), contains('90%'));
    });
  });

  group('state analyzers', () {
    test('skip cleanly when package not present', () async {
      final context = await ProjectDetector().load(fixtureFlutterRoot);
      final riverpod = await RiverpodAnalyzer().analyze(context);
      final bloc = await BlocAnalyzer().analyze(context);
      final getx = await GetxAnalyzer().analyze(context);
      expect(riverpod.metadata['skipped'], isTrue);
      expect(bloc.metadata['skipped'], isTrue);
      expect(getx.metadata['skipped'], isTrue);
      expect(riverpod.score, 100);
    });
  });

  group('strict release', () {
    test('strict mode adds release.strict_* findings', () async {
      final context = await ProjectDetector().load(fixtureFlutterRoot);
      final result = await ReleaseAnalyzer(strict: true).analyze(context);
      expect(
        result.issues.any((i) => i.ruleId.contains('strict')),
        isTrue,
      );
    });
  });
}

class _StringSink implements StringSink {
  _StringSink(this.buffer);
  final StringBuffer buffer;

  @override
  void write(Object? object) => buffer.write(object);

  @override
  void writeAll(Iterable<dynamic> objects, [String separator = '']) =>
      buffer.writeAll(objects, separator);

  @override
  void writeCharCode(int charCode) => buffer.writeCharCode(charCode);

  @override
  void writeln([Object? object = '']) => buffer.writeln(object);
}
