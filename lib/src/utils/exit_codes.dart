/// Process exit codes for CI/CD integration.
abstract final class ExitCodes {
  static const int success = 0;
  static const int issuesFound = 1;
  static const int notFlutterProject = 2;
  static const int usageError = 64;
  static const int unexpectedError = 70;
}
