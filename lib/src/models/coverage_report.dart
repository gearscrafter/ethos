import 'dart:convert';

/// Report model for accessibility coverage analysis results.
class CoverageReport {
  final String specVersion;
  final String projectPath;
  final DateTime timestamp;
  final Map<String, RuleCoverage> coverage;
  final List<String> issues;

  late double overallCoverage;
  late String complianceLevel;

  CoverageReport({
    required this.specVersion,
    required this.projectPath,
    required this.timestamp,
    required this.coverage,
    required this.issues,
  });

  /// Calculates overall coverage percentage based on individual rule coverages.
  ///
  /// Only rules with at least one evaluable element (total > 0) contribute
  /// to the overall average. This prevents rules with no detectable widgets
  /// from skewing the score toward 0%.
  void calculateOverall() {
    final evaluable = coverage.values.where((r) => r.total > 0);
    if (evaluable.isEmpty) {
      overallCoverage = 0.0;
      return;
    }
    final total = evaluable.fold<double>(0, (sum, r) => sum + r.percentage);
    overallCoverage = total / evaluable.length;
  }

  void determineComplianceLevel() {
    if (overallCoverage >= 95) {
      complianceLevel = 'AAA';
    } else if (overallCoverage >= 85) {
      complianceLevel = 'AA';
    } else if (overallCoverage >= 70) {
      complianceLevel = 'A';
    } else {
      complianceLevel = 'NONE';
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'spec_version': specVersion,
      'project_path': projectPath,
      'timestamp': timestamp.toIso8601String(),
      'overall_coverage': double.parse(overallCoverage.toStringAsFixed(2)),
      'compliance_level': complianceLevel,
      'coverage_by_rule': {
        for (final entry in coverage.entries) entry.key: entry.value.toJson(),
      },
      'issues': issues,
    };
  }

  String toJsonString() => jsonEncode(toJson());

  @override
  String toString() =>
      'CoverageReport(spec:$specVersion, coverage:${overallCoverage.toStringAsFixed(2)}%, level:$complianceLevel)';
}

/// Coverage details for a specific rule.
///
/// The triple [matched]/[total]/[indeterminate] is the honest accounting:
/// - [matched]: elements that the detector can confirm comply with the rule.
/// - [total]: elements the detector evaluated (matched + non-matched, but
///   NOT indeterminate). Percentage is matched/total.
/// - [indeterminate]: elements the detector could not evaluate confidently
///   (e.g. a color resolved from a theme or a runtime variable). These are
///   reported separately so the percentage stays honest.
class RuleCoverage {
  final String ruleId;
  final String title;
  final int matched;
  final int total;
  final int indeterminate;
  final double percentage;
  final bool isCritical;

  /// Optional human-readable findings (one per non-compliant element)
  /// useful for editor/CI annotations. Empty if the detector does not
  /// emit per-element findings.
  final List<Finding> findings;

  RuleCoverage({
    required this.ruleId,
    required this.title,
    required this.matched,
    required this.total,
    required this.percentage,
    required this.isCritical,
    this.indeterminate = 0,
    this.findings = const [],
  });

  factory RuleCoverage.calculate({
    required String ruleId,
    required String title,
    required int matched,
    required int total,
    required double criticalThreshold,
    int indeterminate = 0,
    List<Finding> findings = const [],
  }) {
    final percentage = total > 0 ? (matched / total) * 100 : 0.0;
    final isCritical = total > 0 && percentage < criticalThreshold;

    return RuleCoverage(
      ruleId: ruleId,
      title: title,
      matched: matched,
      total: total,
      indeterminate: indeterminate,
      percentage: percentage,
      isCritical: isCritical,
      findings: findings,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'rule_id': ruleId,
      'title': title,
      'matched': matched,
      'total': total,
      'indeterminate': indeterminate,
      'percentage': double.parse(percentage.toStringAsFixed(2)),
      'is_critical': isCritical,
      if (findings.isNotEmpty)
        'findings': findings.map((f) => f.toJson()).toList(),
    };
  }

  @override
  String toString() {
    final indPart = indeterminate > 0 ? ' (+$indeterminate indeterminate)' : '';
    final critPart = isCritical ? ' ⚠️ CRITICAL' : '';
    return 'RuleCoverage($ruleId: ${percentage.toStringAsFixed(2)}% '
        '($matched/$total)$indPart$critPart)';
  }
}

/// A single non-compliant or indeterminate element found by a detector.
class Finding {
  final String filePath;
  final int line;
  final int column;
  final String widgetType;
  final String message;
  final FindingSeverity severity;

  Finding({
    required this.filePath,
    required this.line,
    required this.column,
    required this.widgetType,
    required this.message,
    this.severity = FindingSeverity.fail,
  });

  Map<String, dynamic> toJson() => {
        'file': filePath,
        'line': line,
        'column': column,
        'widget': widgetType,
        'message': message,
        'severity': severity.name,
      };

  @override
  String toString() => '$filePath:$line:$column $widgetType — $message';
}

enum FindingSeverity { fail, indeterminate, info }
