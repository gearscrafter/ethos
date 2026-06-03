import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

/// A single widget construction extracted from the AST.
class WidgetUsage {
  final String type;
  final Map<String, Expression> namedArgs;
  final List<Expression> positionalArgs;
  final List<String> ancestors;
  final int line;
  final int column;
  final int offset;
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

  bool hasAncestor(String type) => ancestors.contains(type);
  bool hasAnyAncestor(Iterable<String> types) {
    for (final a in ancestors) {
      if (types.contains(a)) {
        return true;
      }
    }
    return false;
  }

  Expression? arg(String name) => namedArgs[name];

  @override
  String toString() => '$type@$line:$column';
}

/// Result of parsing a single Dart file.
class ParsedFile {
  final String path;
  final List<WidgetUsage> widgets;
  final bool hasErrors;

  ParsedFile(
      {required this.path, required this.widgets, required this.hasErrors});
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
    hasErrors: _hasErrors(result),
  );
}

bool _hasErrors(dynamic result) {
  try {
    return (result.diagnostics as List).isNotEmpty;
  } catch (_) {}
  try {
    return (result.errors as List).isNotEmpty;
  } catch (_) {}
  return false;
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
        arguments: node.argumentList.arguments as dynamic,
        offset: node.offset,
        node: node,
        descend: () => super.visitInstanceCreationExpression(node));
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final name = node.methodName.name;
    if (node.realTarget == null && name.isNotEmpty && _startsUppercase(name)) {
      _record(
          typeName: name,
          arguments: node.argumentList.arguments as dynamic,
          offset: node.offset,
          node: node,
          descend: () => super.visitMethodInvocation(node));
    } else if (node.realTarget is SimpleIdentifier) {
      final targetName = (node.realTarget as SimpleIdentifier).name;
      if (_startsUppercase(targetName)) {
        _record(
            typeName: targetName,
            arguments: node.argumentList.arguments as dynamic,
            offset: node.offset,
            node: node,
            descend: () => super.visitMethodInvocation(node));
      } else {
        super.visitMethodInvocation(node);
      }
    } else {
      super.visitMethodInvocation(node);
    }
  }

  void _record({
    required String typeName,
    required dynamic arguments,
    required int offset,
    required AstNode node,
    required void Function() descend,
  }) {
    final namedArgs = <String, Expression>{};
    final positionalArgs = <Expression>[];

    for (final arg in arguments as Iterable) {
      final name = _namedArgName(arg);
      final expr = _namedArgExpression(arg);
      if (name != null && expr != null) {
        namedArgs[name] = expr;
      } else if (arg is Expression) {
        positionalArgs.add(arg);
      } else {
        try {
          final e = (arg as dynamic).argumentExpression as Expression?;
          if (e != null) {
            positionalArgs.add(e);
          }
        } catch (_) {
          try {
            final e = (arg as dynamic).expression as Expression?;
            if (e != null) {
              positionalArgs.add(e);
            }
          } catch (_) {}
        }
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

  static String? _namedArgName(dynamic arg) {
    try {
      final nameNode = arg.name;
      if (nameNode == null) {
        return null;
      }

      try {
        final s = nameNode.toString();
        if (s.isNotEmpty &&
            !s.contains(' ') &&
            !s.contains('.') &&
            !s.contains(':')) {
          return s;
        }
      } catch (_) {}

      // analyzer 8.x: Token — .lexeme
      try {
        final lexeme = nameNode.lexeme;
        if (lexeme is String && lexeme.isNotEmpty) {
          return lexeme;
        }
      } catch (_) {}

      // analyzer 7.x: Label — arg.name.label.name
      try {
        final labelName = nameNode.label?.name;
        if (labelName is String && labelName.isNotEmpty) {
          return labelName;
        }
      } catch (_) {}

      return null;
    } catch (_) {
      return null;
    }
  }

  /// Extracts the value [Expression] from a named argument.
  static Expression? _namedArgExpression(dynamic arg) {
    try {
      final e = arg.argumentExpression;
      if (e is Expression) {
        return e;
      }
    } catch (_) {}
    try {
      final e = arg.expression;
      if (e is Expression) {
        return e;
      }
    } catch (_) {}
    try {
      final entities = (arg as dynamic).childEntities.toList();
      if (entities.isNotEmpty) {
        final last = entities.last;
        if (last is Expression) {
          return last;
        }
      }
    } catch (_) {}
    return null;
  }

  static String? _typeNameOf(ConstructorName constructorName) {
    var source = constructorName.type.toSource().trim();
    final gi = source.indexOf('<');
    if (gi != -1) {
      source = source.substring(0, gi);
    }
    final di = source.lastIndexOf('.');
    if (di != -1) {
      source = source.substring(di + 1);
    }
    return source.isEmpty ? null : source;
  }

  static bool _startsUppercase(String s) {
    if (s.isEmpty) {
      return false;
    }
    final c = s.codeUnitAt(0);
    return c >= 0x41 && c <= 0x5A;
  }
}
