import 'dart:io';

import 'package:path/path.dart' as p;

import '../../models/analysis_issue.dart';
import '../../models/analysis_result.dart';
import '../../models/project_context.dart';
import '../../models/severity.dart';
import '../../utils/file_scanner.dart';
import '../analyzer.dart';

/// Pre-release readiness checks for Flutter apps.
class ReleaseAnalyzer implements Analyzer {
  ReleaseAnalyzer({FileScanner? scanner})
      : _scanner = scanner ?? const FileScanner();

  final FileScanner _scanner;

  @override
  String get id => 'release';

  @override
  String get name => 'Release';

  @override
  String get description =>
      'Validate signing, versions, privacy keys, and release hygiene';

  @override
  Future<AnalysisResult> analyze(ProjectContext context) async {
    final issues = <AnalysisIssue>[];
    final checks = <String, bool>{};

    if (context.hasAndroid) {
      final android = await _checkAndroid(context);
      issues.addAll(android.issues);
      checks.addAll(android.checks);
    }

    if (context.hasIos) {
      final ios = await _checkIos(context);
      issues.addAll(ios.issues);
      checks.addAll(ios.checks);
    }

    final flutter = await _checkFlutter(context);
    issues.addAll(flutter.issues);
    checks.addAll(flutter.checks);

    final score = AnalysisResult.computeScore(issues);
    return AnalysisResult(
      analyzerName: name,
      score: score,
      issues: issues,
      summary: 'Release readiness: $score%',
      metadata: {'checks': checks},
    );
  }

  Future<({List<AnalysisIssue> issues, Map<String, bool> checks})>
      _checkAndroid(ProjectContext context) async {
    final issues = <AnalysisIssue>[];
    final checks = <String, bool>{};

    final buildGradle = await _findAndroidBuildGradle(context);
    if (buildGradle == null) {
      issues.add(
        const AnalysisIssue(
          ruleId: 'release.android_gradle_missing',
          message: 'Could not locate android/app/build.gradle(.kts).',
          severity: Severity.warning,
        ),
      );
      checks['android_signing'] = false;
      checks['android_minify'] = false;
      return (issues: issues, checks: checks);
    }

    final content = await buildGradle.readAsString();
    final relative = p.relative(buildGradle.path, from: context.rootPath);

    final hasSigning = RegExp(
          r'signingConfigs\s*\{',
        ).hasMatch(content) ||
        RegExp(
          r'signingConfig\s*=\s*signingConfigs\.',
        ).hasMatch(content);
    checks['android_signing'] = hasSigning;
    if (!hasSigning) {
      issues.add(
        AnalysisIssue(
          ruleId: 'release.android_signing',
          message: 'App signing configuration not found.',
          severity: Severity.error,
          filePath: relative,
          suggestion:
              'Configure signingConfigs.release and assign it to the release buildType.',
        ),
      );
    }

    final hasVersionCode = RegExp(r'versionCode\s+').hasMatch(content) ||
        content.contains('flutter.versionCode') ||
        content.contains('versionCode =');
    checks['android_version_code'] = hasVersionCode;
    if (!hasVersionCode) {
      issues.add(
        AnalysisIssue(
          ruleId: 'release.android_version_code',
          message: 'versionCode not clearly configured.',
          severity: Severity.warning,
          filePath: relative,
          suggestion: 'Ensure versionCode is set for Play Store uploads.',
        ),
      );
    }

    final minify = content.contains('minifyEnabled true') ||
        content.contains('isMinifyEnabled = true') ||
        content.contains('minifyEnabled = true');
    checks['android_minify'] = minify;
    if (!minify) {
      issues.add(
        AnalysisIssue(
          ruleId: 'release.android_r8',
          message: 'R8/ProGuard minify does not appear enabled for release.',
          severity: Severity.info,
          filePath: relative,
          suggestion: 'Enable minifyEnabled and ship a ProGuard keep rules file.',
        ),
      );
    }

    // Permissions sanity via manifest
    final manifest = File(
      p.join(
        context.androidPath,
        'app',
        'src',
        'main',
        'AndroidManifest.xml',
      ),
    );
    if (await manifest.exists()) {
      final m = await manifest.readAsString();
      checks['android_manifest'] = true;
      if (!m.contains('android.permission') && m.contains('<uses-permission')) {
        // still fine
      }
      // Flag debug applicationId suffix leftover isn't critical
      if (m.contains('android:debuggable="true"')) {
        issues.add(
          AnalysisIssue(
            ruleId: 'release.android_debuggable',
            message: 'debuggable=true must not ship in production.',
            severity: Severity.critical,
            filePath: p.relative(manifest.path, from: context.rootPath),
          ),
        );
        checks['android_signing'] = checks['android_signing'] ?? false;
      }
    }

    return (issues: issues, checks: checks);
  }

  Future<({List<AnalysisIssue> issues, Map<String, bool> checks})> _checkIos(
    ProjectContext context,
  ) async {
    final issues = <AnalysisIssue>[];
    final checks = <String, bool>{};

    final infoPlist = File(p.join(context.iosPath, 'Runner', 'Info.plist'));
    if (!await infoPlist.exists()) {
      checks['ios_info_plist'] = false;
      issues.add(
        const AnalysisIssue(
          ruleId: 'release.ios_info_plist',
          message: 'ios/Runner/Info.plist not found.',
          severity: Severity.warning,
        ),
      );
      return (issues: issues, checks: checks);
    }

    final content = await infoPlist.readAsString();
    final relative = p.relative(infoPlist.path, from: context.rootPath);
    checks['ios_info_plist'] = true;

    // Bundle identifier often lives in project.pbxproj
    final pbx = File(
      p.join(context.iosPath, 'Runner.xcodeproj', 'project.pbxproj'),
    );
    var hasBundleId = false;
    if (await pbx.exists()) {
      final pbxContent = await pbx.readAsString();
      hasBundleId = pbxContent.contains('PRODUCT_BUNDLE_IDENTIFIER');
      final relativePbx = p.relative(pbx.path, from: context.rootPath);
      if (!hasBundleId) {
        issues.add(
          AnalysisIssue(
            ruleId: 'release.ios_bundle_id',
            message: 'PRODUCT_BUNDLE_IDENTIFIER not found.',
            severity: Severity.error,
            filePath: relativePbx,
          ),
        );
      }

      final deployMatch = RegExp(
        r'IPHONEOS_DEPLOYMENT_TARGET\s*=\s*([0-9.]+)',
      ).firstMatch(pbxContent);
      checks['ios_deployment_target'] = deployMatch != null;
      if (deployMatch == null) {
        issues.add(
          AnalysisIssue(
            ruleId: 'release.ios_deployment_target',
            message: 'iOS deployment target not found.',
            severity: Severity.warning,
            filePath: relativePbx,
          ),
        );
      }
    }
    checks['ios_bundle_id'] = hasBundleId;

    // Privacy keys commonly required when plugins are used
    final pubspecDeps = {
      ...?context.dependencies?.keys,
      ...?context.devDependencies?.keys,
    };
    final requiredPrivacy = <String, String>{};
    if (pubspecDeps.any((d) => d.contains('camera') || d.contains('image_picker'))) {
      requiredPrivacy['NSCameraUsageDescription'] = 'Camera';
      requiredPrivacy['NSPhotoLibraryUsageDescription'] = 'Photo library';
    }
    if (pubspecDeps.any((d) => d.contains('geolocator') || d.contains('location'))) {
      requiredPrivacy['NSLocationWhenInUseUsageDescription'] = 'Location';
    }
    if (pubspecDeps.any((d) => d.contains('microphone') || d.contains('record'))) {
      requiredPrivacy['NSMicrophoneUsageDescription'] = 'Microphone';
    }

    for (final entry in requiredPrivacy.entries) {
      if (!content.contains(entry.key)) {
        issues.add(
          AnalysisIssue(
            ruleId: 'release.ios_privacy_key',
            message: 'Missing ${entry.value} privacy description (${entry.key}).',
            severity: Severity.error,
            filePath: relative,
            suggestion: 'Add ${entry.key} to Info.plist with a clear purpose string.',
          ),
        );
      }
    }
    checks['ios_privacy_keys'] = requiredPrivacy.keys.every(content.contains);

    return (issues: issues, checks: checks);
  }

  Future<({List<AnalysisIssue> issues, Map<String, bool> checks})>
      _checkFlutter(ProjectContext context) async {
    final issues = <AnalysisIssue>[];
    final checks = <String, bool>{};

    var todoCount = 0;
    var printCount = 0;
    var kDebugModeAssert = false;

    for (final file in context.dartFiles) {
      final relative = p.relative(file.path, from: context.rootPath);
      final content = await _scanner.readFile(file);
      if (content == null) continue;

      final todos = RegExp(r'//\s*(TODO|FIXME)\b').allMatches(content);
      todoCount += todos.length;

      final prints = RegExp(r'\bprint\s*\(').allMatches(content);
      printCount += prints.length;
      if (prints.isNotEmpty) {
        issues.add(
          AnalysisIssue(
            ruleId: 'release.debug_print',
            message: '${prints.length} print() call(s) found.',
            severity: Severity.info,
            filePath: relative,
            suggestion: 'Replace with a logger gated behind kDebugMode, or remove.',
          ),
        );
      }

      if (content.contains('kDebugMode') || content.contains('assert(')) {
        kDebugModeAssert = true;
      }

      // Hardcoded debug flags
      if (RegExp(r'''debugShowCheckedModeBanner\s*:\s*true''').hasMatch(content)) {
        issues.add(
          AnalysisIssue(
            ruleId: 'release.debug_banner',
            message: 'debugShowCheckedModeBanner is true.',
            severity: Severity.warning,
            filePath: relative,
            suggestion: 'Set debugShowCheckedModeBanner: false for production.',
          ),
        );
      }
    }

    checks['flutter_no_excess_todos'] = todoCount < 20;
    if (todoCount >= 20) {
      issues.add(
        AnalysisIssue(
          ruleId: 'release.todo_count',
          message: '$todoCount TODO/FIXME comments remain.',
          severity: Severity.warning,
          suggestion: 'Resolve or ticket outstanding TODOs before release.',
        ),
      );
    }

    checks['flutter_print_audit'] = printCount == 0;
    checks['flutter_debug_guards'] = kDebugModeAssert;

    // Version from pubspec
    final version = context.pubspec['version'];
    final hasVersion = version is String && version.isNotEmpty;
    checks['flutter_version'] = hasVersion;
    if (!hasVersion) {
      issues.add(
        const AnalysisIssue(
          ruleId: 'release.pubspec_version',
          message: 'pubspec.yaml is missing a version field.',
          severity: Severity.error,
          filePath: 'pubspec.yaml',
        ),
      );
    }

    return (issues: issues, checks: checks);
  }

  Future<File?> _findAndroidBuildGradle(ProjectContext context) async {
    final candidates = [
      p.join(context.androidPath, 'app', 'build.gradle'),
      p.join(context.androidPath, 'app', 'build.gradle.kts'),
    ];
    for (final path in candidates) {
      final file = File(path);
      if (await file.exists()) return file;
    }
    return null;
  }
}
