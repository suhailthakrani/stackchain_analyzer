import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Detected architecture style for a Flutter project.
enum ArchitectureStyle {
  cleanArchitecture,
  featureFirst,
  mvvm,
  mvc,
  unknown,
}

/// Snapshot of a Flutter project used by analyzers.
class ProjectContext {
  ProjectContext({
    required this.rootPath,
    required this.pubspec,
    required this.dartFiles,
    required this.hasAndroid,
    required this.hasIos,
    required this.hasWeb,
    required this.hasAnalysisOptions,
    required this.assetPaths,
    required this.architectureStyle,
    this.packageName,
  });

  final String rootPath;
  final YamlMap pubspec;
  final List<File> dartFiles;
  final bool hasAndroid;
  final bool hasIos;
  final bool hasWeb;
  final bool hasAnalysisOptions;
  final List<String> assetPaths;
  final ArchitectureStyle architectureStyle;
  final String? packageName;

  String get projectName {
    final name = pubspec['name'];
    if (name is String && name.isNotEmpty) return name;
    return p.basename(rootPath);
  }

  String get libPath => p.join(rootPath, 'lib');
  String get androidPath => p.join(rootPath, 'android');
  String get iosPath => p.join(rootPath, 'ios');
  String get pubspecPath => p.join(rootPath, 'pubspec.yaml');

  Map<String, dynamic>? get dependencies {
    final deps = pubspec['dependencies'];
    if (deps is! YamlMap) return null;
    return Map<String, dynamic>.from(deps);
  }

  Map<String, dynamic>? get devDependencies {
    final deps = pubspec['dev_dependencies'];
    if (deps is! YamlMap) return null;
    return Map<String, dynamic>.from(deps);
  }

  bool get isFlutterProject {
    final deps = dependencies;
    if (deps == null) return false;
    return deps.containsKey('flutter');
  }

  Directory get libDirectory => Directory(libPath);
}
