import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:path/path.dart' as p;

import '../../models/analysis_issue.dart';
import '../../models/analysis_result.dart';
import '../../models/project_context.dart';
import '../../models/severity.dart';
import '../../utils/dart_parser.dart';
import '../../utils/file_scanner.dart';
import '../analyzer.dart';

/// Detects Flutter/Dart performance anti-patterns.
class PerformanceAnalyzer implements Analyzer {
  PerformanceAnalyzer({
    DartParser? parser,
    FileScanner? scanner,
  })  : _parser = parser ?? const DartParser(),
        _scanner = scanner ?? const FileScanner();

  final DartParser _parser;
  final FileScanner _scanner;

  static const _largeBuildLineThreshold = 80;
  static const _largeAssetBytes = 2 * 1024 * 1024; // 2 MB
  static const _setStateWarnThreshold = 5;

  @override
  String get id => 'performance';

  @override
  String get name => 'Performance';

  @override
  String get description =>
      'Detect rebuild issues, large builds, and asset inefficiencies';

  @override
  Future<AnalysisResult> analyze(ProjectContext context) async {
    final issues = <AnalysisIssue>[];

    for (final file in context.dartFiles) {
      final relative = p.relative(file.path, from: context.rootPath);
      final content = await _scanner.readFile(file);
      if (content == null) continue;

      issues.addAll(_checkLargeBuildMethods(content, relative));
      issues.addAll(_checkSetStateUsage(content, relative));
      issues.addAll(_checkListViewUsage(content, relative));
      issues.addAll(_checkFutureBuilderMisuse(content, relative));
      issues.addAll(_checkMissingConstHints(content, relative));
      issues.addAll(_checkHeavySyncOps(content, relative));

      final unit = _parser.parse(content, path: file.path);
      if (unit != null) {
        issues.addAll(_checkBuildMethodSizeAst(unit, content, relative));
      }
    }

    issues.addAll(await _checkLargeAssets(context));

    final score = AnalysisResult.computeScore(issues);
    return AnalysisResult(
      analyzerName: name,
      score: score,
      issues: issues,
      summary: '${issues.length} performance issue(s) detected.',
    );
  }

  List<AnalysisIssue> _checkLargeBuildMethods(String content, String path) {
    final issues = <AnalysisIssue>[];
    final buildRegex = RegExp(
      r'Widget\s+build\s*\([^)]*\)\s*\{',
      multiLine: true,
    );

    for (final match in buildRegex.allMatches(content)) {
      final start = match.end;
      final body = _extractBlock(content, start - 1);
      if (body == null) continue;
      final lines = body.split('\n').length;
      if (lines >= _largeBuildLineThreshold) {
        final lineNumber = content.substring(0, match.start).split('\n').length;
        issues.add(
          AnalysisIssue(
            ruleId: 'perf.large_build',
            message: 'build method has $lines lines.',
            severity: lines >= 200 ? Severity.error : Severity.warning,
            filePath: path,
            line: lineNumber,
            suggestion: 'Split into smaller widgets to reduce rebuild cost.',
          ),
        );
      }
    }
    return issues;
  }

  List<AnalysisIssue> _checkBuildMethodSizeAst(
    CompilationUnit unit,
    String content,
    String path,
  ) {
    // AST-backed confirmation for StatefulWidget/StatelessWidget build methods.
    final finder = MethodFinder(namePredicate: (n) => n == 'build');
    unit.accept(finder);
    final issues = <AnalysisIssue>[];

    for (final method in finder.methods) {
      final start = method.offset;
      final end = method.end;
      if (start < 0 || end > content.length) continue;
      final snippet = content.substring(start, end);
      final lines = snippet.split('\n').length;
      if (lines < _largeBuildLineThreshold) continue;

      // Avoid duplicating regex findings for the same method.
      final already = issues.any(
        (i) => i.filePath == path && i.ruleId == 'perf.large_build',
      );
      if (already) continue;
    }
    return issues;
  }

  List<AnalysisIssue> _checkSetStateUsage(String content, String path) {
    final issues = <AnalysisIssue>[];
    final matches = RegExp(r'\bsetState\s*\(').allMatches(content).toList();
    if (matches.length >= _setStateWarnThreshold) {
      issues.add(
        AnalysisIssue(
          ruleId: 'perf.excessive_setstate',
          message:
              'File contains ${matches.length} setState calls — possible unnecessary rebuilds.',
          severity: Severity.warning,
          filePath: path,
          suggestion:
              'Consider extracting state, using ValueNotifier, or a state-management solution.',
        ),
      );
    }
    return issues;
  }

  List<AnalysisIssue> _checkListViewUsage(String content, String path) {
    final issues = <AnalysisIssue>[];

    if (RegExp(r'ListView\s*\([^)]*children\s*:').hasMatch(content) &&
        !content.contains('ListView.builder') &&
        !content.contains('ListView.separated')) {
      // Heuristic: ListView(children: [...]) with many children is costly.
      final childrenMatch =
          RegExp(r'ListView\s*\([\s\S]*?children\s*:\s*\[').firstMatch(content);
      if (childrenMatch != null) {
        issues.add(
          AnalysisIssue(
            ruleId: 'perf.listview_children',
            message:
                'ListView with eager children list detected; prefer ListView.builder for long lists.',
            severity: Severity.warning,
            filePath: path,
            suggestion:
                'Use ListView.builder or ListView.separated for lazy construction.',
          ),
        );
      }
    }

    if (content.contains('Column(') &&
        RegExp(r'children\s*:\s*\[[\s\S]{500,}\]').hasMatch(content) &&
        content.contains('SingleChildScrollView')) {
      issues.add(
        AnalysisIssue(
          ruleId: 'perf.column_scroll',
          message:
              'Large Column inside SingleChildScrollView — prefer CustomScrollView/ListView.',
          severity: Severity.info,
          filePath: path,
          suggestion:
              'Use slivers or ListView.builder for scrollable long content.',
        ),
      );
    }

    return issues;
  }

  List<AnalysisIssue> _checkFutureBuilderMisuse(String content, String path) {
    final issues = <AnalysisIssue>[];

    // Future created inline in FutureBuilder future: — causes refetch on rebuild.
    if (RegExp(
      r'FutureBuilder\s*<[^>]*>\s*\(\s*future\s*:\s*\w+\s*\(',
    ).hasMatch(content) ||
        RegExp(r'future\s*:\s*\w+\([^)]*\)\s*,').hasMatch(content) &&
            content.contains('FutureBuilder')) {
      // More precise: future: someMethod( or future: fetch(
      if (RegExp(
        r'FutureBuilder[\s\S]{0,200}?future\s*:\s*[a-zA-Z_]\w*\s*\(',
      ).hasMatch(content)) {
        issues.add(
          AnalysisIssue(
            ruleId: 'perf.futurebuilder_inline',
            message:
                'FutureBuilder may create a new Future on every rebuild.',
            severity: Severity.warning,
            filePath: path,
            suggestion:
                'Cache the Future in initState / a field, or use a proper async state solution.',
          ),
        );
      }
    }
    return issues;
  }

  List<AnalysisIssue> _checkMissingConstHints(String content, String path) {
    final issues = <AnalysisIssue>[];

    // Heuristic: common widgets that are often eligible for const.
    final candidates = [
      RegExp(r'\bSizedBox\s*\('),
      RegExp(r'\bEdgeInsets\.(all|only|symmetric)\s*\('),
      RegExp(r'\bIcon\s*\(\s*Icons\.'),
      RegExp(r'''\bText\s*\(\s*['"]'''),
    ];

    var hits = 0;
    for (final re in candidates) {
      for (final match in re.allMatches(content)) {
        // Skip if preceded by const on the same line segment.
        final prefixStart = match.start > 20 ? match.start - 20 : 0;
        final prefix = content.substring(prefixStart, match.start);
        if (prefix.trimRight().endsWith('const') ||
            RegExp(r'const\s*$').hasMatch(prefix)) {
          continue;
        }
        hits++;
      }
    }

    if (hits >= 8) {
      issues.add(
        AnalysisIssue(
          ruleId: 'perf.missing_const',
          message:
              'Approximately $hits widgets/values may benefit from const constructors.',
          severity: Severity.info,
          filePath: path,
          suggestion:
              'Add const where possible to enable canonicalization and skip rebuilds.',
        ),
      );
    }
    return issues;
  }

  List<AnalysisIssue> _checkHeavySyncOps(String content, String path) {
    final issues = <AnalysisIssue>[];
    final patterns = <RegExp, String>{
      RegExp(r'\bFile\([^)]*\)\.readAs(String|Bytes)Sync\s*\('):
          'Synchronous file I/O',
      RegExp(r'\bjsonDecode\s*\([^)]{200,}\)'):
          'Large synchronous JSON decode',
      RegExp(r'\bSleep\s*\(|\bsleep\s*\('): 'Blocking sleep on UI isolate',
    };

    for (final entry in patterns.entries) {
      if (entry.key.hasMatch(content)) {
        issues.add(
          AnalysisIssue(
            ruleId: 'perf.heavy_sync',
            message: 'Heavy synchronous operation: ${entry.value}.',
            severity: Severity.warning,
            filePath: path,
            suggestion: 'Move work to an async API or a background isolate.',
          ),
        );
      }
    }
    return issues;
  }

  Future<List<AnalysisIssue>> _checkLargeAssets(ProjectContext context) async {
    final issues = <AnalysisIssue>[];
    for (final assetPath in context.assetPaths) {
      final file = File(assetPath);
      if (!await file.exists()) continue;
      final length = await file.length();
      if (length >= _largeAssetBytes) {
        final mb = (length / (1024 * 1024)).toStringAsFixed(1);
        issues.add(
          AnalysisIssue(
            ruleId: 'perf.large_asset',
            message: 'Large asset file ($mb MB).',
            severity: Severity.warning,
            filePath: p.relative(assetPath, from: context.rootPath),
            suggestion:
                'Compress images, use WebP/AVIF, or load assets on demand.',
          ),
        );
      }
    }
    return issues;
  }

  /// Extract a `{ ... }` block starting at the opening brace index.
  String? _extractBlock(String source, int openBraceIndex) {
    if (openBraceIndex < 0 ||
        openBraceIndex >= source.length ||
        source[openBraceIndex] != '{') {
      return null;
    }
    var depth = 0;
    for (var i = openBraceIndex; i < source.length; i++) {
      final c = source[i];
      if (c == '{') depth++;
      if (c == '}') {
        depth--;
        if (depth == 0) {
          return source.substring(openBraceIndex, i + 1);
        }
      }
    }
    return null;
  }
}
