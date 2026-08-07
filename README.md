# StackChain Analyzer

![StackChain Health](https://img.shields.io/badge/stackchain%20health-CLI-blue)
[![pub package](https://img.shields.io/pub/v/stackchain_analyzer.svg)](https://pub.dev/packages/stackchain_analyzer)

Flutter project health analyzer for the **StackChain** ecosystem.

Think of it as **Flutter Doctor for project health**, with SonarQube-style quality checks and a mobile release checklist — all in one Dart CLI.

```
stackchain analyze
stackchain analyze architecture
stackchain analyze security --format sarif
stackchain analyze release --strict
stackchain analyze --baseline
stackchain analyze --format badge
```

## Features

| Analyzer | What it checks |
|---|---|
| **Architecture** | Layer violations, missing domain, circular deps, logic in widgets, oversized features |
| **Performance** | Large `build` methods, excessive `setState`, `ListView` misuse, `FutureBuilder` pitfalls, missing `const`, large assets |
| **Security** | Hardcoded secrets, HTTP URLs, insecure storage, Android debuggable/backup/permissions, iOS ATS |
| **Dependencies** | Outdated packages, deprecated packages, unused deps, duplicates, **OSV advisories** |
| **Release** | Signing, versionCode, R8/ProGuard, iOS privacy keys, TODOs, debug prints (`--strict` gate) |
| **Quality** | Large files, long methods, TODO/FIXME, naming, duplicate blocks, dead files |
| **Riverpod** | `ref.read` in build, missing `.select`, scope/container misuse |
| **Bloc** | Missing `close`, events in build, missing `buildWhen` |
| **GetX** | `Get.put` in build, missing `onClose`, `Get.find` in `Obx` |

### Team adoption tooling

- **`.stackchain.yaml`** — ignore rules, severity overrides, min scores
- **Baseline mode** — only fail on *new* issues (`--baseline` / `--update-baseline`)
- **SARIF** — GitHub Code Scanning upload (`--format sarif`)
- **Badge** — README shield (`--format badge`)
- **GitHub Action** — copy from [`tool/github_action/stackchain.yml`](tool/github_action/stackchain.yml)

## Install

```sh
dart pub global activate stackchain_analyzer
```

Or add as a dev dependency:

```yaml
dev_dependencies:
  stackchain_analyzer: ^0.2.0
```

## Usage

```sh
# Full health scan
stackchain analyze

# Single / multiple domains
stackchain analyze architecture
stackchain analyze performance quality riverpod

# Strict release preflight (Play/App Store gate)
stackchain analyze release --strict

# JSON / CI / SARIF / badge
stackchain analyze --format json
stackchain analyze --format ci --fail-on-warning
stackchain analyze --format sarif > stackchain.sarif
stackchain analyze --format badge

# Baseline (gradual adoption)
stackchain analyze --update-baseline   # once on main
stackchain analyze --baseline          # PRs only fail on new issues

# Offline (skip pub.dev + OSV)
stackchain analyze --offline

# Custom config
stackchain analyze --config .stackchain.yaml

# List analyzers
stackchain analyze --list
```

### `.stackchain.yaml`

```yaml
analyzers:
  disabled: [getx]

ignore:
  - quality.todo
  - rule: deps.outdated
    path: "lib/generated/**"

severity_overrides:
  perf.missing_const: info

fail:
  on_warning: false
  min_score: 70
  strict_release: false

thresholds:
  security: 80

baseline:
  path: .stackchain/baseline.json
```

See [`example/stackchain.yaml`](example/stackchain.yaml) for a full template.

### Exit codes

| Code | Meaning |
|------|---------|
| `0` | Success / no critical or error findings |
| `1` | Issues found (or below `min_score` / thresholds) |
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

## GitHub Action

```yaml
- uses: dart-lang/setup-dart@v1
- run: dart pub global activate stackchain_analyzer
- run: dart pub global run stackchain_analyzer:stackchain analyze --format sarif > stackchain.sarif
- uses: github/codeql-action/upload-sarif@v3
  with:
    sarif_file: stackchain.sarif
```

Full workflow: [`tool/github_action/stackchain.yml`](tool/github_action/stackchain.yml)

## Programmatic API

```dart
import 'package:stackchain_analyzer/stackchain_analyzer.dart';

Future<void> main() async {
  final engine = AnalysisEngine();
  final report = await engine.run(
    projectPath: '.',
    config: await StackChainConfig.load(projectPath: '.'),
    useBaseline: true,
  );
  print('Health: ${report.overallScore}/100');
}
```

## Plugin architecture

```dart
abstract class Analyzer {
  String get id;
  String get name;
  String get description;
  Future<AnalysisResult> analyze(ProjectContext context);
}
```

Register custom analyzers via `AnalyzerRegistry`.

## License

MIT
