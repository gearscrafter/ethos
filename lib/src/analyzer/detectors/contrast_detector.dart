import 'package:analyzer/dart/ast/ast.dart';

import '../../models/spec.dart';
import '../../models/ethos_config.dart';
import '../../models/coverage_report.dart';
import '../ast/widget_visitor.dart';
import '../rule_detector.dart';
import '../utils/color_resolver.dart';
import '../utils/theme_extractor.dart';

/// Detects WCAG 1.4.3 — Minimum Color Contrast.
///
///
/// ## Thresholds
///
class ContrastDetector implements RuleDetector {
  static const double _ratioNormal = 4.5;
  static const double _ratioLarge = 3.0;
  static const double _largeFontPt = 18.0;

  @override
  String get ruleId => 'wcag_1_4_3_contrast_minimum';

  @override
  DetectionResult analyze({
    required Rule rule,
    required List<ParsedFile> files,
    Map<String, WidgetAlias> aliases = const {},
    Map<String, ColorAlias> colorAliases = const {},
  }) {
    final themeColors = ThemeExtractor.extractFromFiles(files);

    int matched = 0;
    int total = 0;
    int indeterminate = 0;
    final findings = <Finding>[];

    for (final file in files) {
      for (final widget in file.widgets) {
        if (widget.type != 'Text') {
          continue;
        }

        final styleArg = widget.arg('style');

        if (styleArg != null && _isTextStyle(styleArg)) {
          final colors = _extractInlineColors(styleArg);
          if (colors != null) {
            final (fg, bg, fontSize) = colors;
            if (fg != null && bg != null) {
              total++;
              _judge(
                fg: fg,
                bg: bg,
                fontSize: fontSize,
                widget: widget,
                file: file,
                matched: (v) => matched += v,
                findings: findings,
              );
              continue;
            }
          }
        }

        if (styleArg != null) {
          final themeResult = _resolveFromTheme(styleArg, themeColors);
          if (themeResult != null) {
            final (fg, bg, fontSize) = themeResult;
            if (fg != null && bg != null) {
              total++;
              _judge(
                fg: fg,
                bg: bg,
                fontSize: fontSize,
                widget: widget,
                file: file,
                matched: (v) => matched += v,
                findings: findings,
              );
              continue;
            }
          }
        }

        if (styleArg != null && colorAliases.isNotEmpty) {
          final aliasResult = _resolveFromAlias(styleArg, colorAliases);
          if (aliasResult != null) {
            final (fg, bg, fontSize) = aliasResult;
            if (fg != null && bg != null) {
              total++;
              _judge(
                fg: fg,
                bg: bg,
                fontSize: fontSize,
                widget: widget,
                file: file,
                matched: (v) => matched += v,
                findings: findings,
              );
              continue;
            }
          }
        }

        // ── No layer resolved both colors → indeterminate ────────────────
        indeterminate++;
      }
    }

    return DetectionResult(
      matched: matched,
      total: total,
      indeterminate: indeterminate,
      findings: findings,
    );
  }

  bool _isTextStyle(Expression expr) {
    final name = _ctorName(expr);
    return name == 'TextStyle';
  }

  (int?, int?, double?)? _extractInlineColors(Expression styleArg) {
    final args = _args(styleArg);
    if (args == null) {
      return null;
    }

    int? fg;
    int? bg;
    double? fontSize;

    for (final arg in args as Iterable) {
      if (!_isNamedArg(arg)) {
        continue;
      }
      final key = _namedArgName(arg);
      final value = _namedArgExpr(arg);
      if (key == null || value == null) {
        continue;
      }
      switch (key) {
        case 'color':
          fg = ColorResolver.resolve(value);
        case 'backgroundColor':
          bg = ColorResolver.resolve(value);
        case 'fontSize':
          if (value is DoubleLiteral) {
            fontSize = value.value;
          } else if (value is IntegerLiteral) {
            fontSize = value.value?.toDouble();
          }
      }
    }
    return (fg, bg, fontSize);
  }

  (int?, int?, double?)? _resolveFromTheme(
    Expression styleArg,
    Map<String, int> themeColors,
  ) {
    if (themeColors.isEmpty) {
      return null;
    }

    final key = _themeKeyOf(styleArg);
    if (key == null) {
      return null;
    }

    final fg = themeColors[key];
    if (fg == null) {
      return null;
    }

    final bg = themeColors['scaffoldBackgroundColor'];

    return (fg, bg, null);
  }

  String? _themeKeyOf(Expression expr) {
    if (expr is! PropertyAccess) {
      return null;
    }

    final slotName = expr.propertyName.name;
    final mid = expr.target;

    if (mid is! PropertyAccess) {
      return null;
    }
    final section = mid.propertyName.name;

    if (section != 'textTheme' && section != 'colorScheme') {
      return null;
    }

    return '$section.$slotName';
  }

  (int?, int?, double?)? _resolveFromAlias(
    Expression styleArg,
    Map<String, ColorAlias> colorAliases,
  ) {
    final sourceText = styleArg.toSource().trim();
    final alias = colorAliases[sourceText];
    if (alias == null) {
      return null;
    }
    return (alias.foreground, alias.background, null);
  }

  void _judge({
    required int fg,
    required int bg,
    required double? fontSize,
    required WidgetUsage widget,
    required ParsedFile file,
    required void Function(int) matched,
    required List<Finding> findings,
  }) {
    final ratio = ColorResolver.contrastRatio(fg, bg);
    final required = (fontSize != null && fontSize >= _largeFontPt)
        ? _ratioLarge
        : _ratioNormal;

    if (ratio >= required) {
      matched(1);
    } else {
      findings.add(Finding(
        filePath: file.path,
        line: widget.line,
        column: widget.column,
        widgetType: 'Text',
        message: 'Contrast ratio ${ratio.toStringAsFixed(2)}:1 is below the '
            '${required.toStringAsFixed(1)}:1 minimum required by WCAG AA.',
      ));
    }
  }

  String? _ctorName(Expression expr) {
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

  dynamic _args(Expression expr) {
    if (expr is InstanceCreationExpression) {
      return expr.argumentList.arguments;
    }
    if (expr is MethodInvocation) {
      return expr.argumentList.arguments;
    }
    return null;
  }

  static bool _isNamedArg(dynamic arg) {
    try {
      return arg.name != null;
    } catch (_) {
      return false;
    }
  }

  static String? _namedArgName(dynamic arg) {
    try {
      final n = arg.name;
      if (n == null) {
        return null;
      }
      final s = n.toString();
      if (s.isNotEmpty &&
          !s.contains(' ') &&
          !s.contains('.') &&
          !s.contains(':')) {
        return s;
      }
      try {
        return n.label?.name as String?;
      } catch (_) {}
      return null;
    } catch (_) {
      return null;
    }
  }

  static Expression? _namedArgExpr(dynamic arg) {
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
