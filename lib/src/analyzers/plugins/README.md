# Analyzer plugins

Built-in plugins live under `architecture/`, `performance/`, `security/`,
`dependencies/`, `release/`, `quality/`, and `state/` (Riverpod / Bloc / GetX).

Implement [Analyzer](../analyzer.dart) and register via `AnalyzerRegistry`:

```dart
class FirebaseAnalyzer implements Analyzer {
  @override
  String get id => 'firebase';
  @override
  String get name => 'Firebase';
  @override
  String get description => 'Firebase configuration and usage checks';

  @override
  Future<AnalysisResult> analyze(ProjectContext context) async {
    return AnalysisResult(analyzerName: name, score: 100, issues: []);
  }
}
```

Still planned:

- `firebase` — rules, insecure configs, missing App Check
- `localization` — missing ARB keys, hardcoded UI strings
- `accessibility` — Semantics, tap targets
