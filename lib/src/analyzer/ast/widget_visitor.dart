import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';

/// A single widget construction extracted from the AST.
///
/// Carries enough context for any [RuleDetector] to make a confident
/// judgement: the widget type, its named arguments, source location, and
/// the chain of ancestor widget types (outermost first) so a detector can
/// ask "is this widget wrapped in `Semantics`?" without re-walking the tree.
class WidgetUsage {
  /// Constructor name as written in source (e.g. `IconButton`, `Semantics`).
  final String type;

  /// Named arguments passed to the constructor. The value is the raw AST
  /// expression node so detectors can inspect literals, identifiers,
  /// member access (`Colors.blue`), method calls, etc.
  final Map<String, Expression> namedArgs;

  /// Positional arguments in source order.
  final List<Expression> positionalArgs;

  /// Ancestor widget types, outermost first. `ancestors.last` is the direct
  /// parent widget construction (if any). Non-widget intermediate AST nodes
  /// are skipped.
  final List<String> ancestors;

  /// 1-based line number where the constructor starts.
  final int line;

  /// 1-based column number where the constructor starts.
  final int column;

  /// Character offset in the source file.
  final int offset;

  /// Reference to the original AST node (either an
  /// [InstanceCreationExpression] or a [MethodInvocation]), in case a
  /// detector needs deeper inspection beyond what is pre-extracted.
  final AstNode node;

  WidgetUsage({
    required this.type,
    required this.namedArgs,
    required this.positionalArgs,
    required this.ancestors,
    required this.line,
    required this.column,
    required this.offset,
    required this.node,
  });

  /// True if any ancestor widget has the given [type].
  bool hasAncestor(String type) => ancestors.contains(type);

  /// True if any ancestor widget type matches any of [types].
  bool hasAnyAncestor(Iterable<String> types) {
    for (final a in ancestors) {
      if (types.contains(a)) return true;
    }
    return false;
  }

  /// Returns the named argument [name] if present, else `null`.
  Expression? arg(String name) => namedArgs[name];

  @override
  String toString() => '$type@$line:$column';
}

/// Result of parsing a single Dart file.
class ParsedFile {
  final String path;
  final List<WidgetUsage> widgets;
  final bool hasErrors;

  ParsedFile({
    required this.path,
    required this.widgets,
    required this.hasErrors,
  });
}

/// Parses a Dart source file and returns every widget construction found.
///
/// Uses `package:analyzer`'s [parseString] (purely syntactic, no type
/// resolution) which is fast and does not require a resolved package
/// context. This is enough for the detectors we run: they classify by
/// constructor name and inspect literal arguments.
///
/// Parse errors are swallowed (the file is still returned with whatever
/// widgets parsed successfully) so a single malformed file does not halt
/// a whole-project analysis.
ParsedFile parseDartFile(String path, String source) {
  final result = parseString(
    content: source,
    throwIfDiagnostics: false,
    featureSet: FeatureSet.latestLanguageVersion(),
  );
  final visitor = _WidgetVisitor(result.lineInfo);
  result.unit.visitChildren(visitor);
  return ParsedFile(
    path: path,
    widgets: visitor.widgets,
    hasErrors: result.errors.isNotEmpty,
  );
}

class _WidgetVisitor extends RecursiveAstVisitor<void> {
  final LineInfo _lineInfo;
  final List<WidgetUsage> widgets = [];
  final List<String> _ancestorStack = [];

  _WidgetVisitor(this._lineInfo);

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final typeName = node.constructorName.type.name2.lexeme;
    _record(
      typeName: typeName,
      arguments: node.argumentList.arguments,
      offset: node.offset,
      node: node,
      descend: () => super.visitInstanceCreationExpression(node),
    );
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final name = node.methodName.name;
    final isConstructorLike =
        node.realTarget == null && name.isNotEmpty && _startsUppercase(name);

    if (isConstructorLike) {
      _record(
        typeName: name,
        arguments: node.argumentList.arguments,
        offset: node.offset,
        node: node,
        descend: () => super.visitMethodInvocation(node),
      );
    } else {
      super.visitMethodInvocation(node);
    }
  }

  void _record({
    required String typeName,
    required List<Expression> arguments,
    required int offset,
    required AstNode node,
    required void Function() descend,
  }) {
    final namedArgs = <String, Expression>{};
    final positionalArgs = <Expression>[];
    for (final arg in arguments) {
      if (arg is NamedExpression) {
        namedArgs[arg.name.label.name] = arg.expression;
      } else {
        positionalArgs.add(arg);
      }
    }

    final location = _lineInfo.getLocation(offset);

    widgets.add(WidgetUsage(
      type: typeName,
      namedArgs: namedArgs,
      positionalArgs: positionalArgs,
      ancestors: List.unmodifiable(_ancestorStack),
      line: location.lineNumber,
      column: location.columnNumber,
      offset: offset,
      node: node,
    ));

    _ancestorStack.add(typeName);
    try {
      descend();
    } finally {
      _ancestorStack.removeLast();
    }
  }

  static bool _startsUppercase(String s) {
    final c = s.codeUnitAt(0);
    return c >= 0x41 && c <= 0x5A; // 'A'..'Z'
  }
}
