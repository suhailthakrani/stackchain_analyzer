import 'package:path/path.dart' as p;

import '../../models/analysis_issue.dart';
import '../../models/analysis_result.dart';
import '../../models/project_context.dart';
import '../../models/severity.dart';
import '../../utils/file_scanner.dart';
import '../analyzer.dart';

/// General Dart/Flutter code quality checks.
class QualityAnalyzer implements Analyzer {
  QualityAnalyzer({FileScanner? scanner})
      : _scanner = scanner ?? const FileScanner();

  final FileScanner _scanner;

  static const _largeFileLines = 500;
  static const _longMethodLines = 80;

  @override
  String get id => 'quality';

  @override
  String get name => 'Quality';

  @override
  String get description =>
      'Detect large files, long methods, TODOs, naming, and dead files';

  @override
  Future<AnalysisResult> analyze(ProjectContext context) async {
    final issues = <AnalysisIssue>[];
    final contents = <String, String>{};

    for (final file in context.dartFiles) {
      final relative = p.relative(file.path, from: context.rootPath);
      final content = await _scanner.readFile(file);
      if (content == null) continue;
      contents[relative] = content;

      issues.addAll(_checkFileSize(content, relative));
      issues.addAll(_checkLongMethods(content, relative));
      issues.addAll(_checkTodos(content, relative));
      issues.addAll(_checkNaming(relative));
    }

    issues.addAll(_checkDuplicateBlocks(contents));
    issues.addAll(await _checkDeadFiles(context, contents.keys.toSet()));

    final score = AnalysisResult.computeScore(issues);
    return AnalysisResult(
      analyzerName: name,
      score: score,
      issues: issues,
      summary: '${issues.length} quality issue(s).',
      metadata: {
        'fileCount': context.dartFiles.length,
        'todoCount': issues.where((i) => i.ruleId == 'quality.todo').length,
      },
    );
  }

  List<AnalysisIssue> _checkFileSize(String content, String path) {
    final lines = _scanner.countLines(content);
    if (lines < _largeFileLines) return const [];
    return [
      AnalysisIssue(
        ruleId: 'quality.large_file',
        message: 'File has $lines lines (threshold: $_largeFileLines).',
        severity: lines >= 1000 ? Severity.error : Severity.warning,
        filePath: path,
        suggestion: 'Split into smaller modules or widgets.',
      ),
    ];
  }

  List<AnalysisIssue> _checkLongMethods(String content, String path) {
    final issues = <AnalysisIssue>[];
    final methodRe = RegExp(
      r'(?:(?:static|async|Future<\w+>|void|Widget|int|String|bool|double|dynamic)\s+)+(\w+)\s*\([^;]*?\)\s*\{',
      multiLine: true,
    );

    for (final match in methodRe.allMatches(content)) {
      final name = match.group(1);
      if (name == null || name == 'get' || name == 'set') continue;
      final open = match.end - 1;
      final body = _extractBlock(content, open);
      if (body == null) continue;
      final lines = body.split('\n').length;
      if (lines >= _longMethodLines) {
        final lineNumber =
            content.substring(0, match.start).split('\n').length;
        issues.add(
          AnalysisIssue(
            ruleId: 'quality.long_method',
            message: 'Method "$name" has $lines lines.',
            severity: Severity.warning,
            filePath: path,
            line: lineNumber,
            suggestion:
                'Extract helpers to improve readability and testability.',
          ),
        );
      }
    }
    return issues;
  }

  List<AnalysisIssue> _checkTodos(String content, String path) {
    final issues = <AnalysisIssue>[];
    final re = RegExp(r'//\s*(TODO|FIXME|HACK)\b(.*)$', multiLine: true);
    for (final match in re.allMatches(content)) {
      final kind = match.group(1) ?? 'TODO';
      final note = (match.group(2) ?? '').trim();
      final line = content.substring(0, match.start).split('\n').length;
      issues.add(
        AnalysisIssue(
          ruleId: 'quality.todo',
          message: note.isEmpty ? '$kind comment found.' : '$kind: $note',
          severity: kind == 'FIXME' ? Severity.warning : Severity.info,
          filePath: path,
          line: line,
        ),
      );
    }
    return issues;
  }

  List<AnalysisIssue> _checkNaming(String path) {
    final fileName = p.basename(path);
    if (!fileName.endsWith('.dart')) return const [];

    final base = fileName.replaceAll('.dart', '');
    if (base.contains('-') || RegExp(r'[A-Z]').hasMatch(base)) {
      return [
        AnalysisIssue(
          ruleId: 'quality.naming',
          message: 'File name "$fileName" is not snake_case.',
          severity: Severity.info,
          filePath: path,
          suggestion: 'Rename to lower_snake_case.dart.',
        ),
      ];
    }
    return const [];
  }

  List<AnalysisIssue> _checkDuplicateBlocks(Map<String, String> contents) {
    final issues = <AnalysisIssue>[];
    final fingerprints = <String, List<String>>{};

    for (final entry in contents.entries) {
      final lines = entry.value
          .split('\n')
          .map((l) => l.trim())
          .where(
            (l) =>
                l.length > 20 &&
                !l.startsWith('//') &&
                !l.startsWith('import '),
          )
          .toList();

      for (var i = 0; i + 5 < lines.length; i++) {
        final window = lines.sublist(i, i + 6).join('\n');
        fingerprints.putIfAbsent(window, () => []).add(entry.key);
      }
    }

    final reported = <String>{};
    for (final entry in fingerprints.entries) {
      final files = entry.value.toSet();
      if (files.length < 2) continue;
      final key = files.toList()..sort();
      final sig = key.join('|');
      if (reported.contains(sig)) continue;
      reported.add(sig);
      if (reported.length > 10) break;

      issues.add(
        AnalysisIssue(
          ruleId: 'quality.duplicate',
          message: 'Possible duplicate code across: ${key.join(', ')}.',
          severity: Severity.info,
          suggestion: 'Extract a shared function or widget.',
        ),
      );
    }
    return issues;
  }

  Future<List<AnalysisIssue>> _checkDeadFiles(
    ProjectContext context,
    Set<String> allRelative,
  ) async {
    final issues = <AnalysisIssue>[];
    final packageName = context.packageName;
    if (packageName == null) return issues;

    final referenced = <String>{};
    final pathToFile = {
      for (final f in context.dartFiles)
        p.relative(f.path, from: context.rootPath): f,
    };

    for (final path in allRelative) {
      final file = pathToFile[path];
      if (file == null) continue;
      final content = await _scanner.readFile(file);
      if (content == null) continue;

      for (final other in allRelative) {
        if (other == path) continue;
        final libRelative =
            other.startsWith('lib/') ? other.substring(4) : other;
        if (content.contains('package:$packageName/$libRelative')) {
          referenced.add(other);
        }
        final base = p.basename(other);
        if (content.contains(base)) {
          referenced.add(other);
        }
      }
    }

    for (final path in allRelative) {
      if (path.endsWith('main.dart') ||
          path.endsWith('app.dart') ||
          p.basename(path) == '$packageName.dart') {
        referenced.add(path);
      }
    }

    var orphanCount = 0;
    for (final path in allRelative) {
      if (referenced.contains(path)) continue;
      if (path.endsWith('main.dart')) continue;
      orphanCount++;
      if (orphanCount > 5) break;
      issues.add(
        AnalysisIssue(
          ruleId: 'quality.dead_file',
          message: 'File may be unreferenced.',
          severity: Severity.info,
          filePath: path,
          suggestion: 'Confirm usage or remove dead code.',
        ),
      );
    }
    return issues;
  }

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
        if (depth == 0) return source.substring(openBraceIndex, i + 1);
      }
    }
    return null;
  }
}
