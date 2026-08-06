import 'package:stackchain_analyzer/stackchain_analyzer.dart';
import 'package:test/test.dart';

import 'support/fixture_paths.dart';

void main() {
  group('ProjectDetector', () {
    final detector = ProjectDetector();

    test('detects Flutter fixture project', () async {
      expect(await detector.isFlutterProject(fixtureFlutterRoot), isTrue);
    });

    test('rejects non-Flutter directory', () async {
      expect(await detector.isFlutterProject(packageRoot), isFalse);
    });

    test('loads ProjectContext', () async {
      final ctx = await detector.load(fixtureFlutterRoot);
      expect(ctx.projectName, 'sample_app');
      expect(ctx.isFlutterProject, isTrue);
      expect(ctx.hasAndroid, isTrue);
      expect(ctx.hasIos, isTrue);
      expect(ctx.dartFiles, isNotEmpty);
      expect(ctx.architectureStyle, ArchitectureStyle.featureFirst);
    });

    test('throws for non-Flutter project', () async {
      expect(
        () => detector.load(packageRoot),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'This is not a Flutter project',
          ),
        ),
      );
    });
  });
}
