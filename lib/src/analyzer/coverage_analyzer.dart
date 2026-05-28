import 'dart:io';

import '../models/spec.dart';
import '../models/coverage_report.dart';
import 'ast/widget_visitor.dart';
import 'detector_registry.dart';
import 'spec_loader.dart';

/// Main analyzer engine. Calculates accessibility coverage for a Flutter
/// project by parsing every Dart file once with `package:analyzer` and
/// dispatching each rule to its registered [RuleDetector].
///
/// The engine itself contains no rule-specific logic: adding, removing, or
/// modifying a detector does not touch this class.
class CoverageAnalyzer {
  final Spec spec;
  final DetectorRegistry registry;

  CoverageAnalyzer({required this.spec, DetectorRegistry? registry})
      : registry = registry ?? DetectorRegistry.withBuiltIns();

  static Future<CoverageAnalyzer> loadFromFile(
    String specPath, {
    DetectorRegistry? registry,
  }) async {
    final spec = await SpecLoader.loadFromFile(specPath);
    SpecLoader.validate(spec);
    return CoverageAnalyzer(spec: spec, registry: registry);
  }

  static CoverageAnalyzer fromString(
    String yamlContent, {
    DetectorRegistry? registry,
  }) {
    final spec = SpecLoader.loadFromString(yamlContent);
    SpecLoader.validate(spec);
    return CoverageAnalyzer(spec: spec, registry: registry);
  }

  /// Analyzes a Flutter project against the loaded spec.
  ///
  /// Pipeline:
  ///   1. Discover Dart files (skipping generated / .g.dart / build dirs).
  ///   2. Parse each file once into a [ParsedFile] (AST + widget list).
  ///   3. For each rule in the spec, look up its detector and run it.
  ///   4. Aggregate into a [CoverageReport].
  Future<CoverageReport> analyze({
    required String projectPath,
    String? specVersion,
  }) async {
    final report = CoverageReport(
      specVersion: specVersion ?? spec.version,
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

      // Parse all files once — every detector reuses the same AST.
      final parsedFiles = <ParsedFile>[];
      for (final file in dartFiles) {
        try {
          final source = await file.readAsString();
          parsedFiles.add(parseDartFile(file.path, source));
        } catch (e) {
          report.issues.add('Failed to parse ${file.path}: $e');
        }
      }

      // Run each rule's detector.
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

        final result = detector.analyze(rule: rule, files: parsedFiles);
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

  /// Walks [projectPath] recursively, returning every `.dart` file that
  /// looks like project source. Generated files, build outputs, and the
  /// pub cache are excluded.
  Future<List<File>> _findDartFiles(String projectPath) async {
    final dir = Directory(projectPath);
    final dartFiles = <File>[];

    if (!await dir.exists()) return dartFiles;

    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final path = entity.path;
      if (!path.endsWith('.dart')) continue;

      // Skip generated / build / pub cache.
      if (path.endsWith('.g.dart') ||
          path.endsWith('.freezed.dart') ||
          path.endsWith('.gr.dart') ||
          path.contains('${Platform.pathSeparator}generated${Platform.pathSeparator}') ||
          path.contains('${Platform.pathSeparator}.dart_tool${Platform.pathSeparator}') ||
          path.contains('${Platform.pathSeparator}build${Platform.pathSeparator}') ||
          path.contains('${Platform.pathSeparator}.pub-cache${Platform.pathSeparator}')) {
        continue;
      }

      dartFiles.add(entity);
    }

    return dartFiles;
  }
}