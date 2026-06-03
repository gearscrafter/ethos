import 'dart:io';

import '../ast/widget_visitor.dart';
import '../coverage_analyzer.dart';
import '../detector_registry.dart';
import '../../models/spec.dart';
import '../../models/coverage_report.dart';

/// Incremental analysis engine used by `ethos watch`.
class WatchEngine {
  final Spec spec;
  final String projectPath;
  final DetectorRegistry registry;
  final bool deepMode;

  /// Per-file parse cache. Key = absolute path.
  final Map<String, ParsedFile> _cache = {};

  /// Last computed report, used for diff calculation.
  CoverageReport? _lastReport;

  WatchEngine({
    required this.spec,
    required this.projectPath,
    required this.registry,
    this.deepMode = false,
  });

  /// Creates a [WatchEngine] using the built-in spec merged with an
  /// optional `ethos.yaml`.
  static Future<WatchEngine> forProject(
    String projectPath, {
    String? configPath,
    bool deepMode = false,
  }) async {
    final analyzer = await CoverageAnalyzer.forProject(
      projectPath,
      configPath: configPath,
    );
    return WatchEngine(
      spec: analyzer.spec,
      projectPath: projectPath,
      registry: analyzer.registry,
      deepMode: deepMode,
    );
  }

  /// Performs the initial full-project scan and populates [_cache].
  Future<CoverageReport> initialScan({
    void Function(int current, int total, String path)? onProgress,
  }) async {
    final files = await _findDartFiles();
    int current = 0;

    for (final file in files) {
      current++;
      onProgress?.call(current, files.length, file.path);
      try {
        final source = await file.readAsString();
        _cache[file.absolute.path] = parseDartFile(file.path, source);
      } catch (_) {}
    }

    _lastReport = _computeReport();
    return _lastReport!;
  }

  /// Re-parses [changedPath] and recomputes the report.
  Future<(CoverageReport, ReportDiff)> reanalyzeFile(String changedPath) async {
    final file = File(changedPath);

    if (!await file.exists()) {
      _cache.remove(file.absolute.path);
    } else {
      try {
        final source = await file.readAsString();
        _cache[file.absolute.path] = parseDartFile(file.path, source);
      } catch (_) {}
    }

    final newReport = _computeReport();
    final diff = ReportDiff.between(_lastReport, newReport);
    _lastReport = newReport;
    return (newReport, diff);
  }

  /// Recomputes the full [CoverageReport] from the current cache.
  CoverageReport _computeReport() {
    final parsedFiles = _cache.values.toList();
    final coverage = <String, RuleCoverage>{};

    for (final rule in spec.rules.values) {
      final detector = registry.find(rule.ruleId);
      if (detector == null) {
        coverage[rule.ruleId] = RuleCoverage.calculate(
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

      coverage[rule.ruleId] = RuleCoverage.calculate(
        ruleId: rule.ruleId,
        title: rule.title,
        matched: result.matched,
        total: result.total,
        indeterminate: result.indeterminate,
        criticalThreshold: rule.coverageMetric.criticalThreshold,
        findings: result.findings,
      );
    }

    final report = CoverageReport(
      specVersion: spec.version,
      projectPath: projectPath,
      timestamp: DateTime.now(),
      coverage: coverage,
      issues: const [],
    );
    report.calculateOverall();
    report.determineComplianceLevel();
    return report;
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
          path.contains('${sep}build$sep')) {
        continue;
      }
      files.add(entity);
    }
    return files;
  }

  int get cachedFileCount => _cache.length;
}

/// Describes what changed between two consecutive reports.
class ReportDiff {
  /// Overall coverage change in percentage points. Positive = improved.
  final double overallDelta;

  /// Per-rule coverage deltas. Key = ruleId.
  final Map<String, double> ruleDelta;

  /// Rules that went from non-critical to critical (regression).
  final List<String> newCritical;

  /// Rules that went from critical to non-critical (improvement).
  final List<String> resolvedCritical;

  const ReportDiff({
    required this.overallDelta,
    required this.ruleDelta,
    required this.newCritical,
    required this.resolvedCritical,
  });

  static ReportDiff between(CoverageReport? before, CoverageReport after) {
    if (before == null) {
      return ReportDiff(
        overallDelta: 0,
        ruleDelta: {},
        newCritical: [],
        resolvedCritical: [],
      );
    }

    final overallDelta = after.overallCoverage - before.overallCoverage;

    final ruleDelta = <String, double>{};
    final newCritical = <String>[];
    final resolvedCritical = <String>[];

    for (final ruleId in after.coverage.keys) {
      final afterRule = after.coverage[ruleId]!;
      final beforeRule = before.coverage[ruleId];
      if (beforeRule == null) {
        continue;
      }

      final delta = afterRule.percentage - beforeRule.percentage;
      if (delta.abs() > 0.01) {
        ruleDelta[ruleId] = delta;
      }

      if (!beforeRule.isCritical && afterRule.isCritical) {
        newCritical.add(ruleId);
      }
      if (beforeRule.isCritical && !afterRule.isCritical) {
        resolvedCritical.add(ruleId);
      }
    }

    return ReportDiff(
      overallDelta: overallDelta,
      ruleDelta: ruleDelta,
      newCritical: newCritical,
      resolvedCritical: resolvedCritical,
    );
  }

  bool get hasChanges =>
      overallDelta.abs() > 0.01 ||
      newCritical.isNotEmpty ||
      resolvedCritical.isNotEmpty;
}
