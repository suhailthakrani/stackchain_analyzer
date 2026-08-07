import 'package:path/path.dart' as p;

import '../../models/analysis_issue.dart';
import '../../models/analysis_result.dart';
import '../../models/project_context.dart';
import '../../models/severity.dart';
import '../../utils/file_scanner.dart';
import '../analyzer.dart';

/// Detects common Bloc/Cubit anti-patterns.
class BlocAnalyzer implements Analyzer {
  BlocAnalyzer({FileScanner? scanner})
      : _scanner = scanner ?? const FileScanner();

  final FileScanner _scanner;

  @override
  String get id => 'bloc';

  @override
  String get name => 'Bloc';

  @override
  String get description =>
      'Detect Bloc/Cubit misuse (missing close, event in build)';

  @override
  Future<AnalysisResult> analyze(ProjectContext context) async {
    final issues = <AnalysisIssue>[];
    final deps = {
      ...?context.dependencies?.keys,
      ...?context.devDependencies?.keys,
    };
    final usesBloc = deps.any(
      (d) => d == 'flutter_bloc' || d == 'bloc' || d == 'hydrated_bloc',
    );

    if (!usesBloc) {
      return AnalysisResult(
        analyzerName: name,
        score: 100,
        issues: const [],
        summary: 'Bloc not detected in pubspec — skipped.',
        metadata: {'skipped': true},
      );
    }

    for (final file in context.dartFiles) {
      final relative = p.relative(file.path, from: context.rootPath);
      final content = await _scanner.readFile(file);
      if (content == null) continue;

      final isBlocFile = RegExp(r'extends\s+(Bloc|Cubit|HydratedBloc)\b')
          .hasMatch(content);
      if (isBlocFile &&
          !content.contains('close()') &&
          !content.contains('@override\n  Future<void> close')) {
        // Cubits/Blocs usually rely on BlocProvider dispose — still flag
        // custom controllers that look manual.
        if (content.contains('StreamController') ||
            content.contains('Timer(')) {
          issues.add(
            AnalysisIssue(
              ruleId: 'bloc.missing_close',
              message:
                  'Bloc/Cubit with StreamController/Timer may need an overridden close().',
              severity: Severity.warning,
              filePath: relative,
              suggestion:
                  'Override close() to cancel timers/subscriptions, then call super.close().',
            ),
          );
        }
      }

      if (RegExp(r'Widget\s+build\s*\(').hasMatch(content) &&
          RegExp(r'\.add\s*\(').hasMatch(content) &&
          content.contains('BlocProvider') == false &&
          RegExp(r'context\.read<\w+Bloc>').hasMatch(content)) {
        issues.add(
          AnalysisIssue(
            ruleId: 'bloc.event_in_build',
            message:
                'Possible Bloc event dispatched during build via context.read.',
            severity: Severity.warning,
            filePath: relative,
            suggestion:
                'Dispatch events from callbacks (onPressed) or BlocListener, not build().',
          ),
        );
      }

      if (content.contains('BlocBuilder') &&
          !content.contains('buildWhen') &&
          content.contains('state.')) {
        issues.add(
          AnalysisIssue(
            ruleId: 'bloc.missing_build_when',
            message:
                'BlocBuilder without buildWhen may rebuild more than needed.',
            severity: Severity.info,
            filePath: relative,
            suggestion:
                'Add buildWhen: (prev, next) => prev.field != next.field.',
          ),
        );
      }
    }

    return AnalysisResult(
      analyzerName: name,
      score: AnalysisResult.computeScore(issues),
      issues: issues,
      summary: '${issues.length} Bloc finding(s).',
    );
  }
}
