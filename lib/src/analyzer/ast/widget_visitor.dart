import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

/// A single widget construction extracted from the AST.
class WidgetUsage {
  /// Constructor name as written in source (e.g. `IconButton`, `Semantics`).
  final String type;

  /// Named arguments passed to the constructor.
  final Map<String, Expression> namedArgs;

  /// Positional arguments in source order.
  final List<Expression> positionalArgs;

  /// Ancestor widget types, outermost first.
  final List<String> ancestors;

  /// 1-based line number where the constructor starts.
  final int line;

  /// 1-based column number where the constructor starts.
  final int column;

  /// Character offset in the source file.
  final int offset;

  /// Reference to the original AST node.
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
  /// Absolute or relative path to the source file.
  final String path;

  /// Every widget construction found in the file.
  final List<WidgetUsage> widgets;

  /// True if the file had parse errors (widgets may still be partially found).
  final bool hasErrors;

  ParsedFile({
    required this.path,
    required this.widgets,
    required this.hasErrors,
  });
}

/// Parses a Dart source file and returns every widget construction found.
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
  final dynamic _lineInfo;
  final List<WidgetUsage> widgets = [];
  final List<String> _ancestorStack = [];

  _WidgetVisitor(this._lineInfo);

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final typeName = _typeNameOf(node.constructorName);
    if (typeName == null) {
      super.visitInstanceCreationExpression(node);
      return;
    }
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

  static String? _typeNameOf(ConstructorName constructorName) {
    var source = constructorName.type.toSource().trim();

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

  static bool _startsUppercase(String s) {
    if (s.isEmpty) return false;
    final c = s.codeUnitAt(0);
    return c >= 0x41 && c <= 0x5A; // 'A'..'Z'
  }
}
