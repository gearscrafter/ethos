import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';

import '../../../models/coverage_report.dart';
import '../../../models/ethos_config.dart';
import '../../../models/spec.dart';
import '../../ast/widget_visitor.dart';
import '../../rule_detector.dart';
import '../deep_detector.dart';
import '../resolved_file.dart';

/// Deep version of [SemanticLabelsDetector] that follows widget definitions
/// across files.
///
/// ## What this adds over the standard detector
///
/// The standard detector only sees `Semantics` that are syntactically present
/// in the same `build()` method as the interactive widget.
///
/// This detector uses the [ProjectIndex] to:
///
/// 1. **Follow custom widget definitions.** When it sees `CircleIconBtn(...)`,
///    it looks up `CircleIconBtn` in the index, finds its `build()` method,
///    and checks whether that build method contains a `Semantics` widget.
///    If yes — PASS, no alias needed.
///
/// 2. **Detect cross-method `Semantics`.** When a `Semantics` wrapper and a
///    `GestureDetector` are in different methods of the same class (the
///    Wonderous `_FullscreenUrlImgViewer` pattern), the index can connect
///    them via the class-level widget tree.
class CrossFileSemanticLabelsDetector implements DeepDetector {
  final ProjectIndex index;

  CrossFileSemanticLabelsDetector({required this.index});

  @override
  String get ruleId => 'wcag_1_3_1_semantics_label';

  static const _customInteractive = {
    'GestureDetector',
    'InkWell',
    'InkResponse',
  };

  static const _tapGestures = {
    'onTap',
    'onTapDown',
    'onTapUp',
    'onDoubleTap',
    'onLongPress',
    'onSecondaryTap',
  };

  @override
  DetectionResult analyzeDeep({
    required Rule rule,
    required List<ResolvedFile> files,
    required ProjectIndex index,
    Map<String, WidgetAlias> aliases = const {},
    Map<String, ColorAlias> colorAliases = const {},
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
          final labelExpr = widget.arg(alias.labelArg!);
          if (_isNonEmptyLiteral(labelExpr)) {
            matched++;
          } else if (_isRuntimeValue(labelExpr)) {
            total--;
            indeterminate++;
          } else {
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
          final element = index.elementFor(widget.type);
          if (element != null && _isWidget(element)) {
            final defFile = index.fileByClassName[widget.type];
            if (defFile != null) {
              total++;
              if (_classHasInternalSemantics(widget.type, defFile)) {
                matched++;
              } else {
                indeterminate++;
                total--;
              }
            }
          }
          continue;
        }

        if (_hasExcludeFromSemantics(widget)) {
          continue;
        }
        if (widget.type == 'GestureDetector') {
          if (!_hasTapGesture(widget)) {
            continue;
          }
          if (_isNonInteractiveTap(widget)) {
            continue;
          }
        }

        total++;

        if (_hasSyntacticSemantics(widget)) {
          matched++;
          continue;
        }

        if (_hasCrossMethodSemantics(widget, file, index)) {
          matched++;
          continue;
        }

        findings.add(Finding(
          filePath: file.path,
          line: widget.line,
          column: widget.column,
          widgetType: widget.type,
          message: '${widget.type} has no Semantics(label: ...) ancestor '
              '— screen readers will not announce it.',
        ));
      }
    }

    return DetectionResult(
      matched: matched,
      total: total,
      indeterminate: indeterminate,
      findings: findings,
    );
  }

  bool _classHasInternalSemantics(String className, ResolvedFile defFile) {
    for (final widget in defFile.widgets) {
      if (widget.type == 'Semantics') {
        final labelArg = widget.arg('label');
        if (labelArg != null) {
          return true;
        }
      }
    }
    return false;
  }

  /// Checks whether a `Semantics` wrapper is present in another `build()`
  /// method of the same class as [widget] — the Wonderous cross-method pattern.
  bool _hasCrossMethodSemantics(
    WidgetUsage widget,
    ResolvedFile file,
    ProjectIndex index,
  ) {
    if (file.hasErrors) {
      return false;
    }
    final fileUsages = index.filesByPath[file.path];
    if (fileUsages == null) {
      return false;
    }
    for (final usage in fileUsages.widgets) {
      if (usage.type == 'Semantics' && usage.arg('label') != null) {
        final offsetDiff = (usage.offset - widget.offset).abs();
        if (offsetDiff < 5000) {
          return true;
        }
      }
    }
    return false;
  }

  bool _hasSyntacticSemantics(WidgetUsage widget) {
    if (widget.hasAncestor('Semantics')) {
      return _findEnclosingSemanticsHasLabel(widget.node);
    }
    return _findDescendantSemanticsHasLabel(widget.node);
  }

  bool _findEnclosingSemanticsHasLabel(AstNode node) {
    AstNode? current = node.parent;
    while (current != null) {
      if (_ctorNameOf(current) == 'Semantics') {
        return _semanticsHasLabel(current);
      }
      current = current.parent;
    }
    return false;
  }

  bool _findDescendantSemanticsHasLabel(AstNode node) {
    final finder = _SemanticsFinder();
    node.visitChildren(finder);
    return finder.found;
  }

  bool _semanticsHasLabel(AstNode node) {
    final args = _argsOf(node);
    if (args == null) {
      return false;
    }
    for (final arg in args) {
      if (arg is NamedExpression && arg.name.label.name == 'label') {
        return _isNonEmptyLiteral(arg.expression);
      }
    }
    return false;
  }

  bool _isWidget(ClassElement element) {
    final name = element.displayName;
    return name.isNotEmpty &&
        name[0].toUpperCase() == name[0] &&
        !name.endsWith('Data') &&
        !name.endsWith('Model') &&
        !name.endsWith('State');
  }

  bool _hasExcludeFromSemantics(WidgetUsage widget) {
    final arg = widget.arg('excludeFromSemantics');
    return arg is BooleanLiteral && arg.value == true;
  }

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
      if (body is ExpressionFunctionBody &&
          onTap.toString().contains('unfocus')) {
        return true;
      }
    }
    if (onTap.toString().contains('unfocus')) {
      return true;
    }
    return false;
  }

  bool _isNonEmptyLiteral(Expression? expr) {
    if (expr == null) {
      return false;
    }
    if (expr is StringLiteral) {
      final v = expr.stringValue;
      return v != null && v.trim().isNotEmpty;
    }
    return false;
  }

  bool _isRuntimeValue(Expression? expr) {
    if (expr == null) {
      return false;
    }
    if (expr is StringLiteral) {
      return expr.stringValue == null;
    }
    return true;
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

  NodeList<Expression>? _argsOf(AstNode node) {
    if (node is InstanceCreationExpression) {
      return node.argumentList.arguments;
    }
    if (node is MethodInvocation) {
      return node.argumentList.arguments;
    }
    return null;
  }
}

class _SemanticsFinder extends RecursiveAstVisitor<void> {
  bool found = false;

  void _check(AstNode node, void Function() descend) {
    if (found) {
      return;
    }
    final name = _nameOf(node);
    if (name == 'Semantics') {
      found = _hasLabel(node);
      if (found) {
        return;
      }
    }
    descend();
  }

  bool _hasLabel(AstNode node) {
    final args = node is InstanceCreationExpression
        ? node.argumentList.arguments
        : node is MethodInvocation
            ? node.argumentList.arguments
            : null;
    if (args == null) {
      return false;
    }
    for (final arg in args) {
      if (arg is NamedExpression && arg.name.label.name == 'label') {
        return true;
      }
    }
    return false;
  }

  String? _nameOf(AstNode node) {
    if (node is InstanceCreationExpression) {
      var s = node.constructorName.type.toSource().trim();
      final i = s.lastIndexOf('.');
      return i != -1 ? s.substring(i + 1) : s;
    }
    if (node is MethodInvocation && node.realTarget == null) {
      return node.methodName.name;
    }
    return null;
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) =>
      _check(node, () => super.visitInstanceCreationExpression(node));

  @override
  void visitMethodInvocation(MethodInvocation node) =>
      _check(node, () => super.visitMethodInvocation(node));
}
