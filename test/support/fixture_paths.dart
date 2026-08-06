import 'dart:io';

import 'package:path/path.dart' as p;

/// Absolute path to this package root.
final String packageRoot = () {
  // test/support → test → package root
  return p.normalize(
    p.join(Directory.current.path),
  );
}();

/// Fixture Flutter app used by analyzer tests.
final String fixtureFlutterRoot = p.join(
  packageRoot,
  'test',
  'fixtures',
  'sample_flutter',
);
