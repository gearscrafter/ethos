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

  bool _isNonEmptyLiteral(Expression expr) {
    if (expr is StringLiteral) {
      final v = expr.stringValue;
      return v != null && v.trim().isNotEmpty;
    }
    return false;
  }

  bool _isEmptyLiteral(Expression expr) {
    if (expr is StringLiteral) {
      final v = expr.stringValue;
      return v != null && v.trim().isEmpty;
    }
    return false;
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
    NodeList<Expression>? args;
    if (node is InstanceCreationExpression) {
      args = node.argumentList.arguments;
    }
    if (node is MethodInvocation) {
      args = node.argumentList.arguments;
    }
    if (args == null) {
      return null;
    }
    for (final arg in args) {
      if (arg is NamedExpression && arg.name.label.name == name) {
        return arg.expression;
      }
    }
    return null;
  }
}

enum _LabelState { literalNonEmpty, indeterminate, missing, empty }
