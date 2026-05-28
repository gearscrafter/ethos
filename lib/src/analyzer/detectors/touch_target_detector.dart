import 'package:analyzer/dart/ast/ast.dart';

import '../../models/spec.dart';
import '../../models/coverage_report.dart';
import '../ast/widget_visitor.dart';
import '../rule_detector.dart';

/// Detects WCAG 2.5.5 — Touch Target Size (Enhanced): interactive elements
/// should be at least 48x48 logical pixels (Material Design guideline).
///
/// ## Strategy
///
/// Touch-target size, like contrast, is rarely declared on the interactive
/// widget itself. So we measure what is verifiable:
///
/// 1. **Material widgets with guaranteed minimums** (`IconButton`,
///    `FloatingActionButton`) → automatic PASS. Flutter enforces 48x48 for
///    these regardless of content.
///
/// 2. **Custom interactive widgets** (`GestureDetector`, `InkWell`,
///    `InkResponse`) sized by an enclosing `SizedBox(width:, height:)` or a
///    `Container` with literal `width`/`height` → PASS if both >= 48, FAIL
///    otherwise.
///
/// 3. Everything else (size from a variable, theme, intrinsic content, or
///    `constraints`) → **indeterminate**.
///
/// ## A note on tapTargetSize
///
/// A Material button with `tapTargetSize: MaterialTapTargetSize.shrinkWrap`
/// opts OUT of the 48x48 guarantee. When we see that literal on an
/// otherwise auto-pass widget, we downgrade it to indeterminate (its real
/// size now depends on content we can't measure).
class TouchTargetDetector implements RuleDetector {
  static const double _minSize = 48.0;

  static const _autoPass = {
    'IconButton',
    'FloatingActionButton',
  };

  /// Custom interactive widgets with no intrinsic minimum size.
  static const _customInteractive = {
    'GestureDetector',
    'InkWell',
    'InkResponse',
  };

  @override
  String get ruleId => 'wcag_2_5_5_target_size_enhanced';

  @override
  DetectionResult analyze({
    required Rule rule,
    required List<ParsedFile> files,
  }) {
    int matched = 0;
    int total = 0;
    int indeterminate = 0;
    final findings = <Finding>[];

    for (final file in files) {
      for (final widget in file.widgets) {
        if (_autoPass.contains(widget.type)) {
          if (_hasShrinkWrapTapTarget(widget)) {
            // Opted out of the 48x48 guarantee — size now depends on
            // content we can't measure.
            indeterminate++;
            continue;
          }
          total++;
          matched++;
          continue;
        }

        if (_customInteractive.contains(widget.type)) {
          final size = _resolveSize(widget);
          switch (size) {
            case _SizeVerdict.pass:
              total++;
              matched++;
            case _SizeVerdict.fail:
              total++;
              findings.add(Finding(
                filePath: file.path,
                line: widget.line,
                column: widget.column,
                widgetType: widget.type,
                message:
                    '${widget.type} touch target is smaller than '
                    '${_minSize.toStringAsFixed(0)}x${_minSize.toStringAsFixed(0)} '
                    'logical pixels (WCAG 2.5.5).',
              ));
            case _SizeVerdict.unknown:
              indeterminate++;
          }
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

  bool _hasShrinkWrapTapTarget(WidgetUsage widget) {
    final arg = widget.arg('tapTargetSize');
    if (arg == null) return false;
    return arg.toString().contains('shrinkWrap');
  }


  _SizeVerdict _resolveSize(WidgetUsage widget) {
    final ownW = _numArg(widget.arg('width'));
    final ownH = _numArg(widget.arg('height'));
    if (ownW != null && ownH != null) {
      return (ownW >= _minSize && ownH >= _minSize)
          ? _SizeVerdict.pass
          : _SizeVerdict.fail;
    }

    final sizer = _findEnclosingSizer(widget.node);
    if (sizer == null) return _SizeVerdict.unknown;

    final w = _numArg(_namedArg(sizer, 'width'));
    final h = _numArg(_namedArg(sizer, 'height'));
    if (w == null || h == null) return _SizeVerdict.unknown;

    return (w >= _minSize && h >= _minSize)
        ? _SizeVerdict.pass
        : _SizeVerdict.fail;
  }

  /// Walks up the AST for the nearest enclosing SizedBox or Container,
  AstNode? _findEnclosingSizer(AstNode node) {
    AstNode? current = node.parent;
    while (current != null) {
      final name = _ctorName(current);
      if (name == 'SizedBox' || name == 'Container') return current;
      if (name != null && _customInteractive.contains(name)) return null;
      current = current.parent;
    }
    return null;
  }

  double? _numArg(Expression? expr) {
    if (expr is DoubleLiteral) return expr.value;
    if (expr is IntegerLiteral) return expr.value?.toDouble();
    return null;
  }

  String? _ctorName(AstNode node) {
    if (node is InstanceCreationExpression) {
      return node.constructorName.type.name2.lexeme;
    }
    if (node is MethodInvocation && node.realTarget == null) {
      return node.methodName.name;
    }
    return null;
  }

  Expression? _namedArg(AstNode node, String name) {
    final args = _argsOf(node);
    if (args == null) return null;
    for (final arg in args) {
      if (arg is NamedExpression && arg.name.label.name == name) {
        return arg.expression;
      }
    }
    return null;
  }

  NodeList<Expression>? _argsOf(AstNode node) {
    if (node is InstanceCreationExpression) return node.argumentList.arguments;
    if (node is MethodInvocation) return node.argumentList.arguments;
    return null;
  }
}

enum _SizeVerdict { pass, fail, unknown }