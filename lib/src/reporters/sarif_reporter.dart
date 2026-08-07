import 'dart:convert';
import 'dart:io';

import '../models/health_report.dart';
import '../models/severity.dart';
import 'reporter.dart';

/// SARIF 2.1.0 reporter for GitHub Code Scanning / VS Code.
class SarifReporter implements Reporter {
  SarifReporter({StringSink? sink}) : _sink = sink ?? stdout;

  final StringSink _sink;

  @override
  void write(HealthReport report) {
    final rules = <String, Map<String, dynamic>>{};
    final results = <Map<String, dynamic>>[];

    for (final issue in report.allIssues) {
      rules.putIfAbsent(issue.ruleId, () {
        return {
          'id': issue.ruleId,
          'name': issue.ruleId,
          'shortDescription': {'text': issue.ruleId},
          'fullDescription': {'text': issue.message},
          'defaultConfiguration': {
            'level': _level(issue.severity),
          },
          'helpUri':
              'https://github.com/suhailthakrani/stackchain_analyzer#readme',
        };
      });

      final result = <String, dynamic>{
        'ruleId': issue.ruleId,
        'level': _level(issue.severity),
        'message': {
          'text': [
            issue.message,
            if (issue.suggestion != null) 'Suggestion: ${issue.suggestion}',
          ].join(' '),
        },
      };

      if (issue.filePath != null) {
        result['locations'] = [
          {
            'physicalLocation': {
              'artifactLocation': {'uri': issue.filePath},
              'region': {
                'startLine': issue.line ?? 1,
                if (issue.column != null) 'startColumn': issue.column,
              },
            },
          },
        ];
      }

      results.add(result);
    }

    final sarif = {
      r'$schema':
          'https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json',
      'version': '2.1.0',
      'runs': [
        {
          'tool': {
            'driver': {
              'name': 'stackchain_analyzer',
              'informationUri':
                  'https://pub.dev/packages/stackchain_analyzer',
              'version': '0.2.0',
              'rules': rules.values.toList(),
            },
          },
          'results': results,
          'properties': {
            'healthScore': report.overallScore,
            'project': report.projectName,
          },
        },
      ],
    };

    _sink.writeln(const JsonEncoder.withIndent('  ').convert(sarif));
  }

  String _level(Severity severity) => switch (severity) {
        Severity.critical || Severity.error => 'error',
        Severity.warning => 'warning',
        Severity.info => 'note',
      };
}
