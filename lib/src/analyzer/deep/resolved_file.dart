import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import '../ast/widget_visitor.dart';

/// A Dart file that has been fully resolved by `AnalysisContextCollection`.
///
/// Unlike [ParsedFile] (which is purely syntactic), a [ResolvedFile] carries
/// type information for every declaration: class hierarchies, method return
/// types, and field types are all available. This lets cross-file detectors
/// follow references from a widget's usage site to its definition.
///
class ResolvedFile extends ParsedFile {
  /// Resolved class elements keyed by class name.
  ///
  /// Each [ClassElement] knows its superclass, interfaces, and members.
  /// Detectors use this to trace custom widget hierarchies:
  /// `CircleIconBtn → AppBtn → StatelessWidget`.
  final Map<String, ClassElement> classElements;

  /// Resolved compilation unit — the full AST with type annotations.
  ///
  /// Detectors that need to inspect resolved expressions (e.g. resolve
  /// the type of a variable argument) use this directly.
  final CompilationUnit resolvedUnit;

  ResolvedFile({
    required super.path,
    required super.widgets,
    required super.hasErrors,
    required this.classElements,
    required this.resolvedUnit,
  });

  ClassElement? classFor(String widgetName) => classElements[widgetName];

  bool definesWidget(String widgetName) =>
      classElements.containsKey(widgetName);
}

class ProjectIndex {
  final Map<String, ResolvedFile> filesByPath;

  final Map<String, ResolvedFile> fileByClassName;

  final Map<String, ClassElement> classElements;

  final Map<String, List<WidgetUsage>> usagesByType;

  ProjectIndex({
    required this.filesByPath,
    required this.fileByClassName,
    required this.classElements,
    required this.usagesByType,
  });

  List<WidgetUsage> usagesOf(String widgetType) =>
      usagesByType[widgetType] ?? const [];

  ClassElement? elementFor(String className) => classElements[className];

  List<String> subclassesOf(String baseClassName) {
    final result = <String>[];
    for (final entry in classElements.entries) {
      final supertype = entry.value.supertype?.element.name;
      if (supertype == baseClassName) {
        result.add(entry.key);
      }
    }
    return result;
  }
}
