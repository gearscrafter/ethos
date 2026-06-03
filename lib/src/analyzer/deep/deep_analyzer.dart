import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/file_system/physical_file_system.dart';

import '../../models/spec.dart';
import '../../models/coverage_report.dart';
import '../ast/widget_visitor.dart';
import '../coverage_analyzer.dart';
import '../detector_registry.dart';
import '../spec_loader.dart';
import 'analysis_progress.dart';
import 'resolved_file.dart';
import 'detectors/cross_file_semantic_labels_detector.dart';
import 'detectors/resolved_contrast_detector.dart';

class DeepAnalyzer {
  final Spec spec;
  final String projectPath;
  final DetectorRegistry registry;

  DeepAnalyzer({
    required this.spec,
    required this.projectPath,
    required this.registry,
  });

  static Future<DeepAnalyzer> forProject(
    String projectPath, {
    String? configPath,
    DetectorRegistry? registry,
  }) async {
    final spec = await SpecLoader.load(
      projectPath: projectPath,
      configPath: configPath,
    );
    return DeepAnalyzer(
      spec: spec,
      projectPath: projectPath,
      registry: registry ?? DetectorRegistry.withBuiltIns(),
    );
  }

  Stream<AnalysisProgress> analyze() async* {
    yield const AnalysisPreparing();

    final dartFiles = await _findDartFiles();
    if (dartFiles.isEmpty) {
      yield AnalysisWarning(message: 'No Dart files found in $projectPath.');
      yield* _fallback();
      return;
    }

    yield AnalysisLoadingContext(totalFiles: dartFiles.length);

    late final AnalysisContextCollection collection;
    try {
      collection = AnalysisContextCollection(
        includedPaths: [Directory(projectPath).absolute.path],
        resourceProvider: PhysicalResourceProvider.INSTANCE,
      );
    } catch (e) {
      yield AnalysisWarning(
        message: 'Could not build analysis context: $e\n'
            'Make sure `flutter pub get` (or `dart pub get`) has been run '
            'in $projectPath.\n'
            'Falling back to standard analysis mode.',
      );
      yield* _fallback();
      return;
    }

    final resolvedFiles = <ResolvedFile>[];
    final issues = <String>[];
    int current = 0;

    for (final file in dartFiles) {
      current++;
      yield AnalysisAnalyzingFile(
        path: file.path,
        current: current,
        total: dartFiles.length,
      );

      try {
        final absPath = file.absolute.path;
        final context = collection.contextFor(absPath);
        final result = await context.currentSession.getResolvedUnit(absPath);

        if (result is ResolvedUnitResult) {
          final classElements = _extractClasses(result.unit);
          final widgets = _visitWidgets(result);

          resolvedFiles.add(ResolvedFile(
            path: file.path,
            widgets: widgets,
            hasErrors: _hasResultErrors(result),
            classElements: classElements,
            resolvedUnit: result.unit,
          ));
        }
      } catch (e) {
        issues.add('Failed to resolve ${file.path}: $e');
        try {
          final source = await file.readAsString();
          final basic = parseDartFile(file.path, source);
          resolvedFiles.add(ResolvedFile(
            path: basic.path,
            widgets: basic.widgets,
            hasErrors: true,
            classElements: const {},
            resolvedUnit: _placeholderUnit,
          ));
        } catch (_) {}
      }
    }

    final index = _buildIndex(resolvedFiles);

    final report = CoverageReport(
      specVersion: spec.version,
      projectPath: projectPath,
      timestamp: DateTime.now(),
      coverage: {},
      issues: issues,
    );

    final deepDetectors = {
      'wcag_1_3_1_semantics_label':
          CrossFileSemanticLabelsDetector(index: index),
      'wcag_1_4_3_contrast_minimum': ResolvedContrastDetector(index: index),
    };

    for (final rule in spec.rules.values) {
      yield AnalysisRunningDetector(
        ruleId: rule.ruleId,
        ruleTitle: rule.title,
      );

      final deepDetector = deepDetectors[rule.ruleId];
      if (deepDetector != null) {
        final result = deepDetector.analyzeDeep(
          rule: rule,
          files: resolvedFiles,
          index: index,
          aliases: spec.widgetAliases,
          colorAliases: spec.colorAliases,
        );
        report.coverage[rule.ruleId] = RuleCoverage.calculate(
          ruleId: rule.ruleId,
          title: rule.title,
          matched: result.matched,
          total: result.total,
          indeterminate: result.indeterminate,
          criticalThreshold: rule.coverageMetric.criticalThreshold,
          findings: result.findings,
        );
        continue;
      }

      final detector = registry.find(rule.ruleId);
      if (detector == null) {
        report.issues.add('No detector for rule "${rule.ruleId}" — skipping.');
        report.coverage[rule.ruleId] = RuleCoverage.calculate(
          ruleId: rule.ruleId,
          title: rule.title,
          matched: 0,
          total: 0,
          criticalThreshold: rule.coverageMetric.criticalThreshold,
        );
        continue;
      }

      final result = detector.analyze(
        rule: rule,
        files: resolvedFiles,
        aliases: spec.widgetAliases,
        colorAliases: spec.colorAliases,
      );
      report.coverage[rule.ruleId] = RuleCoverage.calculate(
        ruleId: rule.ruleId,
        title: rule.title,
        matched: result.matched,
        total: result.total,
        indeterminate: result.indeterminate,
        criticalThreshold: rule.coverageMetric.criticalThreshold,
        findings: result.findings,
      );
    }

    report.calculateOverall();
    report.determineComplianceLevel();
    yield AnalysisComplete(report: report, usedDeepMode: true);
  }

  Stream<AnalysisProgress> _fallback() async* {
    final analyzer = CoverageAnalyzer(
      spec: spec,
      projectPath: projectPath,
      registry: registry,
    );
    final report = await analyzer.analyze();
    yield AnalysisComplete(report: report, usedDeepMode: false);
  }

  Future<List<File>> _findDartFiles() async {
    final dir = Directory(projectPath);
    final files = <File>[];
    if (!await dir.exists()) {
      return files;
    }
    final sep = Platform.pathSeparator;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      final path = entity.path;
      if (!path.endsWith('.dart')) {
        continue;
      }
      if (path.endsWith('.g.dart') ||
          path.endsWith('.freezed.dart') ||
          path.endsWith('.gr.dart') ||
          path.contains('${sep}generated$sep') ||
          path.contains('$sep.dart_tool$sep') ||
          path.contains('${sep}build$sep') ||
          path.contains('$sep.pub-cache$sep')) {
        continue;
      }
      files.add(entity);
    }
    return files;
  }

  Map<String, ClassElement> _extractClasses(CompilationUnit unit) {
    final result = <String, ClassElement>{};
    for (final declaration in unit.declarations) {
      if (declaration is ClassDeclaration) {
        final name = _classDeclarationName(declaration);
        if (name != null && name.isNotEmpty) {
          try {
            final el = _classElement(declaration);
            if (el != null) {
              result[name] = el;
            }
          } catch (_) {}
        }
      }
    }
    return result;
  }

  static String? _classDeclarationName(ClassDeclaration declaration) {
    final d = declaration as dynamic;
    // analyzer 8.x: namePart.typeName.lexeme
    try {
      return d.namePart.typeName.lexeme as String?;
    } catch (_) {}
    // analyzer 8.x alternative: nameToken.lexeme
    try {
      return d.nameToken.lexeme as String?;
    } catch (_) {}
    // analyzer 7.x: name.lexeme (Token)
    try {
      return d.name.lexeme as String?;
    } catch (_) {}
    // analyzer 7.x older: name as String directly
    try {
      final n = d.name;
      if (n is String) {
        return n;
      }
    } catch (_) {}
    return null;
  }

  static ClassElement? _classElement(ClassDeclaration declaration) {
    try {
      // analyzer 8.x path
      final fragment = (declaration as dynamic).declaredFragment;
      if (fragment != null) {
        final el = (fragment as dynamic).element;
        if (el is ClassElement) {
          return el;
        }
      }
    } catch (_) {}
    try {
      // analyzer 7.x path
      final el = (declaration as dynamic).declaredElement;
      if (el is ClassElement) {
        return el;
      }
    } catch (_) {}
    return null;
  }

  static bool _hasResultErrors(dynamic result) {
    try {
      return (result.diagnostics as List).isNotEmpty;
    } catch (_) {}
    try {
      return (result.errors as List).isNotEmpty;
    } catch (_) {}
    return false;
  }

  List<WidgetUsage> _visitWidgets(ResolvedUnitResult result) {
    final visitor = _ResolvedWidgetVisitor(result.lineInfo);
    result.unit.visitChildren(visitor);
    return visitor.widgets;
  }

  ProjectIndex _buildIndex(List<ResolvedFile> files) {
    final filesByPath = <String, ResolvedFile>{};
    final fileByClassName = <String, ResolvedFile>{};
    final classElements = <String, ClassElement>{};
    final usagesByType = <String, List<WidgetUsage>>{};

    for (final file in files) {
      filesByPath[file.path] = file;
      for (final entry in file.classElements.entries) {
        fileByClassName[entry.key] = file;
        classElements[entry.key] = entry.value;
      }
      for (final widget in file.widgets) {
        usagesByType.putIfAbsent(widget.type, () => []).add(widget);
      }
    }

    return ProjectIndex(
      filesByPath: filesByPath,
      fileByClassName: fileByClassName,
      classElements: classElements,
      usagesByType: usagesByType,
    );
  }

  static final CompilationUnit _placeholderUnit =
      parseDartFile('_placeholder', '').widgets as dynamic;
}

class _ResolvedWidgetVisitor extends RecursiveAstVisitor<void> {
  final dynamic _lineInfo;
  final List<WidgetUsage> widgets = [];
  final List<String> _ancestors = [];

  _ResolvedWidgetVisitor(this._lineInfo);

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    var source = node.constructorName.type.toSource().trim();
    final gi = source.indexOf('<');
    if (gi != -1) {
      source = source.substring(0, gi);
    }
    final di = source.lastIndexOf('.');
    if (di != -1) {
      source = source.substring(di + 1);
    }
    if (source.isNotEmpty) {
      // Pass as dynamic to avoid NodeList<Argument> vs List<Expression> error.
      _record(
          source, node.argumentList.arguments as dynamic, node.offset, node);
    }
    _ancestors.add(source);
    try {
      super.visitInstanceCreationExpression(node);
    } finally {
      _ancestors.removeLast();
    }
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final name = node.methodName.name;
    if (node.realTarget == null && name.isNotEmpty && _isUpper(name[0])) {
      _record(name, node.argumentList.arguments as dynamic, node.offset, node);
      _ancestors.add(name);
      try {
        super.visitMethodInvocation(node);
      } finally {
        _ancestors.removeLast();
      }
    } else if (node.realTarget is SimpleIdentifier) {
      final targetName = (node.realTarget as SimpleIdentifier).name;
      if (targetName.isNotEmpty && _isUpper(targetName[0])) {
        _record(targetName, node.argumentList.arguments as dynamic, node.offset,
            node);
        _ancestors.add(targetName);
        try {
          super.visitMethodInvocation(node);
        } finally {
          _ancestors.removeLast();
        }
      } else {
        super.visitMethodInvocation(node);
      }
    } else {
      super.visitMethodInvocation(node);
    }
  }

  void _record(String type, dynamic args, int offset, AstNode node) {
    final namedArgs = <String, Expression>{};
    final positionalArgs = <Expression>[];

    for (final arg in args as Iterable) {
      if (_isNamedArg(arg)) {
        final name = _argName(arg);
        final expr = _argExpression(arg);
        if (name != null && expr != null) {
          namedArgs[name] = expr;
        }
      } else if (arg is Expression) {
        positionalArgs.add(arg);
      }
    }

    final loc = _lineInfo.getLocation(offset);
    widgets.add(WidgetUsage(
      type: type,
      namedArgs: namedArgs,
      positionalArgs: positionalArgs,
      ancestors: List.unmodifiable(_ancestors),
      line: loc.lineNumber,
      column: loc.columnNumber,
      offset: offset,
      node: node,
    ));
  }

  static bool _isNamedArg(dynamic arg) {
    try {
      return arg.name != null;
    } catch (_) {
      return false;
    }
  }

  static String? _argName(dynamic arg) {
    try {
      final n = arg.name;
      if (n == null) {
        return null;
      }
      final s = n.toString();
      if (s.isNotEmpty &&
          !s.contains(' ') &&
          !s.contains('.') &&
          !s.contains(':')) {
        return s;
      }
      try {
        return n.label?.name as String?;
      } catch (_) {}
      return null;
    } catch (_) {
      return null;
    }
  }

  static Expression? _argExpression(dynamic arg) {
    try {
      final e = arg.argumentExpression;
      if (e is Expression) {
        return e;
      }
    } catch (_) {}
    try {
      return arg.expression as Expression?;
    } catch (_) {
      return null;
    }
  }

  static bool _isUpper(String c) {
    final code = c.codeUnitAt(0);
    return code >= 0x41 && code <= 0x5A;
  }
}
