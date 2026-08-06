import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../models/project_context.dart';
import 'file_scanner.dart';

/// Detects and loads Flutter project metadata.
class ProjectDetector {
  ProjectDetector({FileScanner? scanner})
      : _scanner = scanner ?? const FileScanner();

  final FileScanner _scanner;

  /// Returns true when [rootPath] looks like a Flutter project.
  Future<bool> isFlutterProject(String rootPath) async {
    final pubspecFile = File(p.join(rootPath, 'pubspec.yaml'));
    if (!await pubspecFile.exists()) return false;

    try {
      final content = await pubspecFile.readAsString();
      final yaml = loadYaml(content);
      if (yaml is! YamlMap) return false;

      final deps = yaml['dependencies'];
      if (deps is YamlMap && deps.containsKey('flutter')) return true;

      final flutterSection = yaml['flutter'];
      return flutterSection != null;
    } on Exception {
      return false;
    }
  }

  /// Load a full [ProjectContext] for analysis.
  ///
  /// Throws [StateError] if the path is not a Flutter project.
  Future<ProjectContext> load(String rootPath) async {
    final absolute = p.normalize(p.absolute(rootPath));
    final isFlutter = await isFlutterProject(absolute);
    if (!isFlutter) {
      throw StateError('This is not a Flutter project');
    }

    final pubspecFile = File(p.join(absolute, 'pubspec.yaml'));
    final pubspecContent = await pubspecFile.readAsString();
    final pubspec = loadYaml(pubspecContent) as YamlMap;

    final packageName =
        pubspec['name'] is String ? pubspec['name'] as String : null;

    final dartFiles = await _scanner.findDartFiles(p.join(absolute, 'lib'));
    final assetFiles = await _scanner.findAssetFiles(absolute);
    final assetPaths = assetFiles.map((f) => f.path).toList();

    final hasAndroid = await Directory(p.join(absolute, 'android')).exists();
    final hasIos = await Directory(p.join(absolute, 'ios')).exists();
    final hasWeb = await Directory(p.join(absolute, 'web')).exists();
    final hasAnalysisOptions =
        await File(p.join(absolute, 'analysis_options.yaml')).exists();

    final style = await _detectArchitecture(absolute);

    return ProjectContext(
      rootPath: absolute,
      pubspec: pubspec,
      dartFiles: dartFiles,
      hasAndroid: hasAndroid,
      hasIos: hasIos,
      hasWeb: hasWeb,
      hasAnalysisOptions: hasAnalysisOptions,
      assetPaths: assetPaths,
      architectureStyle: style,
      packageName: packageName,
    );
  }

  Future<ArchitectureStyle> _detectArchitecture(String rootPath) async {
    final libPath = p.join(rootPath, 'lib');
    final libDir = Directory(libPath);
    if (!await libDir.exists()) return ArchitectureStyle.unknown;

    final entries = await libDir.list().toList();
    final dirNames = entries
        .whereType<Directory>()
        .map((d) => p.basename(d.path).toLowerCase())
        .toSet();

    final hasFeatures =
        dirNames.contains('features') || dirNames.contains('feature');
    final hasDomain = dirNames.contains('domain');
    final hasData = dirNames.contains('data');
    final hasPresentation =
        dirNames.contains('presentation') || dirNames.contains('ui');
    final hasViewModels = await _hasPathContaining(libPath, 'viewmodel') ||
        await _hasPathContaining(libPath, 'view_model');
    final hasControllers = await _hasPathContaining(libPath, 'controller');
    final hasModels = dirNames.contains('models') || dirNames.contains('model');
    final hasViews = dirNames.contains('views') || dirNames.contains('view');

    if (hasDomain && hasData && (hasPresentation || hasFeatures)) {
      return ArchitectureStyle.cleanArchitecture;
    }
    if (hasFeatures) {
      return ArchitectureStyle.featureFirst;
    }
    if (hasViewModels) {
      return ArchitectureStyle.mvvm;
    }
    if (hasControllers && (hasModels || hasViews)) {
      return ArchitectureStyle.mvc;
    }

    return ArchitectureStyle.unknown;
  }

  Future<bool> _hasPathContaining(String root, String segment) async {
    final dir = Directory(root);
    if (!await dir.exists()) return false;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      final name = p.basename(entity.path).toLowerCase();
      final parent = p.basename(p.dirname(entity.path)).toLowerCase();
      if (name.contains(segment) || parent.contains(segment)) {
        return true;
      }
    }
    return false;
  }
}
