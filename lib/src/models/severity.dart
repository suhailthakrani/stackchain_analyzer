/// Severity level for an analysis finding.
enum Severity {
  critical,
  error,
  warning,
  info;

  String get label => name.toUpperCase();

  int get weight => switch (this) {
        Severity.critical => 25,
        Severity.error => 15,
        Severity.warning => 5,
        Severity.info => 1,
      };

  static Severity fromString(String value) {
    return Severity.values.firstWhere(
      (s) => s.name == value.toLowerCase(),
      orElse: () => Severity.info,
    );
  }
}
