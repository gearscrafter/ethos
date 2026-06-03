import 'dart:io';

import '../models/spec.dart';
import '../models/coverage_report.dart';
import 'ast/widget_visitor.dart';
import 'detector_registry.dart';
import 'spec_loader.dart';

/// Main analyzer engine. Calculates accessibility coverage for a Flutter
/// project by parsing every Dart file once with `package:analyzer` and
/// dispatching each rule to its registered detector.
///
/// ## Recommended entry point
///
/// ```dart
/// final analyzer = await CoverageAnalyzer.forProject('./my_flutter_app');
/// final report = await analyzer.analyze();
/// ```
///
/// This uses the built-in WCAG 2.2 spec packaged with Ethos and
/// automatically merges any `ethos.yaml` found in the project root. The user
/// never copies the WCAG spec.
class CoverageAnalyzer {
  final Spec spec;
  final DetectorRegistry registry;
  final String projectPath;

  CoverageAnalyzer({
    required this.spec,
    required this.projectPath,
    DetectorRegistry? registry,
  }) : registry = registry ?? DetectorRegistry.withBuiltIns();

  static Future<CoverageAnalyzer> forProject(
    String projectPath, {
    String? configPath,
    DetectorRegistry? registry,
  }) async {
    final spec = await SpecLoader.load(
      projectPath: projectPath,
      configPath: configPath,
    );
    return CoverageAnalyzer(
      spec: spec,
      projectPath: projectPath,
      registry: registry,
    );
  }

  static Future<CoverageAnalyzer> loadFromFile(
    String specPath, {
    required String projectPath,
    DetectorRegistry? registry,
  }) async {
    final spec = await SpecLoader.loadFromFile(specPath);
    SpecLoader.validate(spec);
    return CoverageAnalyzer(
      spec: spec,
      projectPath: projectPath,
      registry: registry,
    );
  }

  static CoverageAnalyzer fromString(
    String yamlContent, {
    required String projectPath,
    DetectorRegistry? registry,
  }) {
    final spec = SpecLoader.loadFromString(yamlContent);
    SpecLoader.validate(spec);
    return CoverageAnalyzer(
      spec: spec,
      projectPath: projectPath,
      registry: registry,
    );
  }

  Future<CoverageReport> analyze() async {
    final report = CoverageReport(
      specVersion: spec.version,
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

      final parsedFiles = <ParsedFile>[];
      for (final file in dartFiles) {
        try {
          final source = await file.readAsString();
          parsedFiles.add(parseDartFile(file.path, source));
        } catch (e) {
          report.issues.add('Failed to parse ${file.path}: $e');
        }
      }

      for (final rule in spec.rules.values) {
        final detector = registry.find(rule.ruleId);
        if (detector == null) {
          report.issues.add(
            'No detector registered for rule "${rule.ruleId}" — skipping.',
          );
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
          files: parsedFiles,
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
      return report;
    } catch (e) {
      report.issues.add('Analysis error: $e');
      report.calculateOverall();
      report.determineComplianceLevel();
      return report;
    }
  }

  Future<CoverageReport> analyzeFiles(List<ParsedFile> parsedFiles) async {
    final report = CoverageReport(
      specVersion: spec.version,
      projectPath: projectPath,
      timestamp: DateTime.now(),
      coverage: {},
      issues: [],
    );

    for (final rule in spec.rules.values) {
      final detector = registry.find(rule.ruleId);
      if (detector == null) {
        report.issues.add(
          'No detector registered for rule "${rule.ruleId}" — skipping.',
        );
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
        files: parsedFiles,
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
    return report;
  }

  Future<List<File>> _findDartFiles(String root) async {
    final dir = Directory(root);
    final dartFiles = <File>[];
    if (!await dir.exists()) return dartFiles;
    final sep = Platform.pathSeparator;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final path = entity.path;
      if (!path.endsWith('.dart')) continue;
      if (path.endsWith('.g.dart') ||
          path.endsWith('.freezed.dart') ||
          path.endsWith('.gr.dart') ||
          path.contains('${sep}generated$sep') ||
          path.contains('$sep.dart_tool$sep') ||
          path.contains('${sep}build$sep') ||
          path.contains('$sep.pub-cache$sep')) {
        continue;
      }
      dartFiles.add(entity);
    }
    return dartFiles;
  }
}
