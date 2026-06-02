import 'spec.dart';

/// User-level configuration loaded from `ethos.yaml` in a project root.
///
/// This is OPTIONAL. Ethos ships with a complete built-in spec; users only
/// need an `ethos.yaml` when they want to extend it with their design-system
/// widgets or adjust thresholds. The built-in spec is never copied or
/// modified — the config is applied on top of it at load time.
///
/// ## Example
///
/// ```yaml
/// # ethos.yaml in your project root (optional)
///
/// widget_aliases:
///   CircleIconBtn:
///     role: button
///     label_arg: semanticLabel
///     size_guaranteed: true
///     keyboard_ready: true
///
/// rule_overrides:
///   wcag_1_4_3_contrast_minimum:
///     critical_threshold: 95   # stricter than the default 90
/// ```
class EthosConfig {
  /// Custom widgets the user declares as part of their design system.
  /// Merged into the built-in `widget_aliases` (which is empty by default).
  final Map<String, WidgetAlias> widgetAliases;

  /// Per-rule threshold overrides. Keys are `rule_id`s from the built-in
  /// spec; values may set `target` and/or `critical_threshold`.
  final Map<String, RuleOverride> ruleOverrides;

  const EthosConfig({
    this.widgetAliases = const {},
    this.ruleOverrides = const {},
  });

  /// Empty config — equivalent to "no ethos.yaml exists".
  static const EthosConfig empty = EthosConfig();

  factory EthosConfig.fromYaml(Map<String, dynamic> yaml) {
    final aliases = <String, WidgetAlias>{};
    final aliasesYaml = yaml['widget_aliases'] as Map?;
    if (aliasesYaml != null) {
      aliasesYaml.forEach((key, value) {
        if (value is Map) {
          aliases[key.toString()] = WidgetAlias.fromYaml(
            key.toString(),
            Map<String, dynamic>.from(value),
          );
        }
      });
    }

    final overrides = <String, RuleOverride>{};
    final overridesYaml = yaml['rule_overrides'] as Map?;
    if (overridesYaml != null) {
      overridesYaml.forEach((key, value) {
        if (value is Map) {
          overrides[key.toString()] = RuleOverride.fromYaml(
            Map<String, dynamic>.from(value),
          );
        }
      });
    }

    return EthosConfig(
      widgetAliases: aliases,
      ruleOverrides: overrides,
    );
  }

  @override
  String toString() => 'EthosConfig(${widgetAliases.length} aliases, '
      '${ruleOverrides.length} overrides)';
}

/// Threshold overrides for a single rule.
class RuleOverride {
  final double? target;
  final double? criticalThreshold;

  const RuleOverride({this.target, this.criticalThreshold});

  factory RuleOverride.fromYaml(Map<String, dynamic> yaml) {
    return RuleOverride(
      target: (yaml['target'] as num?)?.toDouble(),
      criticalThreshold: (yaml['critical_threshold'] as num?)?.toDouble(),
    );
  }
}
