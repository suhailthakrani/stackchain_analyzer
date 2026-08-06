# StackChain Analyzer

Flutter project health analyzer for the **StackChain** ecosystem.

Think of it as **Flutter Doctor for project health**, with SonarQube-style quality checks and a mobile release checklist — all in one Dart CLI.

```
stackchain analyze
stackchain analyze architecture
stackchain analyze performance
stackchain analyze security
stackchain analyze dependencies
stackchain analyze release
stackchain analyze --format json
```

## Features

| Analyzer | What it checks |
|---|---|
| **Architecture** | Layer violations, missing domain, circular deps, logic in widgets, oversized features |
| **Performance** | Large `build` methods, excessive `setState`, `ListView` misuse, `FutureBuilder` pitfalls, missing `const`, large assets |
| **Security** | Hardcoded secrets, HTTP URLs, insecure storage, Android debuggable/backup/permissions, iOS ATS |
| **Dependencies** | Outdated packages (pub.dev), deprecated packages, unused deps, duplicates |
| **Release** | Signing, versionCode, R8/ProGuard, iOS privacy keys, TODOs, debug prints |
| **Quality** | Large files, long methods, TODO/FIXME, naming, duplicate blocks, dead files |

## Install

```sh
dart pub global activate stackchain_analyzer
```

Or add as a dev dependency:

```yaml
dev_dependencies:
  stackchain_analyzer: ^0.1.0
```

## Usage

From any Flutter project root:

```sh
# Full health scan
stackchain analyze

# Single domain
stackchain analyze architecture
stackchain analyze security

# Multiple domains
stackchain analyze performance quality

# JSON for tooling / dashboards
stackchain analyze --format json

# CI annotations (GitHub Actions compatible)
stackchain analyze --format ci --fail-on-warning

# Offline (skip pub.dev lookups)
stackchain analyze dependencies --offline

# Analyze another path
stackchain analyze --path ../my_app

# List analyzers
stackchain analyze --list
```

### Exit codes

| Code | Meaning |
|------|---------|
| `0` | Success / no critical or error findings |
| `1` | Issues found (critical or error; or warnings with `--fail-on-warning`) |
| `2` | Not a Flutter project |
| `64` | Usage error |
| `70` | Unexpected failure |

## Example output

```
StackChain Analyzer
────────────────────────────────────────

Project: Ummah Connect

Health Score:

  Architecture   ████████░░ 82
  Performance    ███████░░░ 74
  Security       ██████░░░░ 60
  Release        █████████░ 90

  Overall        ███████░░░ 76

────────────────────────────────────────

12 Issues Found

  Critical: 1
  Error:    2
  Warning:  8
  Info:     1
```

## Programmatic API

```dart
import 'package:stackchain_analyzer/stackchain_analyzer.dart';

Future<void> main() async {
  final engine = AnalysisEngine(
    registry: AnalyzerRegistry(
      analyzers: [
        ArchitectureAnalyzer(),
        SecurityAnalyzer(),
        DependencyAnalyzer(checkPubDev: false),
      ],
    ),
  );

  final report = await engine.run(projectPath: '.');
  print('Health: ${report.overallScore}/100');
  print(report.toJson());
}
```

## Plugin architecture

Analyzers implement a simple contract:

```dart
abstract class Analyzer {
  String get id;
  String get name;
  String get description;
  Future<AnalysisResult> analyze(ProjectContext context);
}
```

Register custom analyzers via `AnalyzerRegistry`:

```dart
AnalyzerRegistry(
  analyzers: [
    ...AnalyzerRegistry.defaultAnalyzers(),
    MyFirebaseAnalyzer(),
    MyRiverpodAnalyzer(),
  ],
);
```

### Planned plugins

- Firebase analyzer
- Riverpod analyzer
- Bloc analyzer
- GetX analyzer
- Localization analyzer
- Accessibility analyzer

## Project detection

The tool expects a Flutter project (`pubspec.yaml` with a `flutter` dependency) and inspects:

- `pubspec.yaml` / `analysis_options.yaml`
- `lib/`
- `android/` / `ios/` / `web/`
- assets

If the path is not a Flutter project:

```
This is not a Flutter project
```

## Development

```sh
dart pub get
dart test
dart run bin/stackchain_analyzer.dart analyze --path test/fixtures/sample_flutter --offline
```

## License

MIT
