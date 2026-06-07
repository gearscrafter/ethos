import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../../models/spec.dart';
import '../../models/ethos_config.dart';
import '../../models/coverage_report.dart';
import '../ast/widget_visitor.dart';
import '../rule_detector.dart';

/// Detects WCAG 1.3.1 — Semantic Labels on Interactive Widgets.
///
/// ## Scope (what counts toward the denominator)
///
/// A custom interactive widget (`GestureDetector`, `InkWell`, `InkResponse`)
/// that behaves as a discrete control. Specifically EXCLUDED:
///
class SemanticLabelsDetector implements RuleDetector {
  static const _customInteractive = {
    'GestureDetector',
    'InkWell',
    'InkResponse',
  };

  @override
  String get ruleId => 'wcag_1_3_1_semantics_label';

  @override
  DetectionResult analyze({
    required Rule rule,
    required List<ParsedFile> files,
    Map<String, WidgetAlias> aliases = const {},
    Map<String, ColorAlias> colorAliases = const {}, // ← added
  }) {
    int matched = 0;
    int total = 0;
    int indeterminate = 0;
    final findings = <Finding>[];

    for (final file in files) {
      for (final widget in file.widgets) {
        final alias = aliases[widget.type];
        if (alias != null && alias.role == WidgetRole.button) {
          if (alias.labelArg == null) {
            indeterminate++;
            continue;
          }
          total++;
          final labelValue = widget.arg(alias.labelArg!);
          final state = _classifyExpression(labelValue);
          switch (state) {
            case _LabelState.literalNonEmpty:
              matched++;
            case _LabelState.indeterminate:
              total--;
              indeterminate++;
            case _LabelState.empty:
            case _LabelState.missing:
              findings.add(Finding(
                filePath: file.path,
                line: widget.line,
                column: widget.column,
                widgetType: widget.type,
                message: '${widget.type} has no non-empty "${alias.labelArg}" '
                    '(declared as a button in ethos.yaml widget_aliases).',
              ));
          }
          continue;
        }

        if (!_customInteractive.contains(widget.type)) {
          continue;
        }
        if (_hasExcludeFromSemantics(widget)) {
          continue;
        }
        if (widget.type == 'GestureDetector' && !_hasTapGesture(widget)) {
          continue;
        }
        if (widget.type == 'GestureDetector' && _isNonInteractiveTap(widget)) {
          continue;
        }

        total++;

        final labelState = _resolveLabel(widget);
        switch (labelState) {
          case _LabelState.literalNonEmpty:
            matched++;
          case _LabelState.indeterminate:
            indeterminate++;
            total--;
            findings.add(Finding(
              filePath: file.path,
              line: widget.line,
              column: widget.column,
              widgetType: widget.type,
              message: 'Wrapped in Semantics, but label is not a literal '
                  '(resolved at runtime). Cannot verify it is non-empty.',
              severity: FindingSeverity.indeterminate,
            ));
          case _LabelState.missing:
            findings.add(Finding(
              filePath: file.path,
              line: widget.line,
              column: widget.column,
              widgetType: widget.type,
              message: '${widget.type} has no Semantics(label: ...) ancestor — '
                  'screen readers will not announce it.',
            ));
          case _LabelState.empty:
            findings.add(Finding(
              filePath: file.path,
              line: widget.line,
              column: widget.column,
              widgetType: widget.type,
              message: 'Wrapped in Semantics, but label is an empty string.',
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

  bool _hasExcludeFromSemantics(WidgetUsage widget) {
    final arg = widget.arg('excludeFromSemantics');
    return arg is BooleanLiteral && arg.value == true;
  }

  static const _tapGestures = {
    'onTap',
    'onTapDown',
    'onTapUp',
    'onDoubleTap',
    'onLongPress',
    'onSecondaryTap',
  };

  bool _hasTapGesture(WidgetUsage widget) {
    for (final g in _tapGestures) {
      if (widget.namedArgs.containsKey(g)) {
        return true;
      }
    }
    return false;
  }

  bool _isNonInteractiveTap(WidgetUsage widget) {
    final onTap = widget.arg('onTap');
    if (onTap == null) {
      return false;
    }
    if (onTap is FunctionExpression) {
      final body = onTap.body;
      if (body is BlockFunctionBody && body.block.statements.isEmpty) {
        return true;
      }
      if (body is ExpressionFunctionBody && _mentionsUnfocus(body.expression)) {
        return true;
      }
    }
    if (_mentionsUnfocus(onTap)) return true;
    return false;
  }

  bool _mentionsUnfocus(Expression expr) => expr.toString().contains('unfocus');

  _LabelState _resolveLabel(WidgetUsage widget) {
    final ancestor = _findEnclosingSemantics(widget.node);
    if (ancestor != null) {
      final state = _labelStateOf(ancestor);
      if (state != _LabelState.missing) return state;
    }
    final descendant = _findDescendantSemantics(widget.node);
    if (descendant != null) {
      final state = _labelStateOf(descendant);
      if (state != _LabelState.missing) return state;
    }
    return _LabelState.missing;
  }

  _LabelState _labelStateOf(AstNode semanticsNode) {
    return _classifyExpression(_namedArg(semanticsNode, 'label'));
  }

  _LabelState _classifyExpression(Expression? expr) {
    if (expr == null) return _LabelState.missing;
    if (expr is StringLiteral) {
      final value = expr.stringValue;
      if (value == null) return _LabelState.indeterminate; // interpolated
      return value.trim().isEmpty
          ? _LabelState.empty
          : _LabelState.literalNonEmpty;
    }

    if (expr is NullLiteral) {
      return _LabelState.missing;
    }

    if (expr is BinaryExpression && expr.operator.lexeme == '??') {
      final right = expr.rightOperand;
      if (right is StringLiteral) {
        final fallback = right.stringValue ?? '';
        return fallback.trim().isEmpty
            ? _LabelState.empty
            : _LabelState.literalNonEmpty;
      }
    }

    if (expr is ConditionalExpression) {
      final thenState = _classifyExpression(expr.thenExpression);
      final elseState = _classifyExpression(expr.elseExpression);
      if (thenState == _LabelState.empty || elseState == _LabelState.empty) {
        return _LabelState.empty;
      }
      if (thenState == _LabelState.missing ||
          elseState == _LabelState.missing) {
        return _LabelState.empty;
      }
      if (thenState == _LabelState.literalNonEmpty &&
          elseState == _LabelState.literalNonEmpty) {
        return _LabelState.literalNonEmpty;
      }
    }

    if (expr is SimpleIdentifier) {
      final name = expr.name;
      if (_looksLikeConstant(name)) {
        return _LabelState.literalNonEmpty;
      }
    }

    if (expr is PrefixedIdentifier) {
      final prefix = expr.prefix.name;
      final id = expr.identifier.name;
      if (_looksLikeStringsClass(prefix) || _looksLikeConstant(id)) {
        return _LabelState.literalNonEmpty;
      }
    }

    return _LabelState.indeterminate; // variable / method call / etc.
  }

  static bool _looksLikeConstant(String name) {
    if (name.isEmpty) {
      return false;
    }
    if (name.startsWith('k') &&
        name.length > 1 &&
        name[1] == name[1].toUpperCase()) {
      return true;
    }
    if (name == name.toUpperCase() && name.contains('_')) {
      return true;
    }
    if (name.endsWith('Label') ||
        name.endsWith('Text') ||
        name.endsWith('Title') ||
        name.endsWith('String') ||
        name.endsWith('Semantic')) {
      return true;
    }
    return false;
  }

  static bool _looksLikeStringsClass(String name) {
    final lower = name.toLowerCase();
    return lower == 'strings' ||
        lower == '\$strings' ||
        lower == 's' ||
        lower == 'l10n' ||
        lower == '\$l10n' ||
        lower.contains('string') ||
        lower.contains('local') ||
        lower.contains('intl') ||
        lower.startsWith('\$');
  }

  AstNode? _findEnclosingSemantics(AstNode node) {
    AstNode? current = node.parent;
    while (current != null) {
      if (_constructorNameOf(current) == 'Semantics') return current;
      current = current.parent;
    }
    return null;
  }

  AstNode? _findDescendantSemantics(AstNode node) {
    final finder = _DescendantSemanticsFinder(
      stopTypes: _customInteractive,
      rootNode: node,
      nameOf: _constructorNameOf,
    );
    node.visitChildren(finder);
    return finder.found;
  }

  String? _constructorNameOf(AstNode node) {
    if (node is InstanceCreationExpression) {
      var source = node.constructorName.type.toSource().trim();
      final genericIdx = source.indexOf('<');
      if (genericIdx != -1) {
        source = source.substring(0, genericIdx);
      }
      final dotIdx = source.lastIndexOf('.');
      if (dotIdx != -1) {
        source = source.substring(dotIdx + 1);
      }
      return source.isEmpty ? null : source;
    }
    if (node is MethodInvocation && node.realTarget == null) {
      return node.methodName.name;
    }
    return null;
  }

  Expression? _namedArg(AstNode node, String name) {
    final args = _argumentsOf(node);
    if (args == null) {
      return null;
    }
    for (final arg in args as Iterable) {
      try {
        if (_argNameMatches(arg, name)) {
          return _extractExpr(arg);
        }
      } catch (_) {}
    }
    return null;
  }

  static Expression? _extractExpr(dynamic arg) {
    try {
      final e = arg.argumentExpression;
      if (e is Expression) {
        return e;
      }
    } catch (_) {}
    try {
      return arg.expression as Expression?;
    } catch (_) {
      return null;
    }
  }

  dynamic _argumentsOf(AstNode node) {
    if (node is InstanceCreationExpression) {
      return node.argumentList.arguments;
    }
    if (node is MethodInvocation) {
      return node.argumentList.arguments;
    }
    return null;
  }
}

bool _argNameMatches(dynamic arg, String name) {
  try {
    final s = arg.name?.toString();
    if (s == name) {
      return true;
    }
  } catch (_) {}
  try {
    if (arg.name?.label?.name == name) {
      return true;
    }
  } catch (_) {}
  return false;
}

enum _LabelState { literalNonEmpty, indeterminate, missing, empty }

class _DescendantSemanticsFinder extends RecursiveAstVisitor<void> {
  final Set<String> stopTypes;
  final AstNode rootNode;
  final String? Function(AstNode) nameOf;
  AstNode? found;

  _DescendantSemanticsFinder({
    required this.stopTypes,
    required this.rootNode,
    required this.nameOf,
  });

  void _check(AstNode node, void Function() descend) {
    if (found != null) return;
    final name = nameOf(node);
    if (name == 'Semantics') {
      found = node;
      return;
    }
    if (node != rootNode && name != null && stopTypes.contains(name)) return;
    descend();
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) =>
      _check(node, () => super.visitInstanceCreationExpression(node));

  @override
  void visitMethodInvocation(MethodInvocation node) =>
      _check(node, () => super.visitMethodInvocation(node));
}
