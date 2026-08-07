# Changelog

## 0.2.1

- Widen `analyzer` to `>=6.0.0 <15.0.0` so Flutter apps using `flutter_test` / `bloc_test` can resolve
- Make NamedType helpers compatible with analyzer 7.x and 8+

## 0.2.0

- Add `.stackchain.yaml` config (ignore rules, severity overrides, score gates)
- Add baseline / diff mode (`--baseline`, `--update-baseline`)
- Add SARIF reporter (`--format sarif`) for GitHub Code Scanning
- Add badge reporter (`--format badge`) for README shields
- Add Riverpod, Bloc, and GetX analyzers
- Add OSV security advisory checks for Pub packages
- Add `--strict` release gate profile
- Ship reusable GitHub Action at `tool/github_action/stackchain.yml`
- Support Dart SDK `>=3.0.0 <4.0.0` with a broad `analyzer` range
- Fix pubspec metadata for pub.dev (description length, real repository URLs)
- Add `example/example.dart` for documentation score

## 0.1.0

- Initial release of `stackchain_analyzer`
- CLI: `stackchain analyze` with architecture, performance, security, dependencies, release, and quality analyzers
- Output formats: console, JSON, CI (GitHub Actions annotations)
- Extensible `Analyzer` plugin interface and `AnalyzerRegistry`
- Exit codes suitable for CI/CD gates
