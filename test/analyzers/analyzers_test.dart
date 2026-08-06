import 'package:stackchain_analyzer/stackchain_analyzer.dart';
import 'package:test/test.dart';

import '../support/fixture_paths.dart';

void main() {
  late ProjectContext context;

  setUpAll(() async {
    context = await ProjectDetector().load(fixtureFlutterRoot);
  });

  test('architecture detects presentation→data violation', () async {
    final result = await ArchitectureAnalyzer().analyze(context);
    expect(result.analyzerName, 'Architecture');
    expect(result.score, lessThan(100));
    expect(
      result.issues.any((i) => i.ruleId == 'arch.layer_violation'),
      isTrue,
    );
  });

  test('security detects API key and insecure HTTP', () async {
    final result = await SecurityAnalyzer().analyze(context);
    expect(
      result.issues.any((i) => i.ruleId == 'sec.secret'),
      isTrue,
    );
    expect(
      result.issues.any((i) => i.ruleId == 'sec.insecure_http'),
      isTrue,
    );
    expect(
      result.issues.any((i) => i.ruleId == 'sec.android_debuggable'),
      isTrue,
    );
  });

  test('performance flags excessive setState and ListView children', () async {
    final result = await PerformanceAnalyzer().analyze(context);
    expect(
      result.issues.any(
        (i) =>
            i.ruleId == 'perf.excessive_setstate' ||
            i.ruleId == 'perf.listview_children',
      ),
      isTrue,
    );
  });

  test('dependencies flags deprecated pedantic and unused packages offline',
      () async {
    final result = await DependencyAnalyzer(checkPubDev: false).analyze(context);
    expect(
      result.issues.any((i) => i.ruleId == 'deps.deprecated'),
      isTrue,
    );
  });

  test('release detects missing signing config', () async {
    final result = await ReleaseAnalyzer().analyze(context);
    expect(
      result.issues.any((i) => i.ruleId == 'release.android_signing'),
      isTrue,
    );
    expect(result.score, lessThanOrEqualTo(100));
  });

  test('quality finds TODO comments', () async {
    final result = await QualityAnalyzer().analyze(context);
    expect(
      result.issues.any((i) => i.ruleId == 'quality.todo'),
      isTrue,
    );
  });
}
