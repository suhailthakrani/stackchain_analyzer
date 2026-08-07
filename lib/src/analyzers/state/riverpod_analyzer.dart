import 'package:path/path.dart' as p;

import '../../models/analysis_issue.dart';
import '../../models/analysis_result.dart';
import '../../models/project_context.dart';
import '../../models/severity.dart';
import '../../utils/file_scanner.dart';
import '../analyzer.dart';

/// Detects common Riverpod anti-patterns.
class RiverpodAnalyzer implements Analyzer {
  RiverpodAnalyzer({FileScanner? scanner})
      : _scanner = scanner ?? const FileScanner();

  final FileScanner _scanner;

  @override
  String get id => 'riverpod';

  @override
  String get name => 'Riverpod';

  @override
  String get description =>
      'Detect Riverpod misuse (ref.read vs watch, missing providers)';

  @override
  Future<AnalysisResult> analyze(ProjectContext context) async {
    final issues = <AnalysisIssue>[];
    final deps = {
      ...?context.dependencies?.keys,
      ...?context.devDependencies?.keys,
    };
    final usesRiverpod = deps.any(
      (d) =>
          d == 'flutter_riverpod' ||
          d == 'hooks_riverpod' ||
          d == 'riverpod' ||
          d == 'riverpod_annotation',
    );

    if (!usesRiverpod) {
      return AnalysisResult(
        analyzerName: name,
        score: 100,
        issues: const [],
        summary: 'Riverpod not detected in pubspec — skipped.',
        metadata: {'skipped': true},
      );
    }

    for (final file in context.dartFiles) {
      final relative = p.relative(file.path, from: context.rootPath);
      final content = await _scanner.readFile(file);
      if (content == null) continue;

      // ref.read inside build methods is a common bug (stale values).
      if (RegExp(r'Widget\s+build\s*\([^)]*\)').hasMatch(content) &&
          RegExp(r'ref\.read\s*\(').hasMatch(content)) {
        issues.add(
          AnalysisIssue(
            ruleId: 'riverpod.read_in_build',
            message:
                'ref.read() used in a file with build() — prefer ref.watch for UI.',
            severity: Severity.warning,
            filePath: relative,
            suggestion:
                'Use ref.watch so the widget rebuilds when the provider changes.',
          ),
        );
      }

      // Provider declared but never watched/read elsewhere is hard; flag
      // StateProvider/StateNotifier without .select for large models.
      if (content.contains('StateNotifierProvider') &&
          !content.contains('.select(') &&
          content.contains('Consumer')) {
        issues.add(
          AnalysisIssue(
            ruleId: 'riverpod.missing_select',
            message:
                'StateNotifierProvider consumed without .select — risk of over-rebuild.',
            severity: Severity.info,
            filePath: relative,
            suggestion:
                'Use ref.watch(provider.select((s) => s.field)) for granular rebuilds.',
          ),
        );
      }

      if (RegExp(r'ProviderScope\s*\(').hasMatch(content) &&
          content.contains('overrides:') &&
          content.contains('ProviderContainer')) {
        issues.add(
          AnalysisIssue(
            ruleId: 'riverpod.container_in_scope',
            message: 'ProviderContainer mixed with ProviderScope overrides.',
            severity: Severity.info,
            filePath: relative,
            suggestion:
                'Prefer ProviderScope overrides for widget trees; containers for tests/tools.',
          ),
        );
      }
    }

    return AnalysisResult(
      analyzerName: name,
      score: AnalysisResult.computeScore(issues),
      issues: issues,
      summary: '${issues.length} Riverpod finding(s).',
    );
  }
}
