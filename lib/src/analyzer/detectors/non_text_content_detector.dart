import 'package:analyzer/dart/ast/ast.dart';

import '../../models/ethos_config.dart';
import '../../models/spec.dart';
import '../../models/coverage_report.dart';
import '../ast/widget_visitor.dart';
import '../rule_detector.dart';

/// Detects WCAG 1.1.1 — Non-text Content.
///
/// All image and icon widgets that convey information must have a text
/// alternative accessible to assistive technologies. Purely decorative
/// content must be explicitly excluded from the semantic tree.
///
/// ## In scope
///
/// - `Image`, `Image.asset`, `Image.network`, `Image.file`, `Image.memory`
/// - `SvgPicture.asset`, `SvgPicture.network`, `SvgPicture.file`
/// - `Icon`
///
/// ## Outcomes
///
/// - **Pass:** widget is wrapped in `Semantics(label: '<non-empty>')`,
///   has `excludeFromSemantics: true` (decorative), or for `Icon` has
///   a non-empty literal `semanticLabel:` argument.
/// - **Indeterminate:** label is a runtime variable or interpolation.
/// - **Fail:** no semantic label and no explicit decoration marker.
class NonTextContentDetector implements RuleDetector {
  static const _imageWidgets = {
    'Image',
    'SvgPicture',
    'NetworkImage',
    'AssetImage',
  };

  static const _imageConstructors = {
    'Image',
    'SvgPicture',
  };

  @override
  String get ruleId => 'wcag_1_1_1_non_text_content';

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
        final isImage = _imageWidgets.contains(widget.type) ||
            _imageConstructors.contains(widget.type);
        final isIcon = widget.type == 'Icon';

        if (!isImage && !isIcon) {
          continue;
        }

        if (isIcon) {
          total++;
          final label = widget.arg('semanticLabel');
          if (label == null) {
            findings.add(Finding(
              filePath: file.path,
              line: widget.line,
              column: widget.column,
              widgetType: 'Icon',
              message: 'Icon has no semanticLabel — screen readers will '
                  'announce the icon data value instead of a meaningful name.',
            ));
          } else if (_isNonEmptyLiteral(label)) {
            matched++;
          } else if (_isEmptyLiteral(label)) {
            findings.add(Finding(
              filePath: file.path,
              line: widget.line,
              column: widget.column,
              widgetType: 'Icon',
              message: 'Icon has an empty semanticLabel.',
            ));
          } else {
            total--;
            indeterminate++;
          }
          continue;
        }

        total++;

        if (_hasExcludeFromSemantics(widget)) {
          matched++;
          continue;
        }

        final semanticsState = _resolveSemantics(widget);
        switch (semanticsState) {
          case _LabelState.literalNonEmpty:
            matched++;
          case _LabelState.indeterminate:
            total--;
            indeterminate++;
          case _LabelState.missing:
          case _LabelState.empty:
            findings.add(Finding(
              filePath: file.path,
              line: widget.line,
              column: widget.column,
              widgetType: widget.type,
              message: '${widget.type} has no accessible text alternative. '
                  'Wrap it in Semantics(label: \'...\') or add '
                  'excludeFromSemantics: true if it is decorative '
                  '(WCAG 1.1.1).',
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

  _LabelState _resolveSemantics(WidgetUsage widget) {
    AstNode? current = widget.node.parent;
    while (current != null) {
      if (_ctorNameOf(current) == 'Semantics') {
        final labelArg = _namedArg(current, 'label');
        if (labelArg == null) {
          current = current.parent;
          continue;
        }
        if (_isNonEmptyLiteral(labelArg)) {
          return _LabelState.literalNonEmpty;
        }
        if (_isEmptyLiteral(labelArg)) {
          return _LabelState.empty;
        }
        return _LabelState.indeterminate;
      }
      final name = _ctorNameOf(current);
      if (name != null && _imageWidgets.contains(name)) {
        break;
      }
      current = current.parent;
    }
    return _LabelState.missing;
  }

  _LabelState _classifyLabelExpr(Expression? expr) {
    if (expr == null) {
      return _LabelState.missing;
    }

    if (expr is StringLiteral) {
      final v = expr.stringValue;
      if (v == null) {
        return _LabelState.indeterminate;
      }
      return v.trim().isEmpty ? _LabelState.empty : _LabelState.literalNonEmpty;
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
      final t = _classifyLabelExpr(expr.thenExpression);
      final e = _classifyLabelExpr(expr.elseExpression);
      if (t == _LabelState.empty || e == _LabelState.empty) {
        return _LabelState.empty;
      }
      if (t == _LabelState.literalNonEmpty &&
          e == _LabelState.literalNonEmpty) {
        return _LabelState.literalNonEmpty;
      }
    }

    if (expr is SimpleIdentifier && _looksLikeConstant(expr.name)) {
      return _LabelState.literalNonEmpty;
    }

    if (expr is PrefixedIdentifier) {
      if (_looksLikeStringsClass(expr.prefix.name) ||
          _looksLikeConstant(expr.identifier.name)) {
        return _LabelState.literalNonEmpty;
      }
    }

    return _LabelState.indeterminate;
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
    return name.endsWith('Label') ||
        name.endsWith('Text') ||
        name.endsWith('Title') ||
        name.endsWith('String') ||
        name.endsWith('Semantic');
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

  bool _isNonEmptyLiteral(Expression expr) {
    return _classifyLabelExpr(expr) == _LabelState.literalNonEmpty;
  }

  bool _isEmptyLiteral(Expression expr) {
    final state = _classifyLabelExpr(expr);
    return state == _LabelState.empty;
  }

  String? _ctorNameOf(AstNode node) {
    if (node is InstanceCreationExpression) {
      var s = node.constructorName.type.toSource().trim();
      final gi = s.indexOf('<');
      if (gi != -1) {
        s = s.substring(0, gi);
      }
      final di = s.lastIndexOf('.');
      if (di != -1) {
        s = s.substring(di + 1);
      }
      return s.isEmpty ? null : s;
    }
    if (node is MethodInvocation && node.realTarget == null) {
      return node.methodName.name;
    }
    return null;
  }

  Expression? _namedArg(AstNode node, String name) {
    dynamic args;
    if (node is InstanceCreationExpression) {
      args = node.argumentList.arguments;
    }
    if (node is MethodInvocation) {
      args = node.argumentList.arguments;
    }
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
