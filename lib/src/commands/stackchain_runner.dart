import 'package:args/command_runner.dart';

import 'analyze_command.dart';

/// StackChain Analyzer CLI entrypoint wiring.
class StackChainCommandRunner extends CommandRunner<void> {
  StackChainCommandRunner()
      : super(
          'stackchain',
          'Flutter project health analyzer for the StackChain ecosystem.\n\n'
          'Run `stackchain analyze` to scan a Flutter project, or pass an '
          'analyzer name (architecture, performance, security, dependencies, '
          'release, quality).',
        ) {
    addCommand(AnalyzeCommand());
  }

  static const version = '0.2.1';
}
