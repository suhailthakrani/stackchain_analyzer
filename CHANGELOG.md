# Changelog

## 0.1.0

- Initial release of `stackchain_analyzer`
- CLI: `stackchain analyze` with architecture, performance, security, dependencies, release, and quality analyzers
- Output formats: console, JSON, CI (GitHub Actions annotations)
- Extensible `Analyzer` plugin interface and `AnalyzerRegistry`
- Exit codes suitable for CI/CD gates
