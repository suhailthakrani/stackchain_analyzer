import 'stackchain_analyzer.dart' as entry;

/// Alias executable so `dart pub global run stackchain` works.
Future<void> main(List<String> arguments) => entry.main(arguments);
