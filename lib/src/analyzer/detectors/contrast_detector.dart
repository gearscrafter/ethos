import 'package:analyzer/dart/ast/ast.dart';

import '../../models/spec.dart';
import '../../models/coverage_report.dart';
import '../ast/widget_visitor.dart';
import '../rule_detector.dart';
import '../utils/color_resolver.dart';

/// Detects WCAG 1.4.3 — Minimum Color Contrast.
///
/// ## The honesty problem
///
/// True contrast checking needs BOTH the text color and the color it sits
/// on. In real Flutter code these are almost never in the same node: the
/// text color lives in `TextStyle(color:)` while the background comes from
/// an ancestor `Container`, `Scaffold`, or the theme — often several levels
/// away and frequently resolved at runtime. Reconstructing that with purely
/// syntactic analysis is not reliably possible.
///
/// So this detector measures only the **verifiable** case: a `Text` whose
/// `style` declares both `color` and `backgroundColor` as resolvable
/// literals. There it computes the real WCAG ratio and judges PASS/FAIL.
///
/// Everything else is reported honestly:
/// - A `Text` with a resolvable text color but no inline background →
///   **indeterminate** (we can't see what it sits on).
/// - Colors from theme / `$styles` / variables → **indeterminate**.
///
/// This keeps the percentage meaningful: it reflects text whose contrast we
/// could actually verify, not a guess.
///
/// ## Thresholds
///
/// WCAG AA: 4.5:1 for normal text, 3:1 for large text (>=18pt, or >=14pt
/// bold). Without resolved font metrics we apply the stricter 4.5:1 by
/// default; a `fontSize` literal >= 18 relaxes to 3:1.
class ContrastDetector implements RuleDetector {
  static const double _ratioNormal = 4.5;
  static const double _ratioLarge = 3.0;
  static const double _largeFontPt = 18.0;

  @override
  String get ruleId => 'wcag_1_4_3_contrast_minimum';

  @override
  DetectionResult analyze({
    required Rule rule,
    required List<ParsedFile> files,
    Map<String, WidgetAlias> aliases = const {},
  }) {
    int matched = 0;
    int total = 0;
    int indeterminate = 0;
    final findings = <Finding>[];

    for (final file in files) {
      for (final widget in file.widgets) {
        if (widget.type != 'Text') continue;

        final styleArg = widget.arg('style');
        if (styleArg == null) {
          indeterminate++;
          continue;
        }

        final colors = _extractColors(styleArg);
        if (colors == null) {
          indeterminate++;
          continue;
        }

        final (fg, bg, fontSize) = colors;

        if (fg == null || bg == null) {
          indeterminate++;
          continue;
        }

        total++;

        final ratio = ColorResolver.contrastRatio(fg, bg);
        final required = (fontSize != null && fontSize >= _largeFontPt)
            ? _ratioLarge
            : _ratioNormal;

        if (ratio >= required) {
          matched++;
        } else {
          findings.add(Finding(
            filePath: file.path,
            line: widget.line,
            column: widget.column,
            widgetType: 'Text',
            message:
                'Contrast ratio ${ratio.toStringAsFixed(2)}:1 is below the '
                '${required.toStringAsFixed(1)}:1 minimum required by WCAG AA.',
          ));
        }
      }
    }

    return DetectionResult(
      matched: matched,
      total: total,
      indeterminate: indeterminate,
      findings: findings,
    );
  }

  /// Extracts (foreground, background, fontSize) from a `style:` argument
  /// if it is an inline `TextStyle(...)`. Each element may be null if that
  /// piece isn't a resolvable literal. Returns null if `style` isn't an
  /// inline TextStyle at all (e.g. `style: $styles.text.body`).
  (int?, int?, double?)? _extractColors(Expression styleArg) {
    final name = _ctorName(styleArg);
    if (name != 'TextStyle') return null;

    final args = _args(styleArg);
    if (args == null) return null;

    int? fg;
    int? bg;
    double? fontSize;

    for (final arg in args) {
      if (arg is! NamedExpression) continue;
      final key = arg.name.label.name;
      final value = arg.expression;

      switch (key) {
        case 'color':
          fg = ColorResolver.resolve(value);
        case 'backgroundColor':
          bg = ColorResolver.resolve(value);
        case 'fontSize':
          if (value is DoubleLiteral) {
            fontSize = value.value;
          } else if (value is IntegerLiteral) {
            fontSize = value.value?.toDouble();
          }
      }
    }

    return (fg, bg, fontSize);
  }

  String? _ctorName(Expression expr) {
    if (expr is InstanceCreationExpression) {
      return expr.constructorName.type.name2.lexeme;
    }
    if (expr is MethodInvocation && expr.realTarget == null) {
      return expr.methodName.name;
    }
    return null;
  }

  NodeList<Expression>? _args(Expression expr) {
    if (expr is InstanceCreationExpression) return expr.argumentList.arguments;
    if (expr is MethodInvocation) return expr.argumentList.arguments;
    return null;
  }
}