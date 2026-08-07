import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../models/severity.dart';

/// Project-level configuration loaded from `.stackchain.yaml`.
class StackChainConfig {
  const StackChainConfig({
    this.enabledAnalyzers = const [],
    this.disabledAnalyzers = const [],
    this.ignoreRules = const [],
    this.severityOverrides = const {},
    this.failOnWarning = false,
    this.minScore,
    this.strictRelease = false,
    this.analyzerMinScores = const {},
    this.baselinePath = '.stackchain/baseline.json',
  });

  /// Empty / default config when no file is present.
  static const empty = StackChainConfig();

  final List<String> enabledAnalyzers;
  final List<String> disabledAnalyzers;
  final List<IgnoreRule> ignoreRules;
  final Map<String, Severity> severityOverrides;
  final bool failOnWarning;
  final int? minScore;
  final bool strictRelease;
  final Map<String, int> analyzerMinScores;
  final String baselinePath;

  /// Load from [projectPath] / `.stackchain.yaml` (or [explicitPath]).
  static Future<StackChainConfig> load({
    required String projectPath,
    String? explicitPath,
  }) async {
    final file = File(
      explicitPath ?? p.join(projectPath, '.stackchain.yaml'),
    );
    if (!await file.exists()) return empty;

    final yaml = loadYaml(await file.readAsString());
    if (yaml is! YamlMap) return empty;
    return StackChainConfig.fromYaml(yaml);
  }

  factory StackChainConfig.fromYaml(YamlMap yaml) {
    final analyzers = yaml['analyzers'];
    final ignore = yaml['ignore'];
    final overrides = yaml['severity_overrides'];
    final fail = yaml['fail'];
    final thresholds = yaml['thresholds'];

    final enabled = <String>[];
    final disabled = <String>[];
    if (analyzers is YamlMap) {
      final e = analyzers['enabled'];
      final d = analyzers['disabled'];
      if (e is YamlList) {
        enabled.addAll(e.map((v) => '$v'.toLowerCase()));
      }
      if (d is YamlList) {
        disabled.addAll(d.map((v) => '$v'.toLowerCase()));
      }
    }

    final ignoreRules = <IgnoreRule>[];
    if (ignore is YamlList) {
      for (final item in ignore) {
        if (item is String) {
          ignoreRules.add(IgnoreRule(ruleId: item));
        } else if (item is YamlMap) {
          ignoreRules.add(
            IgnoreRule(
              ruleId: '${item['rule'] ?? item['id'] ?? ''}',
              pathGlob: item['path'] as String?,
            ),
          );
        }
      }
    }

    final severityOverrides = <String, Severity>{};
    if (overrides is YamlMap) {
      for (final entry in overrides.entries) {
        severityOverrides['${entry.key}'] =
            Severity.fromString('${entry.value}');
      }
    }

    var failOnWarning = false;
    int? minScore;
    var strictRelease = false;
    if (fail is YamlMap) {
      failOnWarning = fail['on_warning'] == true;
      final ms = fail['min_score'];
      if (ms is int) minScore = ms;
      if (ms is num) minScore = ms.round();
      strictRelease = fail['strict_release'] == true;
    }

    final analyzerMinScores = <String, int>{};
    if (thresholds is YamlMap) {
      for (final entry in thresholds.entries) {
        final v = entry.value;
        if (v is int) analyzerMinScores['${entry.key}'] = v;
        if (v is num) analyzerMinScores['${entry.key}'] = v.round();
      }
    }

    final baseline = yaml['baseline'];
    final baselinePath = baseline is YamlMap
        ? (baseline['path'] as String? ?? '.stackchain/baseline.json')
        : (baseline is String ? baseline : '.stackchain/baseline.json');

    return StackChainConfig(
      enabledAnalyzers: enabled,
      disabledAnalyzers: disabled,
      ignoreRules: ignoreRules,
      severityOverrides: severityOverrides,
      failOnWarning: failOnWarning,
      minScore: minScore,
      strictRelease: strictRelease,
      analyzerMinScores: analyzerMinScores,
      baselinePath: baselinePath,
    );
  }

  /// Resolve which analyzer ids to run given CLI rest args.
  List<String> resolveAnalyzerIds(List<String> cliIds) {
    if (cliIds.isNotEmpty) {
      return cliIds
          .map((e) => e.toLowerCase())
          .where((id) => !disabledAnalyzers.contains(id))
          .toList();
    }
    if (enabledAnalyzers.isNotEmpty) {
      return enabledAnalyzers
          .where((id) => !disabledAnalyzers.contains(id))
          .toList();
    }
    return const [];
  }

  bool isIgnored({
    required String ruleId,
    String? filePath,
  }) {
    for (final rule in ignoreRules) {
      if (rule.ruleId.isEmpty) continue;
      final ruleMatch =
          rule.ruleId == ruleId || rule.ruleId == '*' || ruleId.startsWith('${rule.ruleId}.');
      // Also allow exact and prefix: "quality" matches "quality.todo"
      final prefixMatch = ruleId.startsWith('${rule.ruleId}.') ||
          rule.ruleId == ruleId;
      if (!ruleMatch && !prefixMatch) continue;
      if (rule.pathGlob == null || rule.pathGlob!.isEmpty) return true;
      if (filePath != null && _matchGlob(rule.pathGlob!, filePath)) {
        return true;
      }
    }
    return false;
  }

  static bool _matchGlob(String glob, String path) {
    // Minimal glob: ** / * support.
    final normalized = path.replaceAll('\\', '/');
    final pattern = glob.replaceAll('\\', '/');
    final regex = RegExp(
      '^${RegExp.escape(pattern).replaceAll(r'\*\*', '.*').replaceAll(r'\*', '[^/]*')}\$',
      caseSensitive: false,
    );
    return regex.hasMatch(normalized);
  }
}

/// A single ignore entry from config.
class IgnoreRule {
  const IgnoreRule({required this.ruleId, this.pathGlob});

  final String ruleId;
  final String? pathGlob;
}
