import 'dart:io';

import 'package:args/command_runner.dart';

import '../analyzers/analyzer.dart';
import '../analyzers/analyzer_registry.dart';
import '../analyzers/architecture/architecture_analyzer.dart';
import '../analyzers/dependencies/dependency_analyzer.dart';
import '../analyzers/performance/performance_analyzer.dart';
import '../analyzers/quality/quality_analyzer.dart';
import '../analyzers/release/release_analyzer.dart';
import '../analyzers/security/security_analyzer.dart';
import '../reporters/reporter.dart';
import '../utils/exit_codes.dart';
import 'analysis_engine.dart';

/// Top-level `analyze` command.
///
/// Examples:
///   stackchain analyze
///   stackchain analyze architecture
///   stackchain analyze performance security
///   stackchain analyze --format json
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
        'format',
        abbr: 'f',
        allowed: ['console', 'json', 'ci'],
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
        'offline',
        negatable: false,
        help: 'Skip network checks (e.g. pub.dev outdated lookup).',
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
      'stackchain analyze [architecture|performance|security|dependencies|release|quality] [arguments]';

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
    final format = ReportFormat.parse(results['format'] as String);
    final color = results['color'] as bool;
    final verbose = results['verbose'] as bool;
    final failOnWarning = results['fail-on-warning'] as bool;
    final offline = results['offline'] as bool;

    final engine = _injectedEngine ??
        AnalysisEngine(
          registry: AnalyzerRegistry(
            analyzers: _buildAnalyzers(offline: offline),
          ),
        );

    try {
      if (analyzerIds.isNotEmpty) {
        // Validate early for clearer errors.
        engine.registry.resolve(analyzerIds);
      }

      final report = await engine.run(
        projectPath: path,
        analyzerIds: analyzerIds,
      );

      final reporter = engine.createReporter(
        format: format,
        color: color && stdout.hasTerminal,
        verbose: verbose,
      );
      reporter.write(report);

      exitCode = engine.exitCodeFor(
        report,
        failOnWarning: failOnWarning,
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

  List<Analyzer> _buildAnalyzers({required bool offline}) => [
        ArchitectureAnalyzer(),
        PerformanceAnalyzer(),
        SecurityAnalyzer(),
        DependencyAnalyzer(checkPubDev: !offline),
        ReleaseAnalyzer(),
        QualityAnalyzer(),
      ];
}
