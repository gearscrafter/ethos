import 'dart:convert';

/// Report model for accessibility coverage analysis results.
class CoverageReport {
  final String specVersion;
  final String projectPath;
  final DateTime timestamp;
  final Map<String, RuleCoverage> coverage; // rule_id -> RuleCoverage
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

  /// Calculates overall coverage percentage based on individual rule coverages
  void calculateOverall() {
    if (coverage.isEmpty) {
      overallCoverage = 0.0;
    } else {
      final total = coverage.values.fold<double>(
        0,
        (sum, rule) => sum + rule.percentage,
      );
      overallCoverage = total / coverage.length;
    }
  }

  /// Determines the compliance level based on overall coverage
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

  /// Converts the report to a JSON-serializable map
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

  /// Converts the report to a JSON string
  String toJsonString() {
    return jsonEncode(toJson());
  }

  @override
  String toString() =>
      'CoverageReport(spec:$specVersion, coverage:${overallCoverage.toStringAsFixed(2)}%, level:$complianceLevel)';
}

/// Coverage details for a specific rule.
class RuleCoverage {
  final String ruleId;
  final String title;
  final int matched;
  final int total;
  final double percentage;
  final bool isCritical;

  RuleCoverage({
    required this.ruleId,
    required this.title,
    required this.matched,
    required this.total,
    required this.percentage,
    required this.isCritical,
  });

  factory RuleCoverage.calculate({
    required String ruleId,
    required String title,
    required int matched,
    required int total,
    required double criticalThreshold,
  }) {
    final percentage = total > 0 ? (matched / total) * 100 : 0.0;
    final isCritical = percentage < criticalThreshold;

    return RuleCoverage(
      ruleId: ruleId,
      title: title,
      matched: matched,
      total: total,
      percentage: percentage,
      isCritical: isCritical,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'rule_id': ruleId,
      'title': title,
      'matched': matched,
      'total': total,
      'percentage': double.parse(percentage.toStringAsFixed(2)),
      'is_critical': isCritical,
    };
  }

  @override
  String toString() =>
      'RuleCoverage($ruleId: ${percentage.toStringAsFixed(2)}% ($matched/$total)${isCritical ? ' ⚠️ CRITICAL' : ''})';
}
