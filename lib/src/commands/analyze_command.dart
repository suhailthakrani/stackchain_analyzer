import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../analyzers/analyzer.dart';
import '../analyzers/analyzer_registry.dart';
import '../analyzers/architecture/architecture_analyzer.dart';
import '../analyzers/dependencies/dependency_analyzer.dart';
import '../analyzers/performance/performance_analyzer.dart';
import '../analyzers/quality/quality_analyzer.dart';
import '../analyzers/release/release_analyzer.dart';
import '../analyzers/security/security_analyzer.dart';
import '../analyzers/state/bloc_analyzer.dart';
import '../analyzers/state/getx_analyzer.dart';
import '../analyzers/state/riverpod_analyzer.dart';
import '../config/stackchain_config.dart';
import '../reporters/reporter.dart';
import '../utils/exit_codes.dart';
import 'analysis_engine.dart';

/// Top-level `analyze` command.
///
/// Examples:
///   stackchain analyze
///   stackchain analyze architecture
///   stackchain analyze release --strict
///   stackchain analyze --format sarif
///   stackchain analyze --baseline --update-baseline
class AnalyzeCommand extends Command<void> {
  AnalyzeCommand({AnalysisEngine? engine}) : _injectedEngine = engine {
    argParser
      ..addOption(
        'path',
        abbr: 'p',
        defaultsTo: '.',
        help: 'Path to the Flutter project root.',
      )
      ..addOption(
        'config',
        abbr: 'c',
        help: 'Path to .stackchain.yaml (defaults to <path>/.stackchain.yaml).',
      )
      ..addOption(
        'format',
        abbr: 'f',
        allowed: ['console', 'json', 'ci', 'sarif', 'badge'],
        defaultsTo: 'console',
        help: 'Output format.',
      )
      ..addFlag(
        'color',
        defaultsTo: true,
        help: 'Enable ANSI colors in console output.',
      )
      ..addFlag(
        'verbose',
        abbr: 'v',
        negatable: false,
        help: 'Show additional detail.',
      )
      ..addFlag(
        'fail-on-warning',
        negatable: false,
        help: 'Exit with code 1 when warnings are present.',
      )
      ..addFlag(
        'strict',
        negatable: false,
        help: 'Strict release gate (signing, minify, no prints).',
      )
      ..addFlag(
        'offline',
        negatable: false,
        help: 'Skip network checks (pub.dev + OSV advisories).',
      )
      ..addFlag(
        'baseline',
        negatable: false,
        help: 'Only report issues not in the saved baseline.',
      )
      ..addFlag(
        'update-baseline',
        negatable: false,
        help: 'Write current issues to the baseline file.',
      )
      ..addFlag(
        'list',
        abbr: 'l',
        negatable: false,
        help: 'List available analyzers and exit.',
      );
  }

  final AnalysisEngine? _injectedEngine;

  @override
  String get name => 'analyze';

  @override
  String get description =>
      'Analyze Flutter project health (architecture, performance, security, …).';

  @override
  String get invocation =>
      'stackchain analyze [analyzer…] [arguments]';

  @override
  Future<void> run() async {
    final results = argResults!;
    final registry = AnalyzerRegistry();

    if (results['list'] as bool) {
      stdout.writeln('Available analyzers:');
      for (final a in registry.all) {
        stdout.writeln('  ${a.id.padRight(14)} ${a.description}');
      }
      return;
    }

    final analyzerIds = results.rest;
    final path = results['path'] as String;
    final configPath = results['config'] as String?;
    final format = ReportFormat.parse(results['format'] as String);
    final color = results['color'] as bool;
    final verbose = results['verbose'] as bool;
    final failOnWarning = results['fail-on-warning'] as bool;
    final offline = results['offline'] as bool;
    final strict = results['strict'] as bool;
    final useBaseline = results['baseline'] as bool;
    final updateBaseline = results['update-baseline'] as bool;

    final absolutePath = p.normalize(p.absolute(path));
    final config = await StackChainConfig.load(
      projectPath: absolutePath,
      explicitPath: configPath,
    );

    final effectiveStrict = strict || config.strictRelease;

    final engine = _injectedEngine ??
        AnalysisEngine(
          registry: AnalyzerRegistry(
            analyzers: _buildAnalyzers(
              offline: offline,
              strictRelease: effectiveStrict,
            ),
          ),
        );

    try {
      final resolvedIds = config.resolveAnalyzerIds(analyzerIds);
      if (resolvedIds.isNotEmpty || analyzerIds.isNotEmpty) {
        engine.registry.resolve(
          resolvedIds.isEmpty ? analyzerIds : resolvedIds,
        );
      }

      final report = await engine.run(
        projectPath: path,
        analyzerIds: analyzerIds,
        config: config,
        useBaseline: useBaseline,
        updateBaseline: updateBaseline,
      );

      final reporter = engine.createReporter(
        format: format,
        color: color && stdout.hasTerminal,
        verbose: verbose,
      );
      reporter.write(report);

      if (updateBaseline) {
        stdout.writeln(
          'Baseline updated: ${config.baselinePath}',
        );
      }

      exitCode = engine.exitCodeFor(
        report,
        failOnWarning: failOnWarning,
        config: config,
      );
    } on StateError catch (e) {
      stderr.writeln(e.message);
      exitCode = ExitCodes.notFlutterProject;
    } on ArgumentError catch (e) {
      stderr.writeln('${e.message}');
      stderr.writeln(
        'Available: ${registry.all.map((a) => a.id).join(', ')}',
      );
      exitCode = ExitCodes.usageError;
    } on Exception catch (e, st) {
      stderr.writeln('Unexpected error: $e');
      if (verbose) stderr.writeln(st);
      exitCode = ExitCodes.unexpectedError;
    }
  }

  List<Analyzer> _buildAnalyzers({
    required bool offline,
    required bool strictRelease,
  }) =>
      [
        ArchitectureAnalyzer(),
        PerformanceAnalyzer(),
        SecurityAnalyzer(),
        DependencyAnalyzer(
          checkPubDev: !offline,
          checkAdvisories: !offline,
        ),
        ReleaseAnalyzer(strict: strictRelease),
        QualityAnalyzer(),
        RiverpodAnalyzer(),
        BlocAnalyzer(),
        GetxAnalyzer(),
      ];
}
