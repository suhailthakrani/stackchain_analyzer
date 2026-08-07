import 'package:path/path.dart' as p;

import '../../models/analysis_issue.dart';
import '../../models/analysis_result.dart';
import '../../models/project_context.dart';
import '../../models/severity.dart';
import '../../utils/file_scanner.dart';
import '../analyzer.dart';

/// Detects common GetX anti-patterns.
class GetxAnalyzer implements Analyzer {
  GetxAnalyzer({FileScanner? scanner})
      : _scanner = scanner ?? const FileScanner();

  final FileScanner _scanner;

  @override
  String get id => 'getx';

  @override
  String get name => 'GetX';

  @override
  String get description =>
      'Detect GetX misuse (missing disposal, Get.put in build)';

  @override
  Future<AnalysisResult> analyze(ProjectContext context) async {
    final issues = <AnalysisIssue>[];
    final deps = {
      ...?context.dependencies?.keys,
      ...?context.devDependencies?.keys,
    };
    final usesGetx = deps.contains('get') || deps.contains('getx');

    if (!usesGetx) {
      return AnalysisResult(
        analyzerName: name,
        score: 100,
        issues: const [],
        summary: 'GetX not detected in pubspec — skipped.',
        metadata: {'skipped': true},
      );
    }

    for (final file in context.dartFiles) {
      final relative = p.relative(file.path, from: context.rootPath);
      final content = await _scanner.readFile(file);
      if (content == null) continue;

      if (RegExp(r'Widget\s+build\s*\(').hasMatch(content) &&
          RegExp(r'Get\.put\s*<').hasMatch(content)) {
        issues.add(
          AnalysisIssue(
            ruleId: 'getx.put_in_build',
            message: 'Get.put() inside build() recreates controllers on rebuild.',
            severity: Severity.error,
            filePath: relative,
            suggestion:
                'Use Get.put / Get.lazyPut in bindings or initState, not build().',
          ),
        );
      }

      if (content.contains('extends GetxController') &&
          !content.contains('onClose') &&
          (content.contains('Worker(') ||
              content.contains('ever(') ||
              content.contains('StreamSubscription'))) {
        issues.add(
          AnalysisIssue(
            ruleId: 'getx.missing_on_close',
            message:
                'GetxController with workers/subscriptions should override onClose().',
            severity: Severity.warning,
            filePath: relative,
            suggestion: 'Dispose workers/subscriptions in onClose().',
          ),
        );
      }

      if (content.contains('Obx(') && content.contains('Get.find')) {
        issues.add(
          AnalysisIssue(
            ruleId: 'getx.find_in_obx',
            message: 'Get.find inside Obx can hide reactive dependency tracking issues.',
            severity: Severity.info,
            filePath: relative,
            suggestion:
                'Prefer final controller = Get.find<T>() outside Obx, then use .obs fields.',
          ),
        );
      }
    }

    return AnalysisResult(
      analyzerName: name,
      score: AnalysisResult.computeScore(issues),
      issues: issues,
      summary: '${issues.length} GetX finding(s).',
    );
  }
}
