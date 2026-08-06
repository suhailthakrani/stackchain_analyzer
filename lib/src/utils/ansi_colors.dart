import 'dart:io';

/// ANSI terminal styling helpers.
abstract final class AnsiColors {
  static bool get supported {
    if (stdout.hasTerminal) return true;
    final term = Platform.environment['TERM'];
    return term != null && term != 'dumb';
  }

  static String wrap(String text, String code, {bool enabled = true}) {
    if (!enabled || !supported) return text;
    return '$code$text\x1B[0m';
  }

  static String bold(String text, {bool enabled = true}) =>
      wrap(text, '\x1B[1m', enabled: enabled);

  static String dim(String text, {bool enabled = true}) =>
      wrap(text, '\x1B[2m', enabled: enabled);

  static String red(String text, {bool enabled = true}) =>
      wrap(text, '\x1B[31m', enabled: enabled);

  static String green(String text, {bool enabled = true}) =>
      wrap(text, '\x1B[32m', enabled: enabled);

  static String yellow(String text, {bool enabled = true}) =>
      wrap(text, '\x1B[33m', enabled: enabled);

  static String blue(String text, {bool enabled = true}) =>
      wrap(text, '\x1B[34m', enabled: enabled);

  static String cyan(String text, {bool enabled = true}) =>
      wrap(text, '\x1B[36m', enabled: enabled);

  static String magenta(String text, {bool enabled = true}) =>
      wrap(text, '\x1B[35m', enabled: enabled);
}
