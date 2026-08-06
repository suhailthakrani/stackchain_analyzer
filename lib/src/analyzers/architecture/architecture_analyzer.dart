import 'dart:io';

import 'package:path/path.dart' as p;

import '../../models/analysis_issue.dart';
import '../../models/analysis_result.dart';
import '../../models/project_context.dart';
import '../../models/severity.dart';
import '../../utils/dart_parser.dart';
import '../../utils/file_scanner.dart';
import '../analyzer.dart';

/// Detects Flutter architecture anti-patterns.
///
/// Supports Clean Architecture, Feature First, MVVM, and MVC layouts.
class ArchitectureAnalyzer implements Analyzer {
  ArchitectureAnalyzer({
    DartParser? parser,
    FileScanner? scanner,
  })  : _parser = parser ?? const DartParser(),
        _scanner = scanner ?? const FileScanner();

  final DartParser _parser;
  final FileScanner _scanner;

  static const _oversizedFeatureFileThreshold = 40;

  @override
  String get id => 'architecture';

  @override
  String get name => 'Architecture';

  @override
  String get description =>
      'Detect layer violations, missing domain, and structural issues';

  @override
  Future<AnalysisResult> analyze(ProjectContext context) async {
    final issues = <AnalysisIssue>[];

    issues.addAll(await _checkLayerViolations(context));
    issues.addAll(await _checkMissingDomain(context));
    issues.addAll(await _checkOversizedFeatures(context));
    issues.addAll(await _checkCircularHints(context));
    issues.addAll(await _checkBusinessLogicInWidgets(context));

    final score = AnalysisResult.computeScore(issues);
    final style = context.architectureStyle.name;

    return AnalysisResult(
      analyzerName: name,
      score: score,
      issues: issues,
      summary: 'Detected style: $style. ${issues.length} architecture issue(s).',
      metadata: {'architectureStyle': style},
    );
  }

  Future<List<AnalysisIssue>> _checkLayerViolations(
    ProjectContext context,
  ) async {
    final issues = <AnalysisIssue>[];
    final packageName = context.packageName ?? '';

    for (final file in context.dartFiles) {
      final relative = p.relative(file.path, from: context.rootPath);
      final layer = _detectLayer(relative);
      if (layer == null) continue;

      final content = await _scanner.readFile(file);
      if (content == null) continue;

      final unit = _parser.parse(content, path: file.path);
      if (unit == null) continue;

      final imports = _parser.collectImports(unit);
      for (final importUri in imports) {
        final importedLayer = _layerFromImport(importUri, packageName, relative);
        if (importedLayer == null) continue;

        final violation = _isViolation(layer, importedLayer);
        if (violation != null) {
          issues.add(
            AnalysisIssue(
              ruleId: 'arch.layer_violation',
              message: violation.message,
              severity: Severity.error,
              filePath: relative,
              suggestion: violation.suggestion,
              context: 'Imports: $importUri',
            ),
          );
        }
      }
    }
    return issues;
  }

  Future<List<AnalysisIssue>> _checkMissingDomain(
    ProjectContext context,
  ) async {
    final issues = <AnalysisIssue>[];
    final style = context.architectureStyle;

    if (style != ArchitectureStyle.cleanArchitecture &&
        style != ArchitectureStyle.featureFirst) {
      return issues;
    }

    final hasTopDomain =
        await Directory(p.join(context.libPath, 'domain')).exists();
    final hasFeatureDomain = await _anyFeatureHasLayer(context, 'domain');

    if (!hasTopDomain && !hasFeatureDomain) {
      final hasData = await Directory(p.join(context.libPath, 'data')).exists() ||
          await _anyFeatureHasLayer(context, 'data');
      if (hasData) {
        issues.add(
          const AnalysisIssue(
            ruleId: 'arch.missing_domain',
            message: 'Data layer present but domain layer is missing.',
            severity: Severity.warning,
            suggestion:
                'Introduce a domain layer with entities and repository abstractions.',
          ),
        );
      }
    }
    return issues;
  }

  Future<List<AnalysisIssue>> _checkOversizedFeatures(
    ProjectContext context,
  ) async {
    final issues = <AnalysisIssue>[];
    final featuresRoot = Directory(p.join(context.libPath, 'features'));
    if (!await featuresRoot.exists()) {
      final alt = Directory(p.join(context.libPath, 'feature'));
      if (!await alt.exists()) return issues;
      return _scanFeatureDirs(alt, context, issues);
    }
    return _scanFeatureDirs(featuresRoot, context, issues);
  }

  Future<List<AnalysisIssue>> _scanFeatureDirs(
    Directory featuresRoot,
    ProjectContext context,
    List<AnalysisIssue> issues,
  ) async {
    await for (final entity in featuresRoot.list()) {
      if (entity is! Directory) continue;
      final dartFiles = await _scanner.findDartFiles(entity.path);
      if (dartFiles.length > _oversizedFeatureFileThreshold) {
        final name = p.basename(entity.path);
        issues.add(
          AnalysisIssue(
            ruleId: 'arch.oversized_feature',
            message:
                'Feature "$name" has ${dartFiles.length} Dart files (threshold: $_oversizedFeatureFileThreshold).',
            severity: Severity.warning,
            filePath: p.relative(entity.path, from: context.rootPath),
            suggestion:
                'Split into sub-features or extract shared modules.',
          ),
        );
      }
    }
    return issues;
  }

  Future<List<AnalysisIssue>> _checkCircularHints(
    ProjectContext context,
  ) async {
    final issues = <AnalysisIssue>[];
    final packageName = context.packageName ?? '';
    if (packageName.isEmpty) return issues;

    // Build a simple import graph of package-relative paths.
    final graph = <String, Set<String>>{};

    for (final file in context.dartFiles) {
      final relative = p.relative(file.path, from: context.rootPath);
      final content = await _scanner.readFile(file);
      if (content == null) continue;
      final unit = _parser.parse(content, path: file.path);
      if (unit == null) continue;

      final imports = _parser.collectImports(unit);
      final targets = <String>{};
      for (final uri in imports) {
        final target = _packageUriToRelative(uri, packageName);
        if (target != null) targets.add(target);
      }
      graph[relative] = targets;
    }

    // Detect 2-cycles (A→B→A) as a practical circular dependency signal.
    for (final entry in graph.entries) {
      final a = entry.key;
      for (final b in entry.value) {
        final bImports = graph[b];
        if (bImports != null && bImports.contains(a) && a.compareTo(b) < 0) {
          issues.add(
            AnalysisIssue(
              ruleId: 'arch.circular_dependency',
              message: 'Circular dependency between $a and $b.',
              severity: Severity.error,
              filePath: a,
              suggestion:
                  'Extract a shared abstraction or invert one dependency direction.',
            ),
          );
        }
      }
    }
    return issues;
  }

  Future<List<AnalysisIssue>> _checkBusinessLogicInWidgets(
    ProjectContext context,
  ) async {
    final issues = <AnalysisIssue>[];

    for (final file in context.dartFiles) {
      final relative = p.relative(file.path, from: context.rootPath);
      if (!_looksLikeUiFile(relative)) continue;

      final content = await _scanner.readFile(file);
      if (content == null) continue;

      // Heuristics: HTTP / DB / repository calls inside widget files.
      final patterns = <RegExp, String>{
        RegExp(r'\b(http\.|dio\.|Dio\()'): 'HTTP client usage',
        RegExp(r'\b(FirebaseFirestore|FirebaseAuth|SharedPreferences)\b'):
            'Direct infrastructure access',
        RegExp(r'\b(sqflite|Isar|Hive)\b'): 'Direct database access',
      };

      for (final entry in patterns.entries) {
        if (entry.key.hasMatch(content)) {
          issues.add(
            AnalysisIssue(
              ruleId: 'arch.logic_in_widget',
              message:
                  'Possible business/infrastructure logic in UI: ${entry.value}.',
              severity: Severity.warning,
              filePath: relative,
              suggestion:
                  'Move networking and persistence into repositories or use cases.',
            ),
          );
        }
      }
    }
    return issues;
  }

  Future<bool> _anyFeatureHasLayer(ProjectContext context, String layer) async {
    for (final name in ['features', 'feature']) {
      final root = Directory(p.join(context.libPath, name));
      if (!await root.exists()) continue;
      await for (final feature in root.list()) {
        if (feature is! Directory) continue;
        if (await Directory(p.join(feature.path, layer)).exists()) {
          return true;
        }
      }
    }
    return false;
  }

  String? _detectLayer(String relativePath) {
    final normalized = relativePath.replaceAll('\\', '/').toLowerCase();
    if (normalized.contains('/presentation/') ||
        normalized.contains('/ui/') ||
        normalized.contains('/views/') ||
        normalized.contains('/widgets/') ||
        normalized.contains('/screens/') ||
        normalized.contains('/pages/')) {
      return 'presentation';
    }
    if (normalized.contains('/domain/')) return 'domain';
    if (normalized.contains('/data/')) return 'data';
    return null;
  }

  String? _layerFromImport(
    String importUri,
    String packageName,
    String currentFile,
  ) {
    String? path;
    if (importUri.startsWith('package:$packageName/')) {
      path = 'lib/${importUri.substring('package:$packageName/'.length)}';
    } else if (importUri.startsWith('package:')) {
      return null; // external package
    } else if (importUri.startsWith('.')) {
      final dir = p.dirname(currentFile);
      path = p.normalize(p.join(dir, importUri));
    } else {
      return null;
    }
    return _detectLayer(path);
  }

  String? _packageUriToRelative(String uri, String packageName) {
    if (!uri.startsWith('package:$packageName/')) return null;
    return 'lib/${uri.substring('package:$packageName/'.length)}';
  }

  bool _looksLikeUiFile(String relative) {
    final n = relative.toLowerCase();
    return n.contains('/presentation/') ||
        n.contains('/ui/') ||
        n.contains('/views/') ||
        n.contains('/widgets/') ||
        n.contains('/screens/') ||
        n.contains('/pages/') ||
        n.endsWith('_page.dart') ||
        n.endsWith('_screen.dart') ||
        n.endsWith('_view.dart') ||
        n.endsWith('_widget.dart');
  }

  _Violation? _isViolation(String from, String to) {
    // Presentation must not depend on data.
    if (from == 'presentation' && to == 'data') {
      return const _Violation(
        message:
            'Presentation layer should not depend directly on data layer.',
        suggestion: 'Create a domain repository abstraction and inject it.',
      );
    }
    // Domain must not depend on data or presentation.
    if (from == 'domain' && (to == 'data' || to == 'presentation')) {
      return _Violation(
        message: 'Domain layer must not depend on $to layer.',
        suggestion: 'Keep domain pure; depend only on abstractions.',
      );
    }
    return null;
  }
}

class _Violation {
  const _Violation({required this.message, required this.suggestion});
  final String message;
  final String suggestion;
}
