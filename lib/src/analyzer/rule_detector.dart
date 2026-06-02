import 'package:ethos/src/models/coverage_report.dart';
import 'package:ethos/src/models/spec.dart';

import 'ast/widget_visitor.dart';

/// Contract that every rule detector must implement.
///
/// A detector is responsible for ONE WCAG rule. It receives the parsed AST
/// of every Dart file in a project and reports how many widgets comply,
/// how many do not, and how many it could not evaluate.
///
/// Detectors are designed to be:
/// - **Self-contained**: each lives in its own file.
/// - **Self-registering**: see [DetectorRegistry] — adding a new detector
///   requires zero changes to existing code.
/// - **Honest**: when a detector cannot decide (e.g. a color resolved from
///   a theme), it counts the element as indeterminate, not as pass/fail.
abstract class RuleDetector {
  /// The rule_id this detector implements. MUST match the rule_id in the
  /// YAML spec; the registry uses this for the lookup.
  String get ruleId;

  /// Analyzes all parsed files for this rule and returns coverage.
  ///
  /// [rule] is the spec metadata (title, critical threshold, etc).
  /// [files] are all parsed Dart files in the project.
  DetectionResult analyze({
    required Rule rule,
    required List<ParsedFile> files,
    Map<String, WidgetAlias> aliases = const {},
  });
}

/// Raw counts produced by a [RuleDetector], before they are turned into a
/// [RuleCoverage]. Kept as a plain data class so detectors don't have to
/// know about thresholds or critical-status calculation.
class DetectionResult {
  final int matched;
  final int total;
  final int indeterminate;
  final List<Finding> findings;

  const DetectionResult({
    required this.matched,
    required this.total,
    this.indeterminate = 0,
    this.findings = const [],
  });

  /// Convenience for detectors that found nothing applicable.
  const DetectionResult.empty()
      : matched = 0,
        total = 0,
        indeterminate = 0,
        findings = const [];
}
