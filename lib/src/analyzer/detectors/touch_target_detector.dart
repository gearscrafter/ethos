import 'package:analyzer/dart/ast/ast.dart';

import '../../models/spec.dart';
import '../../models/coverage_report.dart';
import '../ast/widget_visitor.dart';
import '../rule_detector.dart';

/// Detects WCAG 2.5.5 — Touch Target Size.
///
class TouchTargetDetector implements RuleDetector {
  static const double _minSize = 48.0;

  static const _autoPass = {
    'IconButton',
    'FloatingActionButton',
  };

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
    Map<String, WidgetAlias> aliases = const {}, // ← added
  }) {
    int matched = 0;
    int total = 0;
    int indeterminate = 0;
    final findings = <Finding>[];

    for (final file in files) {
      for (final widget in file.widgets) {

        final alias = aliases[widget.type];
        if (alias != null && alias.role == WidgetRole.button) {
          if (alias.sizeGuaranteed) {
            total++;
            matched++;
          } else {
            indeterminate++;
          }
          continue;
        }

        if (_autoPass.contains(widget.type)) {
          if (_hasShrinkWrapTapTarget(widget)) {
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
                    '${_minSize.toStringAsFixed(0)}x'
                    '${_minSize.toStringAsFixed(0)} '
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
    if (node is InstanceCreationExpression) return node.constructorName.type.name2.lexeme;
    if (node is MethodInvocation && node.realTarget == null) return node.methodName.name;
    return null;
  }

  Expression? _namedArg(AstNode node, String name) {
    final args = _argsOf(node);
    if (args == null) return null;
    for (final arg in args) {
      if (arg is NamedExpression && arg.name.label.name == name) return arg.expression;
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