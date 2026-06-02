import 'spec.dart';

/// User-level configuration loaded from `ethos.yaml` in a project root.
///
/// This is OPTIONAL. Ethos ships with a complete built-in spec; users only
/// need an `ethos.yaml` when they want to extend it with design-system
/// widgets, color aliases, or threshold overrides.
///
/// ## Example
///
/// ```yaml
/// # ethos.yaml — optional, sits next to pubspec.yaml
///
/// widget_aliases:
///   CircleIconBtn:
///     role: button
///     label_arg: semanticLabel
///     size_guaranteed: true
///     keyboard_ready: true
///
/// color_aliases:
///   "$styles.text.body":
///     foreground: "#212121"
///     background: "#FFFFFF"
///   "$styles.colors.offWhite":
///     foreground: "#FAFAFA"
///
/// rule_overrides:
///   wcag_1_4_3_contrast_minimum:
///     critical_threshold: 95
/// ```
class EthosConfig {
  /// Custom widgets declared as part of the user's design system.
  final Map<String, WidgetAlias> widgetAliases;

  /// Color mappings for design-system style expressions that Ethos cannot
  /// resolve statically (e.g. `$styles.text.body`, `AppColors.primary`).
  ///
  /// Key: the exact source expression as written in code.
  /// Value: the resolved [ColorAlias] with foreground (required) and
  /// optional background.
  final Map<String, ColorAlias> colorAliases;

  /// Per-rule threshold overrides.
  final Map<String, RuleOverride> ruleOverrides;

  const EthosConfig({
    this.widgetAliases = const {},
    this.colorAliases = const {},
    this.ruleOverrides = const {},
  });

  /// Empty config — equivalent to "no ethos.yaml exists".
  static const EthosConfig empty = EthosConfig();

  factory EthosConfig.fromYaml(Map<String, dynamic> yaml) {
    // widget_aliases
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

    // color_aliases
    final colorAliases = <String, ColorAlias>{};
    final colorAliasesYaml = yaml['color_aliases'] as Map?;
    if (colorAliasesYaml != null) {
      colorAliasesYaml.forEach((key, value) {
        if (value is Map) {
          final alias = ColorAlias.fromYaml(Map<String, dynamic>.from(value));
          if (alias != null) {
            colorAliases[key.toString()] = alias;
          }
        }
      });
    }

    // rule_overrides
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
      colorAliases: colorAliases,
      ruleOverrides: overrides,
    );
  }

  @override
  String toString() => 'EthosConfig(${widgetAliases.length} widget aliases, '
      '${colorAliases.length} color aliases, '
      '${ruleOverrides.length} overrides)';
}

class ColorAlias {
  /// The text (foreground) color. Always present.
  final int foreground;

  /// The background color. When null, the detector cannot compute a ratio
  /// from this alias alone — it will still mark the element as indeterminate
  /// unless the background is found via [ThemeExtractor] or inline.
  final int? background;

  const ColorAlias({required this.foreground, this.background});

  /// Parses from a YAML map. Returns null if [foreground] is missing or
  /// unparseable — callers should skip invalid entries rather than crash.
  static ColorAlias? fromYaml(Map<String, dynamic> yaml) {
    final fgStr = yaml['foreground'] as String?;
    if (fgStr == null) {
      return null;
    }
    final fg = _parseHex(fgStr);
    if (fg == null) {
      return null;
    }

    final bgStr = yaml['background'] as String?;
    final bg = bgStr != null ? _parseHex(bgStr) : null;

    return ColorAlias(foreground: fg, background: bg);
  }

  /// Parses `#RRGGBB` or `#AARRGGBB` to a 32-bit ARGB int.
  static int? _parseHex(String hex) {
    final clean = hex.trim().replaceFirst('#', '');
    final value = int.tryParse(clean, radix: 16);
    if (value == null) {
      return null;
    }
    // If only RGB (6 digits), add full opacity.
    return clean.length == 6 ? (0xFF000000 | value) : value;
  }
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
