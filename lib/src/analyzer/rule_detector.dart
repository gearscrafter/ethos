import '../models/coverage_report.dart';
import '../models/ethos_config.dart';
import '../models/spec.dart';
import 'ast/widget_visitor.dart';

/// Contract that every rule detector must implement.
abstract class RuleDetector {
  /// The rule_id this detector implements.
  String get ruleId;

  /// Analyzes all parsed files for this rule and returns coverage.
  ///
  /// [rule]         — spec metadata (title, critical threshold, etc).
  /// [files]        — all parsed Dart files in the project.
  /// [aliases]      — user-declared widget aliases from `ethos.yaml`.
  /// [colorAliases] — user-declared color mappings from `ethos.yaml`.
  ///                  Only consumed by [ContrastDetector]; other detectors
  ///                  can safely ignore it.
  DetectionResult analyze({
    required Rule rule,
    required List<ParsedFile> files,
    Map<String, WidgetAlias> aliases = const {},
    Map<String, ColorAlias> colorAliases = const {},
  });
}

/// Raw counts produced by a [RuleDetector].
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

  const DetectionResult.empty()
      : matched = 0,
        total = 0,
        indeterminate = 0,
        findings = const [];
}
