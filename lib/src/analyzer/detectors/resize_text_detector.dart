import 'package:analyzer/dart/ast/ast.dart';

import '../../models/ethos_config.dart';
import '../../models/spec.dart';
import '../../models/coverage_report.dart';
import '../ast/widget_visitor.dart';
import '../rule_detector.dart';

/// Detects WCAG 1.4.4 — Resize Text.
///
/// Text must be resizable up to 200% without loss of content or
/// functionality. Hardcoding `textScaleFactor` (deprecated) or
/// `textScaler` to a fixed value prevents users from using their system
/// font-size preferences.
///
/// ## In scope
///
/// - `Text(textScaleFactor: <literal>)` — legacy API, deprecated in Flutter 3.
/// - `Text(textScaler: TextScaler.noScaling)` or
///   `Text(textScaler: TextScaler.linear(<literal>))`.
/// - `MediaQuery(textScaleFactor: <literal>, ...)` — forces scale globally.
/// - `MediaQuery.removePadding` / `MediaQuery.copyWith` with literal
///   `textScaleFactor`.
///
/// ## Outcomes
///
/// - **Pass:** `Text` without any `textScaleFactor` / `textScaler` override
///   — inherits system preference (the vast majority of Flutter apps).
/// - **Fail:** literal `textScaleFactor` ≠ null, or `TextScaler.noScaling`,
///   or `TextScaler.linear(<literal>)`.
/// - **Indeterminate:** scale factor from a variable or method call — cannot
///   determine if it clamps properly.
///
/// ## Note on `MediaQuery` scope
///
/// A `MediaQuery(textScaleFactor: 1.0, ...)` affects all `Text` descendants.
/// We flag the `MediaQuery` itself rather than every individual `Text` — one
/// finding is clearer than hundreds.
class ResizeTextDetector implements RuleDetector {
  @override
  String get ruleId => 'wcag_1_4_4_resize_text';

  @override
  DetectionResult analyze({
    required Rule rule,
    required List<ParsedFile> files,
    Map<String, WidgetAlias> aliases = const {},
    Map<String, ColorAlias> colorAliases = const {},
  }) {
    int matched = 0;
    int total = 0;
    int indeterminate = 0;
    final findings = <Finding>[];

    for (final file in files) {
      for (final widget in file.widgets) {
        if (!_hasExplicitScaleArg(widget)) {
          continue;
        }

        final verdict = _classify(widget);
        if (verdict == null) {
          continue;
        }

        switch (verdict) {
          case _ScaleVerdict.pass:
            total++;
            matched++;
          case _ScaleVerdict.fail:
            total++;
            findings.add(Finding(
              filePath: file.path,
              line: widget.line,
              column: widget.column,
              widgetType: widget.type,
              message: _failMessage(widget),
            ));
          case _ScaleVerdict.indeterminate:
            indeterminate++;
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

  bool _hasExplicitScaleArg(WidgetUsage widget) {
    if (widget.type != 'Text' && widget.type != 'MediaQuery') {
      return false;
    }
    return widget.namedArgs.containsKey('textScaleFactor') ||
        widget.namedArgs.containsKey('textScaler');
  }

  _ScaleVerdict? _classify(WidgetUsage widget) {
    switch (widget.type) {
      case 'Text':
        return _classifyText(widget);
      case 'MediaQuery':
        return _classifyMediaQuery(widget);
      default:
        return null;
    }
  }

  _ScaleVerdict _classifyText(WidgetUsage widget) {
    final tsf = widget.arg('textScaleFactor');
    if (tsf != null) {
      if (tsf is IntegerLiteral || tsf is DoubleLiteral) {
        return _ScaleVerdict.fail;
      }
      if (tsf is NullLiteral) {
        return _ScaleVerdict.pass;
      }
      return _ScaleVerdict.indeterminate;
    }

    final scaler = widget.arg('textScaler');
    if (scaler != null) {
      return _classifyTextScalerExpr(scaler);
    }
    return _ScaleVerdict.pass;
  }

  _ScaleVerdict _classifyMediaQuery(WidgetUsage widget) {
    final tsf = widget.arg('textScaleFactor');
    if (tsf != null) {
      if (tsf is IntegerLiteral || tsf is DoubleLiteral) {
        return _ScaleVerdict.fail;
      }
      if (tsf is NullLiteral) {
        return _ScaleVerdict.pass;
      }
      return _ScaleVerdict.indeterminate;
    }
    return _ScaleVerdict.pass;
  }

  _ScaleVerdict _classifyTextScalerExpr(Expression expr) {
    if (expr is PropertyAccess) {
      final prop = expr.propertyName.name;
      if (prop == 'noScaling') {
        return _ScaleVerdict.fail;
      }
    }
    if (expr is PrefixedIdentifier && expr.identifier.name == 'noScaling') {
      return _ScaleVerdict.fail;
    }

    if (expr is MethodInvocation && expr.methodName.name == 'linear') {
      final args = expr.argumentList.arguments;
      if (args.isNotEmpty) {
        final first = args.first;
        if (first is DoubleLiteral || first is IntegerLiteral) {
          return _ScaleVerdict.fail;
        }
        return _ScaleVerdict.indeterminate;
      }
    }

    if (expr is SimpleIdentifier || expr is MethodInvocation) {
      return _ScaleVerdict.indeterminate;
    }

    return _ScaleVerdict.indeterminate;
  }

  String _failMessage(WidgetUsage widget) {
    if (widget.type == 'MediaQuery') {
      return 'MediaQuery overrides textScaleFactor with a fixed literal — '
          'all Text descendants will ignore system font-size preferences '
          '(WCAG 1.4.4).';
    }
    final tsf = widget.arg('textScaleFactor');
    if (tsf != null) {
      return 'Text has a hardcoded textScaleFactor — users cannot resize '
          'this text using system font-size preferences (WCAG 1.4.4). '
          'Remove textScaleFactor or set it to null.';
    }
    return 'Text uses TextScaler.noScaling or a fixed TextScaler.linear — '
        'users cannot resize this text using system font-size preferences '
        '(WCAG 1.4.4). Use TextScaler.linear with a variable or '
        'clamp with a max >= 2.0.';
  }
}

enum _ScaleVerdict { pass, fail, indeterminate }
