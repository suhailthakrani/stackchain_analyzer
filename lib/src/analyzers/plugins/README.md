# Future analyzer plugins

Implement [Analyzer](../lib/src/analyzers/analyzer.dart) and register via
`AnalyzerRegistry`:

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
    // ...
    return AnalysisResult(analyzerName: name, score: 100, issues: []);
  }
}
```

Planned domains:

- `firebase` — rules, insecure rules files, missing App Check
- `riverpod` — provider misuse, missing `ref.watch` vs `ref.read`
- `bloc` — event/state patterns, close() leaks
- `getx` — controller disposal, reactive anti-patterns
- `localization` — missing ARB keys, hardcoded UI strings
- `accessibility` — Semantics, contrast, tap targets
