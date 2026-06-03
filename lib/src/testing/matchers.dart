import 'package:ethos/src/models/coverage_report.dart';
import 'package:matcher/matcher.dart';

/// WCAG compliance levels used in test matchers.
enum WcagLevel {
  /// Level A — basic accessibility (≥ 70% overall coverage).
  a,

  /// Level AA — strong accessibility (≥ 85% overall coverage).
  aa,

  /// Level AAA — enhanced accessibility (≥ 95% overall coverage).
  aaa,
}

/// Matches a [CoverageReport] whose [CoverageReport.complianceLevel] is at
/// least [level].
///
/// ```dart
/// expect(report, meetsAccessibilityLevel(WcagLevel.a));
/// expect(report, meetsAccessibilityLevel(WcagLevel.aa));
/// ```
Matcher meetsAccessibilityLevel(WcagLevel level) =>
    _MeetsAccessibilityLevel(level);

/// Matches a [CoverageReport] where the rule identified by [ruleId] is not
/// critical (i.e. its coverage is at or above the rule's critical threshold).
///
/// ```dart
/// expect(report, passesRule('wcag_1_3_1_semantics_label'));
/// ```
Matcher passesRule(String ruleId) => _PassesRule(ruleId);

/// Matches a [CoverageReport] where the rule identified by [ruleId] has a
/// coverage percentage that satisfies [coverageMatcher].
///
/// ```dart
/// expect(report, hasRuleCoverage(
///   'wcag_1_3_1_semantics_label',
///   greaterThan(80),
/// ));
/// ```
Matcher hasRuleCoverage(String ruleId, Matcher coverageMatcher) =>
    _HasRuleCoverage(ruleId, coverageMatcher);

/// Matches a [CoverageReport] with no rules below their critical threshold.
///
/// ```dart
/// expect(report, hasNoCriticalFailures());
/// ```
Matcher hasNoCriticalFailures() => _HasNoCriticalFailures();

/// Matches a [CoverageReport] with no [Finding]s for the given [ruleId].
///
/// ```dart
/// expect(report, hasNoFindingsFor('wcag_1_1_1_non_text_content'));
/// ```
Matcher hasNoFindingsFor(String ruleId) => _HasNoFindingsFor(ruleId);

// ─── implementations ─────────────────────────────────────────────────────────

class _MeetsAccessibilityLevel extends Matcher {
  final WcagLevel level;
  const _MeetsAccessibilityLevel(this.level);

  static const _thresholds = {
    WcagLevel.a: 70.0,
    WcagLevel.aa: 85.0,
    WcagLevel.aaa: 95.0,
  };

  static const _labels = {
    WcagLevel.a: 'A',
    WcagLevel.aa: 'AA',
    WcagLevel.aaa: 'AAA',
  };

  @override
  bool matches(dynamic item, Map matchState) {
    if (item is! CoverageReport) {
      return false;
    }
    final threshold = _thresholds[level]!;
    return item.overallCoverage >= threshold;
  }

  @override
  Description describe(Description description) =>
      description.add('meets WCAG Level ${_labels[level]} '
          '(overall coverage ≥ ${_thresholds[level]}%)');

  @override
  Description describeMismatch(
    dynamic item,
    Description mismatchDescription,
    Map matchState,
    bool verbose,
  ) {
    if (item is! CoverageReport) {
      return mismatchDescription.add('is not a CoverageReport');
    }
    return mismatchDescription.add(
      'has overall coverage ${item.overallCoverage.toStringAsFixed(1)}% '
      '(compliance: ${item.complianceLevel})',
    );
  }
}

class _PassesRule extends Matcher {
  final String ruleId;
  const _PassesRule(this.ruleId);

  @override
  bool matches(dynamic item, Map matchState) {
    if (item is! CoverageReport) {
      return false;
    }
    final rule = item.coverage[ruleId];
    if (rule == null) {
      return false;
    }
    return !rule.isCritical;
  }

  @override
  Description describe(Description description) =>
      description.add('passes rule "$ruleId" (not critical)');

  @override
  Description describeMismatch(
    dynamic item,
    Description mismatchDescription,
    Map matchState,
    bool verbose,
  ) {
    if (item is! CoverageReport) {
      return mismatchDescription.add('is not a CoverageReport');
    }
    final rule = item.coverage[ruleId];
    if (rule == null) {
      return mismatchDescription.add('has no coverage data for "$ruleId"');
    }
    return mismatchDescription.add(
      '"$ruleId" is CRITICAL: '
      '${rule.percentage.toStringAsFixed(1)}% '
      '(${rule.matched}/${rule.total})',
    );
  }
}

class _HasRuleCoverage extends Matcher {
  final String ruleId;
  final Matcher coverageMatcher;
  const _HasRuleCoverage(this.ruleId, this.coverageMatcher);

  @override
  bool matches(dynamic item, Map matchState) {
    if (item is! CoverageReport) {
      return false;
    }
    final rule = item.coverage[ruleId];
    if (rule == null) {
      return false;
    }
    return coverageMatcher.matches(rule.percentage, matchState);
  }

  @override
  Description describe(Description description) =>
      description.add('"$ruleId" coverage ').addDescriptionOf(coverageMatcher);

  @override
  Description describeMismatch(
    dynamic item,
    Description mismatchDescription,
    Map matchState,
    bool verbose,
  ) {
    if (item is! CoverageReport) {
      return mismatchDescription.add('is not a CoverageReport');
    }
    final rule = item.coverage[ruleId];
    if (rule == null) {
      return mismatchDescription.add('has no coverage data for "$ruleId"');
    }
    return mismatchDescription.add(
      '"$ruleId" coverage is ${rule.percentage.toStringAsFixed(1)}% '
      '(${rule.matched}/${rule.total})',
    );
  }
}

class _HasNoCriticalFailures extends Matcher {
  const _HasNoCriticalFailures();

  @override
  bool matches(dynamic item, Map matchState) {
    if (item is! CoverageReport) {
      return false;
    }
    return !item.coverage.values.any((c) => c.isCritical);
  }

  @override
  Description describe(Description description) =>
      description.add('has no critical rule failures');

  @override
  Description describeMismatch(
    dynamic item,
    Description mismatchDescription,
    Map matchState,
    bool verbose,
  ) {
    if (item is! CoverageReport) {
      return mismatchDescription.add('is not a CoverageReport');
    }
    final critical = item.coverage.values
        .where((c) => c.isCritical)
        .map((c) => '"${c.ruleId}" (${c.percentage.toStringAsFixed(1)}%)')
        .join(', ');
    return mismatchDescription.add('has critical failures: $critical');
  }
}

class _HasNoFindingsFor extends Matcher {
  final String ruleId;
  const _HasNoFindingsFor(this.ruleId);

  @override
  bool matches(dynamic item, Map matchState) {
    if (item is! CoverageReport) {
      return false;
    }
    final rule = item.coverage[ruleId];
    if (rule == null) {
      return true;
    }
    return rule.findings.isEmpty;
  }

  @override
  Description describe(Description description) =>
      description.add('has no findings for "$ruleId"');

  @override
  Description describeMismatch(
    dynamic item,
    Description mismatchDescription,
    Map matchState,
    bool verbose,
  ) {
    if (item is! CoverageReport) {
      return mismatchDescription.add('is not a CoverageReport');
    }
    final rule = item.coverage[ruleId];
    if (rule == null) {
      return mismatchDescription.add('has no coverage data for "$ruleId"');
    }
    final count = rule.findings.length;
    return mismatchDescription.add(
      'has $count finding${count == 1 ? "" : "s"} for "$ruleId":\n'
      '${rule.findings.map((f) => '  • ${f.filePath}:${f.line} — ${f.message}').join('\n')}',
    );
  }
}
