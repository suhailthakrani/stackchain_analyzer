import '../models/analysis_result.dart';
import '../models/project_context.dart';

/// Plugin contract for StackChain analyzers.
///
/// Implement this interface to add new analysis domains
/// (e.g. Firebase, Riverpod, Bloc, GetX, localization, a11y).
abstract class Analyzer {
  /// Unique machine-readable identifier (e.g. `architecture`).
  String get id;

  /// Human-readable display name.
  String get name;

  /// Short description shown in help text.
  String get description;

  /// Run analysis against [context] and return findings.
  Future<AnalysisResult> analyze(ProjectContext context);
}
