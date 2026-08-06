import 'dart:io';

import 'package:args/command_runner.dart';

import 'package:stackchain_analyzer/src/commands/stackchain_runner.dart';
import 'package:stackchain_analyzer/src/utils/exit_codes.dart';

Future<void> main(List<String> arguments) async {
  final runner = StackChainCommandRunner();

  if (arguments.contains('--version') || arguments.contains('-V')) {
    stdout.writeln('stackchain_analyzer ${StackChainCommandRunner.version}');
    return;
  }

  try {
    await runner.run(arguments.isEmpty ? ['analyze'] : arguments);
  } on UsageException catch (e) {
    stderr.writeln(e.message);
    stderr.writeln(e.usage);
    exitCode = ExitCodes.usageError;
  }
}
