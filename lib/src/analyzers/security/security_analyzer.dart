import 'dart:io';

import 'package:path/path.dart' as p;

import '../../models/analysis_issue.dart';
import '../../models/analysis_result.dart';
import '../../models/project_context.dart';
import '../../models/severity.dart';
import '../../utils/file_scanner.dart';
import '../analyzer.dart';

/// Mobile-focused security analyzer.
class SecurityAnalyzer implements Analyzer {
  SecurityAnalyzer({FileScanner? scanner})
      : _scanner = scanner ?? const FileScanner();

  final FileScanner _scanner;

  static final _secretPatterns = <RegExp, String>{
    RegExp(r'api[_-]?key\s*[:=]\s*(\S{16,})', caseSensitive: false):
        'Possible API key',
    RegExp(
      r'(secret|access[_-]?token|auth[_-]?token)\s*[:=]\s*(\S{16,})',
      caseSensitive: false,
    ): 'Possible token/secret',
    RegExp(
      r'(password|passwd|pwd)\s*[:=]\s*(\S{4,})',
      caseSensitive: false,
    ): 'Possible hardcoded password',
    RegExp(r'AIza[0-9A-Za-z\-_]{35}'): 'Possible Google/Firebase API key',
    RegExp(
      r'firebase[_-]?(api)?[_-]?key\s*[:=]\s*(\S+)',
      caseSensitive: false,
    ): 'Possible Firebase key',
    RegExp(r'-----BEGIN (RSA |EC )?PRIVATE KEY-----'): 'Private key material',
  };

  @override
  String get id => 'security';

  @override
  String get name => 'Security';

  @override
  String get description =>
      'Detect secrets, insecure configs, and mobile security risks';

  @override
  Future<AnalysisResult> analyze(ProjectContext context) async {
    final issues = <AnalysisIssue>[];

    issues.addAll(await _scanDartSecrets(context));
    issues.addAll(await _scanHttpUsage(context));
    issues.addAll(await _scanInsecureStorage(context));
    issues.addAll(await _scanSensitivePrints(context));

    if (context.hasAndroid) {
      issues.addAll(await _scanAndroid(context));
    }
    if (context.hasIos) {
      issues.addAll(await _scanIos(context));
    }

    final score = AnalysisResult.computeScore(issues);
    return AnalysisResult(
      analyzerName: name,
      score: score,
      issues: issues,
      summary: '${issues.length} security finding(s).',
    );
  }

  Future<List<AnalysisIssue>> _scanDartSecrets(ProjectContext context) async {
    final issues = <AnalysisIssue>[];
    for (final file in context.dartFiles) {
      final relative = p.relative(file.path, from: context.rootPath);
      final content = await _scanner.readFile(file);
      if (content == null) continue;

      for (final entry in _secretPatterns.entries) {
        for (final match in entry.key.allMatches(content)) {
          final line =
              content.substring(0, match.start).split('\n').length;
          issues.add(
            AnalysisIssue(
              ruleId: 'sec.secret',
              message: '${entry.value} found.',
              severity: Severity.critical,
              filePath: relative,
              line: line,
              suggestion:
                  'Move secrets to environment variables, --dart-define, or a secrets manager. Never commit credentials.',
              context: _redact(match.group(0) ?? ''),
            ),
          );
        }
      }
    }
    return issues;
  }

  Future<List<AnalysisIssue>> _scanHttpUsage(ProjectContext context) async {
    final issues = <AnalysisIssue>[];
    final httpUrl = RegExp(r'''['"]http://[^'"]+['"]''');

    for (final file in context.dartFiles) {
      final relative = p.relative(file.path, from: context.rootPath);
      final content = await _scanner.readFile(file);
      if (content == null) continue;

      for (final match in httpUrl.allMatches(content)) {
        final url = match.group(0) ?? '';
        if (url.contains('localhost') || url.contains('127.0.0.1')) continue;
        final line = content.substring(0, match.start).split('\n').length;
        issues.add(
          AnalysisIssue(
            ruleId: 'sec.insecure_http',
            message: 'Insecure HTTP URL detected.',
            severity: Severity.error,
            filePath: relative,
            line: line,
            suggestion: 'Use HTTPS for all network traffic.',
            context: url,
          ),
        );
      }
    }
    return issues;
  }

  Future<List<AnalysisIssue>> _scanInsecureStorage(
    ProjectContext context,
  ) async {
    final issues = <AnalysisIssue>[];
    for (final file in context.dartFiles) {
      final relative = p.relative(file.path, from: context.rootPath);
      final content = await _scanner.readFile(file);
      if (content == null) continue;

      if (content.contains('SharedPreferences') &&
          RegExp(
            r'''(token|password|secret|apiKey|api_key)''',
            caseSensitive: false,
          ).hasMatch(content)) {
        issues.add(
          AnalysisIssue(
            ruleId: 'sec.insecure_storage',
            message:
                'Sensitive data may be stored in SharedPreferences (unencrypted).',
            severity: Severity.warning,
            filePath: relative,
            suggestion:
                'Use flutter_secure_storage or platform Keychain/Keystore for secrets.',
          ),
        );
      }
    }
    return issues;
  }

  Future<List<AnalysisIssue>> _scanSensitivePrints(
    ProjectContext context,
  ) async {
    final issues = <AnalysisIssue>[];
    final printRe = RegExp(
      r'''print\s*\(\s*['"][^'"]*(token|password|secret|api[_-]?key|bearer)[^'"]*['"]''',
      caseSensitive: false,
    );

    for (final file in context.dartFiles) {
      final relative = p.relative(file.path, from: context.rootPath);
      final content = await _scanner.readFile(file);
      if (content == null) continue;

      for (final match in printRe.allMatches(content)) {
        final line = content.substring(0, match.start).split('\n').length;
        issues.add(
          AnalysisIssue(
            ruleId: 'sec.sensitive_print',
            message: 'print() may leak sensitive data.',
            severity: Severity.warning,
            filePath: relative,
            line: line,
            suggestion: 'Remove debug prints or redact sensitive values.',
          ),
        );
      }
    }
    return issues;
  }

  Future<List<AnalysisIssue>> _scanAndroid(ProjectContext context) async {
    final issues = <AnalysisIssue>[];
    final manifestPath = p.join(
      context.androidPath,
      'app',
      'src',
      'main',
      'AndroidManifest.xml',
    );
    final manifest = File(manifestPath);
    if (!await manifest.exists()) return issues;

    final content = await manifest.readAsString();
    final relative = p.relative(manifestPath, from: context.rootPath);

    if (RegExp(
      r'''android:debuggable\s*=\s*["']true["']''',
    ).hasMatch(content)) {
      issues.add(
        AnalysisIssue(
          ruleId: 'sec.android_debuggable',
          message: 'android:debuggable is true.',
          severity: Severity.critical,
          filePath: relative,
          suggestion: 'Ensure debuggable is false for release builds.',
        ),
      );
    }

    if (RegExp(
      r'''android:allowBackup\s*=\s*["']true["']''',
    ).hasMatch(content)) {
      issues.add(
        AnalysisIssue(
          ruleId: 'sec.android_backup',
          message: 'android:allowBackup is enabled.',
          severity: Severity.warning,
          filePath: relative,
          suggestion:
              'Disable allowBackup or use backup rules to exclude sensitive data.',
        ),
      );
    }

    if (RegExp(
      r'''android:exported\s*=\s*["']true["']''',
    ).hasMatch(content)) {
      // Informational — exported components need review.
      final count =
          RegExp(r'''android:exported\s*=\s*["']true["']''').allMatches(content).length;
      if (count > 1) {
        issues.add(
          AnalysisIssue(
            ruleId: 'sec.android_exported',
            message: '$count components are exported=true — review exposure.',
            severity: Severity.info,
            filePath: relative,
            suggestion:
                'Only export components that must be reachable from other apps.',
          ),
        );
      }
    }

    const riskyPerms = [
      'WRITE_EXTERNAL_STORAGE',
      'READ_SMS',
      'RECEIVE_SMS',
      'READ_CALL_LOG',
      'PROCESS_OUTGOING_CALLS',
      'REQUEST_INSTALL_PACKAGES',
    ];
    for (final perm in riskyPerms) {
      if (content.contains(perm)) {
        issues.add(
          AnalysisIssue(
            ruleId: 'sec.android_permission',
            message: 'Sensitive permission declared: $perm.',
            severity: Severity.warning,
            filePath: relative,
            suggestion: 'Justify and minimize dangerous permissions.',
          ),
        );
      }
    }

    return issues;
  }

  Future<List<AnalysisIssue>> _scanIos(ProjectContext context) async {
    final issues = <AnalysisIssue>[];
    final infoPlistPath = p.join(context.iosPath, 'Runner', 'Info.plist');
    final infoPlist = File(infoPlistPath);
    if (!await infoPlist.exists()) return issues;

    final content = await infoPlist.readAsString();
    final relative = p.relative(infoPlistPath, from: context.rootPath);

    // ATS disabled
    if (content.contains('NSAllowsArbitraryLoads') &&
        RegExp(
          r'''NSAllowsArbitraryLoads[\s\S]{0,80}<true\s*/>''',
        ).hasMatch(content)) {
      issues.add(
        AnalysisIssue(
          ruleId: 'sec.ios_ats',
          message: 'App Transport Security allows arbitrary loads.',
          severity: Severity.error,
          filePath: relative,
          suggestion: 'Disable NSAllowsArbitraryLoads and use HTTPS endpoints.',
        ),
      );
    }

    // Common privacy keys used without description check is in release analyzer;
    // here flag empty string descriptions.
    final privacyKeys = [
      'NSCameraUsageDescription',
      'NSPhotoLibraryUsageDescription',
      'NSMicrophoneUsageDescription',
      'NSLocationWhenInUseUsageDescription',
    ];
    for (final key in privacyKeys) {
      final empty = RegExp(
        '$key</key>\\s*<string>\\s*</string>',
      );
      if (empty.hasMatch(content)) {
        issues.add(
          AnalysisIssue(
            ruleId: 'sec.ios_privacy_empty',
            message: 'Empty privacy usage description for $key.',
            severity: Severity.warning,
            filePath: relative,
            suggestion: 'Provide a clear user-facing purpose string.',
          ),
        );
      }
    }

    return issues;
  }

  String _redact(String value) {
    if (value.length <= 8) return '***';
    return '${value.substring(0, 4)}…${value.substring(value.length - 2)}';
  }
}
