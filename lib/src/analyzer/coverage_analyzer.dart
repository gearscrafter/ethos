import 'dart:io';
import '../models/spec.dart';
import '../models/coverage_report.dart';
import 'spec_loader.dart';

/// Main analyzer engine that analyzes Flutter projects to calculate accessibility coverage.
///
/// This class is responsible for:
/// - Loading accessibility specifications from YAML files
/// - Scanning Flutter projects for Dart files
/// - Analyzing code against WCAG 2.2 rules
/// - Calculating coverage metrics
/// - Generating comprehensive reports
///
/// The analyzer uses pattern matching (regex) to detect accessibility issues
/// and measure coverage percentages for each rule.
///
class CoverageAnalyzer {
  final Spec spec;

  CoverageAnalyzer({required this.spec});

  static Future<CoverageAnalyzer> loadFromFile(String specPath) async {
    final spec = await SpecLoader.loadFromFile(specPath);
    SpecLoader.validate(spec);
    return CoverageAnalyzer(spec: spec);
  }

  static CoverageAnalyzer fromString(String yamlContent) {
    final spec = SpecLoader.loadFromString(yamlContent);
    SpecLoader.validate(spec);
    return CoverageAnalyzer(spec: spec);
  }

  /// Analyzes a Flutter project to calculate accessibility coverage.
  Future<CoverageReport> analyze({
    required String projectPath,
    String specVersion = 'v1.0.0',
  }) async {
    final report = CoverageReport(
      specVersion: specVersion,
      projectPath: projectPath,
      timestamp: DateTime.now(),
      coverage: {},
      issues: [],
    );

    try {
      final dartFiles = await _findDartFiles(projectPath);

      if (dartFiles.isEmpty) {
        report.issues.add('No Dart files found in $projectPath');
        report.calculateOverall();
        report.determineComplianceLevel();
        return report;
      }

      for (final rule in spec.rules.values) {
        final coverage = await _calculateRuleCoverage(
          rule: rule,
          dartFiles: dartFiles,
        );
        report.coverage[rule.ruleId] = coverage;
      }

      report.calculateOverall();
      report.determineComplianceLevel();

      return report;
    } catch (e) {
      report.issues.add('Analysis error: $e');
      report.calculateOverall();
      report.determineComplianceLevel();
      return report;
    }
  }

  Future<List<File>> _findDartFiles(String projectPath) async {
    final dir = Directory(projectPath);
    final dartFiles = <File>[];

    try {
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File && entity.path.endsWith('.dart')) {
          if (!entity.path.contains('.g.dart') &&
              !entity.path.contains('generated')) {
            dartFiles.add(entity);
          }
        }
      }
    } catch (e) {}

    return dartFiles;
  }

  Future<RuleCoverage> _calculateRuleCoverage({
    required Rule rule,
    required List<File> dartFiles,
  }) async {
    int matched = 0;
    int total = 0;

    for (final file in dartFiles) {
      try {
        final content = await file.readAsString();
        final (ruleMatched, ruleTotal) = _analyzeFileForRule(
          rule: rule,
          fileContent: content,
        );
        matched += ruleMatched;
        total += ruleTotal;
      } catch (e) {}
    }

    return RuleCoverage.calculate(
      ruleId: rule.ruleId,
      title: rule.title,
      matched: matched,
      total: total,
      criticalThreshold: rule.coverageMetric.criticalThreshold,
    );
  }

  (int matched, int total) _analyzeFileForRule({
    required Rule rule,
    required String fileContent,
  }) {
    switch (rule.ruleId) {
      case 'wcag_1_3_1_semantics_label':
        return _analyzeSemanticLabels(fileContent);
      case 'wcag_1_4_3_contrast_minimum':
        return _analyzeContrast(fileContent);
      case 'wcag_2_5_5_target_size_enhanced':
        return _analyzeTouchTargets(fileContent);
      case 'wcag_2_1_1_keyboard':
        return _analyzeKeyboardNavigation(fileContent);
      case 'wcag_2_4_3_focus_order':
        return _analyzeFocusOrder(fileContent);
      default:
        return (0, 0);
    }
  }

  (int matched, int total) _analyzeSemanticLabels(String code) {
    final gesturePattern = RegExp(r'GestureDetector\s*\(');
    final inkWellPattern = RegExp(r'InkWell\s*\(');
    final inkResponsePattern = RegExp(r'InkResponse\s*\(');

    final totalCustomInteractive = gesturePattern.allMatches(code).length +
        inkWellPattern.allMatches(code).length +
        inkResponsePattern.allMatches(code).length;

    final semanticsLabelPattern = RegExp(r'Semantics\s*\(\s*label\s*:\s*');
    final withSemantics = semanticsLabelPattern.allMatches(code).length;

    return (withSemantics, totalCustomInteractive);
  }

  (int matched, int total) _analyzeContrast(String code) {
    final lowContrastPatterns = [
      RegExp(r'Colors\.(grey|gray|lightGrey|lightGray|disabled)'),
      RegExp(r'Color\(0x[89a-fA-F][0-9a-fA-F]{5}\)'),
    ];

    final textPatterns = [
      RegExp(r'Text\s*\('),
      RegExp(r'TextStyle\s*\('),
      RegExp(r'style\s*:\s*TextStyle'),
    ];

    final textElements = textPatterns.fold<int>(
      0,
      (sum, pattern) => sum + pattern.allMatches(code).length,
    );

    final lowContrastElements = lowContrastPatterns.fold<int>(
      0,
      (sum, pattern) => sum + pattern.allMatches(code).length,
    );

    final matched = textElements - lowContrastElements;

    return (matched > 0 ? matched : 0, textElements > 0 ? textElements : 0);
  }

  (int matched, int total) _analyzeTouchTargets(String code) {
    final interactivePattern = RegExp(
      r'(GestureDetector|InkWell|ElevatedButton|TextButton|IconButton|FloatingActionButton)\s*\(',
    );
    final totalInteractive = interactivePattern.allMatches(code).length;

    final sizePattern = RegExp(r'(width|height)\s*:\s*(4[8-9]|[5-9]\d|\d{3,})');
    final withGoodSize = sizePattern.allMatches(code).length;

    final materialPattern = RegExp(
      r'(ElevatedButton|TextButton|IconButton|FloatingActionButton)\s*\(',
    );
    final materialWidgets = materialPattern.allMatches(code).length;

    final matched = materialWidgets + (withGoodSize ~/ 2);

    return (matched, totalInteractive > 0 ? totalInteractive : 0);
  }

  (int matched, int total) _analyzeKeyboardNavigation(String code) {
    final interactivePattern = RegExp(
      r'(GestureDetector|InkWell|ElevatedButton|TextButton|IconButton|FloatingActionButton|TextField)\s*\(',
    );
    final totalInteractive = interactivePattern.allMatches(code).length;

    final keyboardAccessiblePattern = RegExp(
      r'(ElevatedButton|TextButton|IconButton|FloatingActionButton|OutlinedButton|TextField)\s*\(',
    );
    final keyboardAccessible =
        keyboardAccessiblePattern.allMatches(code).length;

    return (keyboardAccessible, totalInteractive > 0 ? totalInteractive : 0);
  }

  (int matched, int total) _analyzeFocusOrder(String code) {
    final focusPattern = RegExp(r'(FocusScope|FocusNode|autofocus\s*:\s*true)');
    final withFocusManagement = focusPattern.allMatches(code).length;

    final structurePattern =
        RegExp(r'(Form|Column|ListView|CustomScrollView)\s*\(');
    final structuredLayouts = structurePattern.allMatches(code).length;

    return (withFocusManagement, structuredLayouts > 0 ? structuredLayouts : 1);
  }
}
