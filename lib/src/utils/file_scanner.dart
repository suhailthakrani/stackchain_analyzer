import 'dart:io';

import 'package:path/path.dart' as p;

/// File system helpers for scanning Flutter projects.
class FileScanner {
  const FileScanner();

  /// Recursively find Dart files under [directory], skipping generated noise.
  Future<List<File>> findDartFiles(String directory) async {
    final root = Directory(directory);
    if (!await root.exists()) return const [];

    final files = <File>[];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      if (!entity.path.endsWith('.dart')) continue;
      final relative = p.relative(entity.path, from: directory);
      if (_shouldSkip(relative)) continue;
      files.add(entity);
    }

    files.sort((a, b) => a.path.compareTo(b.path));
    return files;
  }

  /// Find asset files declared under common asset folders.
  Future<List<File>> findAssetFiles(String rootPath) async {
    final candidates = [
      p.join(rootPath, 'assets'),
      p.join(rootPath, 'asset'),
      p.join(rootPath, 'images'),
    ];

    final files = <File>[];
    for (final dirPath in candidates) {
      final dir = Directory(dirPath);
      if (!await dir.exists()) continue;
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) files.add(entity);
      }
    }
    return files;
  }

  bool _shouldSkip(String relativePath) {
    final segments = p.split(relativePath);
    const skipDirs = {
      '.dart_tool',
      'build',
      '.git',
      'generated',
      '.generated',
    };
    if (segments.any(skipDirs.contains)) return true;
    if (relativePath.endsWith('.g.dart')) return true;
    if (relativePath.endsWith('.freezed.dart')) return true;
    if (relativePath.endsWith('.gr.dart')) return true;
    if (relativePath.endsWith('.mocks.dart')) return true;
    return false;
  }

  /// Read file contents safely; returns null on failure.
  Future<String?> readFile(File file) async {
    try {
      return await file.readAsString();
    } on Exception {
      return null;
    }
  }

  /// Count non-empty lines in [content].
  int countLines(String content) {
    if (content.isEmpty) return 0;
    return content.split('\n').length;
  }
}
