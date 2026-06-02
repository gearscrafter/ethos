import 'package:analyzer/dart/ast/ast.dart';
import '../ast/widget_visitor.dart';

/// Extracts color information from `MaterialApp(theme: ThemeData(...))` and
/// `ThemeData(colorScheme: ColorScheme(...))` declarations found in a
/// project's Dart files.
///
/// This is **syntactic only** — no type resolution. It finds `ThemeData`
/// and `ColorScheme` constructor calls with inline literal color arguments
/// and builds lookup maps that [ContrastDetector] can use to resolve
/// `theme.textTheme.X` and `Theme.of(context).colorScheme.X` expressions.
///
/// ## What it resolves
///
/// - `ThemeData(textTheme: TextTheme(bodyLarge: TextStyle(color: Color(0xFF...))))`
///   → `{'bodyLarge': 0xFF...}`
/// - `ThemeData(colorScheme: ColorScheme(primary: Color(0xFF...)))`
///   → `{'primary': 0xFF...}`
/// - `ThemeData(scaffoldBackgroundColor: Color(0xFF...))`
///   → `{'scaffoldBackgroundColor': 0xFF...}`
///
/// ## What it does NOT resolve
///
/// - Colors stored in variables (`color: myColor`).
/// - `ThemeData.from(...)` factory constructors.
/// - Dynamic / computed colors.
/// These remain indeterminate in the contrast report.
class ThemeExtractor {
  static Map<String, int> extractFromFiles(List<ParsedFile> files) {
    final result = <String, int>{};
    for (final file in files) {
      _extractFromWidgets(file.widgets, result);
    }
    return result;
  }

  static void _extractFromWidgets(
    List<WidgetUsage> widgets,
    Map<String, int> result,
  ) {
    for (final widget in widgets) {
      if (widget.type != 'ThemeData') {
        continue;
      }

      // scaffoldBackgroundColor: Color(0xFF...)
      final scaffoldBg = widget.arg('scaffoldBackgroundColor');
      if (scaffoldBg != null) {
        final color = _resolveColor(scaffoldBg);
        if (color != null) {
          result['scaffoldBackgroundColor'] = color;
        }
      }

      // textTheme: TextTheme(bodyLarge: TextStyle(color: ...), ...)
      final textThemeArg = widget.arg('textTheme');
      if (textThemeArg != null) {
        _extractTextTheme(textThemeArg, result);
      }

      // colorScheme: ColorScheme(primary: Color(...), ...)
      final colorSchemeArg = widget.arg('colorScheme');
      if (colorSchemeArg != null) {
        _extractColorScheme(colorSchemeArg, result);
      }
    }
  }

  static void _extractTextTheme(
    Expression expr,
    Map<String, int> result,
  ) {
    final args = _argsOf(expr);
    if (args == null) {
      return;
    }

    for (final arg in args) {
      if (arg is! NamedExpression) {
        continue;
      }
      final slotName = arg.name.label.name;
      final styleExpr = arg.expression;

      final styleArgs = _argsOf(styleExpr);
      if (styleArgs == null) {
        continue;
      }

      for (final styleArg in styleArgs) {
        if (styleArg is! NamedExpression) {
          continue;
        }
        if (styleArg.name.label.name != 'color') {
          continue;
        }
        final color = _resolveColor(styleArg.expression);
        if (color != null) {
          result['textTheme.$slotName'] = color;
        }
      }
    }
  }

  static void _extractColorScheme(
    Expression expr,
    Map<String, int> result,
  ) {
    final args = _argsOf(expr);
    if (args == null) {
      return;
    }

    for (final arg in args) {
      if (arg is! NamedExpression) {
        continue;
      }
      final slotName = arg.name.label.name;
      final color = _resolveColor(arg.expression);
      if (color != null) {
        result['colorScheme.$slotName'] = color;
      }
    }
  }

  static int? _resolveColor(Expression expr) {
    final ctorName = _ctorNameOf(expr);
    if (ctorName == 'Color') {
      final args = _argsOf(expr);
      if (args != null && args.isNotEmpty) {
        final first = args.first;
        if (first is IntegerLiteral) {
          return _normalizeArgb(first.value);
        }
      }
      return null;
    }

    if (expr is PrefixedIdentifier && expr.prefix.name == 'Colors') {
      return _materialColor[expr.identifier.name];
    }
    if (expr is PropertyAccess) {
      final target = expr.target;
      if (target is PrefixedIdentifier && target.prefix.name == 'Colors') {
        return _materialColor[target.identifier.name];
      }
    }

    return null;
  }

  static int? _normalizeArgb(int? value) {
    if (value == null) {
      return null;
    }
    return value <= 0xFFFFFF ? (0xFF000000 | value) : (value & 0xFFFFFFFF);
  }

  static String? _ctorNameOf(Expression expr) {
    if (expr is InstanceCreationExpression) {
      var source = expr.constructorName.type.toSource().trim();
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
    if (expr is MethodInvocation && expr.realTarget == null) {
      return expr.methodName.name;
    }
    return null;
  }

  static NodeList<Expression>? _argsOf(Expression expr) {
    if (expr is InstanceCreationExpression) {
      return expr.argumentList.arguments;
    }
    if (expr is MethodInvocation) {
      return expr.argumentList.arguments;
    }
    return null;
  }

  static const Map<String, int> _materialColor = {
    'transparent': 0x00000000,
    'black': 0xFF000000,
    'black87': 0xDD000000,
    'black54': 0x8A000000,
    'black45': 0x73000000,
    'black38': 0x61000000,
    'black26': 0x42000000,
    'black12': 0x1F000000,
    'white': 0xFFFFFFFF,
    'white70': 0xB3FFFFFF,
    'white60': 0x99FFFFFF,
    'white54': 0x8AFFFFFF,
    'white38': 0x62FFFFFF,
    'white30': 0x4DFFFFFF,
    'white24': 0x3DFFFFFF,
    'white12': 0x1FFFFFFF,
    'white10': 0x1AFFFFFF,
    'red': 0xFFF44336,
    'pink': 0xFFE91E63,
    'purple': 0xFF9C27B0,
    'deepPurple': 0xFF673AB7,
    'indigo': 0xFF3F51B5,
    'blue': 0xFF2196F3,
    'lightBlue': 0xFF03A9F4,
    'cyan': 0xFF00BCD4,
    'teal': 0xFF009688,
    'green': 0xFF4CAF50,
    'lightGreen': 0xFF8BC34A,
    'lime': 0xFFCDDC39,
    'yellow': 0xFFFFEB3B,
    'amber': 0xFFFFC107,
    'orange': 0xFFFF9800,
    'deepOrange': 0xFFFF5722,
    'brown': 0xFF795548,
    'grey': 0xFF9E9E9E,
    'blueGrey': 0xFF607D8B,
  };
}
