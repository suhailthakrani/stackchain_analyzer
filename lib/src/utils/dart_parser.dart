import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:path/path.dart' as p;

/// Lightweight Dart AST helpers built on `package:analyzer`.
class DartParser {
  const DartParser();

  /// Parse [source] into a [CompilationUnit], or null on syntax errors.
  CompilationUnit? parse(String source, {String? path}) {
    try {
      final result = parseString(
        content: source,
        path: path,
        throwIfDiagnostics: false,
      );
      if (result.errors.any((e) => e.severity.name == 'ERROR')) {
        // Still return the unit — partial AST is useful for heuristics.
      }
      return result.unit;
    } on Exception {
      return null;
    }
  }

  Future<CompilationUnit?> parseFile(File file) async {
    try {
      final content = await file.readAsString();
      return parse(content, path: file.path);
    } on Exception {
      return null;
    }
  }

  /// Collect import URIs from a compilation unit.
  List<String> collectImports(CompilationUnit unit) {
    return unit.directives
        .whereType<ImportDirective>()
        .map((d) => d.uri.stringValue ?? '')
        .where((uri) => uri.isNotEmpty)
        .toList();
  }

  /// Relative path from project lib/ for display.
  String relativeLibPath(String filePath, String rootPath) {
    final libRoot = p.join(rootPath, 'lib');
    if (p.isWithin(libRoot, filePath)) {
      return p.relative(filePath, from: rootPath);
    }
    return p.relative(filePath, from: rootPath);
  }
}

/// Visitor that finds method declarations by name pattern.
class MethodFinder extends RecursiveAstVisitor<void> {
  MethodFinder({this.namePredicate});

  final bool Function(String name)? namePredicate;
  final List<MethodDeclaration> methods = [];

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    final name = node.name.lexeme;
    if (namePredicate == null || namePredicate!(name)) {
      methods.add(node);
    }
    super.visitMethodDeclaration(node);
  }
}

/// Visitor that counts setState invocations.
class SetStateCounter extends RecursiveAstVisitor<void> {
  int count = 0;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == 'setState') {
      count++;
    }
    super.visitMethodInvocation(node);
  }
}

/// Visitor that finds class declarations extending Widget / StatelessWidget / etc.
class WidgetClassFinder extends RecursiveAstVisitor<void> {
  final List<ClassDeclaration> widgets = [];

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final extendsClause = node.extendsClause;
    if (extendsClause != null) {
      final name = extendsClause.superclass.name2.lexeme;
      const widgetBases = {
        'StatelessWidget',
        'StatefulWidget',
        'ConsumerWidget',
        'ConsumerStatefulWidget',
        'HookWidget',
        'HookConsumerWidget',
        'Cubit',
        'Bloc',
      };
      // We track widget-like and also leave Cubit/Bloc for other analyzers.
      if (widgetBases.contains(name) || name.endsWith('Widget')) {
        widgets.add(node);
      }
    }
    super.visitClassDeclaration(node);
  }
}
