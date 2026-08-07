import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../../models/analysis_issue.dart';
import '../../models/analysis_result.dart';
import '../../models/project_context.dart';
import '../../models/severity.dart';
import '../../utils/file_scanner.dart';
import '../analyzer.dart';

/// Analyzes pubspec.yaml dependencies.
class DependencyAnalyzer implements Analyzer {
  DependencyAnalyzer({
    FileScanner? scanner,
    http.Client? httpClient,
    this.checkPubDev = true,
    this.checkAdvisories = true,
  })  : _scanner = scanner ?? const FileScanner(),
        _http = httpClient ?? http.Client();

  final FileScanner _scanner;
  final http.Client _http;

  /// When false, skips network calls (useful for tests / offline CI).
  final bool checkPubDev;

  /// When true (and [checkPubDev] is true), queries OSV for Pub advisories.
  final bool checkAdvisories;

  static const _knownDeprecated = <String, String>{
    'pedantic': 'Replaced by package:lints / flutter_lints',
    'flutter_launcher_icons_new': 'Prefer flutter_launcher_icons',
    'kiwi': 'Consider injectable / get_it',
  };

  @override
  String get id => 'dependencies';

  @override
  String get name => 'Dependencies';

  @override
  String get description =>
      'Detect outdated, unused, deprecated, vulnerable, and duplicate packages';

  @override
  Future<AnalysisResult> analyze(ProjectContext context) async {
    final issues = <AnalysisIssue>[];
    final metadata = <String, dynamic>{};

    final deps = context.dependencies ?? {};
    final devDeps = context.devDependencies ?? {};
    final allDeps = <String, dynamic>{...deps, ...devDeps}
      ..remove('flutter')
      ..remove('flutter_test')
      ..remove('flutter_localizations')
      ..remove('sdk');

    issues.addAll(_checkDeprecated(allDeps));
    issues.addAll(await _checkUnused(context, allDeps.keys.toSet()));
    issues.addAll(_checkDuplicates(context));

    final outdated = <Map<String, String>>[];
    final advisories = <Map<String, String>>[];
    if (checkPubDev) {
      final results = await _checkOutdated(allDeps);
      issues.addAll(results.issues);
      outdated.addAll(results.outdated);

      if (checkAdvisories) {
        final vuln = await _checkOsvAdvisories(allDeps);
        issues.addAll(vuln.issues);
        advisories.addAll(vuln.advisories);
      }
    }

    metadata['dependencyCount'] = allDeps.length;
    metadata['outdated'] = outdated;
    metadata['advisories'] = advisories;

    final score = AnalysisResult.computeScore(issues);
    return AnalysisResult(
      analyzerName: name,
      score: score,
      issues: issues,
      summary: '${allDeps.length} packages analyzed, ${issues.length} issue(s).',
      metadata: metadata,
    );
  }

  List<AnalysisIssue> _checkDeprecated(Map<String, dynamic> deps) {
    final issues = <AnalysisIssue>[];
    for (final entry in deps.entries) {
      final note = _knownDeprecated[entry.key];
      if (note != null) {
        issues.add(
          AnalysisIssue(
            ruleId: 'deps.deprecated',
            message: 'Deprecated package "${entry.key}": $note.',
            severity: Severity.warning,
            filePath: 'pubspec.yaml',
            suggestion: note,
          ),
        );
      }
    }
    return issues;
  }

  Future<List<AnalysisIssue>> _checkUnused(
    ProjectContext context,
    Set<String> packageNames,
  ) async {
    final issues = <AnalysisIssue>[];
    if (packageNames.isEmpty) return issues;

    // Packages commonly referenced without a dart import.
    const alwaysUsed = {
      'flutter',
      'cupertino_icons',
      'flutter_lints',
      'lints',
      'build_runner',
      'json_serializable',
      'freezed',
      'freezed_annotation',
      'json_annotation',
      'riverpod_generator',
      'go_router_builder',
      'flutter_gen',
      'flutter_launcher_icons',
      'flutter_native_splash',
      'intl_utils',
      'mockito',
      'build_verify',
      'source_gen',
    };

    final used = <String>{};
    for (final file in context.dartFiles) {
      final content = await _scanner.readFile(file);
      if (content == null) continue;
      for (final name in packageNames) {
        if (content.contains('package:$name/')) {
          used.add(name);
        }
      }
    }

    // Also scan test/ and bin/
    for (final dirName in ['test', 'bin', 'integration_test']) {
      final dir = Directory(p.join(context.rootPath, dirName));
      if (!await dir.exists()) continue;
      final files = await _scanner.findDartFiles(dir.path);
      for (final file in files) {
        final content = await _scanner.readFile(file);
        if (content == null) continue;
        for (final name in packageNames) {
          if (content.contains('package:$name/')) {
            used.add(name);
          }
        }
      }
    }

    for (final name in packageNames) {
      if (alwaysUsed.contains(name)) continue;
      if (used.contains(name)) continue;
      issues.add(
        AnalysisIssue(
          ruleId: 'deps.unused',
          message: 'Possibly unused dependency: $name.',
          severity: Severity.info,
          filePath: 'pubspec.yaml',
          suggestion:
              'Remove if unused, or verify it is only referenced from native/codegen.',
        ),
      );
    }
    return issues;
  }

  List<AnalysisIssue> _checkDuplicates(ProjectContext context) {
    final issues = <AnalysisIssue>[];
    final deps = context.dependencies ?? {};
    final devDeps = context.devDependencies ?? {};

    for (final name in deps.keys) {
      if (devDeps.containsKey(name) &&
          name != 'flutter' &&
          name != 'flutter_test') {
        issues.add(
          AnalysisIssue(
            ruleId: 'deps.duplicate',
            message:
                'Package "$name" appears in both dependencies and dev_dependencies.',
            severity: Severity.warning,
            filePath: 'pubspec.yaml',
            suggestion: 'Keep it in only one section.',
          ),
        );
      }
    }
    return issues;
  }

  Future<({List<AnalysisIssue> issues, List<Map<String, String>> outdated})>
      _checkOutdated(Map<String, dynamic> deps) async {
    final issues = <AnalysisIssue>[];
    final outdated = <Map<String, String>>[];

    for (final entry in deps.entries) {
      final name = entry.key;
      final constraint = _constraintToString(entry.value);
      if (constraint == null) continue;
      if (constraint == 'any') continue;

      try {
        final latest = await _fetchLatestVersion(name);
        if (latest == null) continue;

        final current = _extractVersion(constraint);
        if (current == null) continue;

        if (_isOlder(current, latest)) {
          outdated.add({
            'package': name,
            'current': current,
            'latest': latest,
          });
          issues.add(
            AnalysisIssue(
              ruleId: 'deps.outdated',
              message: '$name is outdated (current: $current, latest: $latest).',
              severity: Severity.info,
              filePath: 'pubspec.yaml',
              suggestion: 'Run `dart pub outdated` and upgrade when ready.',
              context: 'Current: $current\nLatest: $latest',
            ),
          );
        }
      } on Exception {
        // Network failures are non-fatal.
      }
    }

    return (issues: issues, outdated: outdated);
  }

  Future<({List<AnalysisIssue> issues, List<Map<String, String>> advisories})>
      _checkOsvAdvisories(Map<String, dynamic> deps) async {
    final issues = <AnalysisIssue>[];
    final advisories = <Map<String, String>>[];

    for (final entry in deps.entries) {
      final name = entry.key;
      final constraint = _constraintToString(entry.value);
      if (constraint == null) continue;
      final version = _extractVersion(constraint);
      if (version == null) continue;

      try {
        final uri = Uri.parse('https://api.osv.dev/v1/query');
        final response = await _http
            .post(
              uri,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'package': {'name': name, 'ecosystem': 'Pub'},
                'version': version,
              }),
            )
            .timeout(const Duration(seconds: 8));
        if (response.statusCode != 200) continue;

        final json = jsonDecode(response.body);
        if (json is! Map<String, dynamic>) continue;
        final vulns = json['vulns'];
        if (vulns is! List || vulns.isEmpty) continue;

        for (final vuln in vulns.take(3)) {
          if (vuln is! Map<String, dynamic>) continue;
          final id = '${vuln['id'] ?? 'OSV'}';
          final summary = '${vuln['summary'] ?? 'Known vulnerability'}';
          advisories.add({'package': name, 'id': id, 'version': version});
          issues.add(
            AnalysisIssue(
              ruleId: 'deps.advisory',
              message: 'Security advisory $id for $name@$version: $summary',
              severity: Severity.critical,
              filePath: 'pubspec.yaml',
              suggestion:
                  'Upgrade $name to a patched version. See https://osv.dev/vulnerability/$id',
              context: id,
            ),
          );
        }
      } on Exception {
        // Network failures are non-fatal.
      }
    }

    return (issues: issues, advisories: advisories);
  }

  Future<String?> _fetchLatestVersion(String packageName) async {
    final uri = Uri.parse('https://pub.dev/api/packages/$packageName');
    final response = await _http.get(uri).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) return null;
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final latest = json['latest'] as Map<String, dynamic>?;
    return latest?['version'] as String?;
  }

  String? _constraintToString(dynamic value) {
    if (value is String) return value;
    if (value is YamlMap) {
      // sdk / git / path deps
      if (value.containsKey('sdk') ||
          value.containsKey('git') ||
          value.containsKey('path')) {
        return null;
      }
      final version = value['version'];
      if (version is String) return version;
    }
    return value?.toString();
  }

  String? _extractVersion(String constraint) {
    final match = RegExp(r'(\d+\.\d+\.\d+)').firstMatch(constraint);
    return match?.group(1);
  }

  bool _isOlder(String current, String latest) {
    List<int> parse(String v) =>
        v.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final a = parse(current);
    final b = parse(latest);
    for (var i = 0; i < 3; i++) {
      final av = i < a.length ? a[i] : 0;
      final bv = i < b.length ? b[i] : 0;
      if (av < bv) return true;
      if (av > bv) return false;
    }
    return false;
  }
}
