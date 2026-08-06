import 'analyzer.dart';
import 'architecture/architecture_analyzer.dart';
import 'dependencies/dependency_analyzer.dart';
import 'performance/performance_analyzer.dart';
import 'quality/quality_analyzer.dart';
import 'release/release_analyzer.dart';
import 'security/security_analyzer.dart';

/// Registry of available analyzer plugins.
class AnalyzerRegistry {
  AnalyzerRegistry({List<Analyzer>? analyzers})
      : _analyzers = List.unmodifiable(
          analyzers ?? defaultAnalyzers(),
        );

  final List<Analyzer> _analyzers;

  List<Analyzer> get all => _analyzers;

  Analyzer? findById(String id) {
    final normalized = id.toLowerCase();
    for (final analyzer in _analyzers) {
      if (analyzer.id == normalized) return analyzer;
    }
    return null;
  }

  List<Analyzer> resolve(List<String> ids) {
    if (ids.isEmpty) return all;
    final resolved = <Analyzer>[];
    for (final id in ids) {
      final analyzer = findById(id);
      if (analyzer == null) {
        throw ArgumentError('Unknown analyzer: $id');
      }
      resolved.add(analyzer);
    }
    return resolved;
  }

  /// Built-in analyzers shipped with the package.
  static List<Analyzer> defaultAnalyzers() => [
        ArchitectureAnalyzer(),
        PerformanceAnalyzer(),
        SecurityAnalyzer(),
        DependencyAnalyzer(),
        ReleaseAnalyzer(),
        QualityAnalyzer(),
      ];
}
