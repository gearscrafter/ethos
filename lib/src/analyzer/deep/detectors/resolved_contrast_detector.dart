import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';

import '../../../models/coverage_report.dart';
import '../../../models/ethos_config.dart';
import '../../../models/spec.dart';
import '../../ast/widget_visitor.dart';
import '../../rule_detector.dart';
import '../../utils/color_resolver.dart';
import '../../utils/theme_extractor.dart';
import '../deep_detector.dart';
import '../resolved_file.dart';

class ResolvedContrastDetector implements DeepDetector {
  final ProjectIndex index;

  ResolvedContrastDetector({required this.index});

  @override
  String get ruleId => 'wcag_1_4_3_contrast_minimum';

  static const double _ratioNormal = 4.5;
  static const double _ratioLarge = 3.0;
  static const double _largeFontPt = 18.0;

  @override
  DetectionResult analyzeDeep({
    required Rule rule,
    required List<ResolvedFile> files,
    required ProjectIndex index,
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
          final r = _tryInline(styleArg);
          if (r != null) {
            total++;
            _judge(
                r.$1, r.$2, r.$3, widget, file, (v) => matched += v, findings);
            continue;
          }
        }

        if (styleArg != null) {
          final r = _tryTheme(styleArg, themeColors);
          if (r != null) {
            total++;
            _judge(
                r.$1, r.$2, r.$3, widget, file, (v) => matched += v, findings);
            continue;
          }
        }

        if (styleArg != null && colorAliases.isNotEmpty) {
          final r = _tryAlias(styleArg, colorAliases);
          if (r != null) {
            total++;
            _judge(
                r.$1, r.$2, r.$3, widget, file, (v) => matched += v, findings);
            continue;
          }
        }

        if (styleArg != null && !file.hasErrors) {
          final r = _tryResolvedVariable(styleArg, file);
          if (r != null) {
            total++;
            _judge(
                r.$1, r.$2, r.$3, widget, file, (v) => matched += v, findings);
            continue;
          }
        }

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

  (int?, int?, double?)? _tryResolvedVariable(
    Expression styleArg,
    ResolvedFile file,
  ) {
    if (file.hasErrors) {
      return null;
    }
    final args = _argsOf(styleArg);
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
          fg = ColorResolver.resolve(value) ?? _resolveIdentifier(value, file);
        case 'backgroundColor':
          bg = ColorResolver.resolve(value) ?? _resolveIdentifier(value, file);
        case 'fontSize':
          if (value is DoubleLiteral) {
            fontSize = value.value;
          } else if (value is IntegerLiteral) {
            fontSize = value.value?.toDouble();
          }
      }
    }

    if (fg == null && bg == null) {
      return null;
    }
    return (fg, bg, fontSize);
  }

  int? _resolveIdentifier(Expression expr, ResolvedFile file) {
    if (expr is! SimpleIdentifier) {
      return null;
    }
    final element = expr.element;
    if (element == null) {
      return null;
    }
    if (element is TopLevelVariableElement || element is FieldElement) {
      final initializer = (element as dynamic).initializer as Expression?;
      if (initializer != null) {
        return ColorResolver.resolve(initializer);
      }
    }
    return null;
  }

  bool _isTextStyle(Expression expr) => _ctorName(expr) == 'TextStyle';

  (int?, int?, double?)? _tryInline(Expression styleArg) {
    final args = _argsOf(styleArg);
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
    if (fg == null || bg == null) {
      return null;
    }
    return (fg, bg, fontSize);
  }

  (int?, int?, double?)? _tryTheme(
    Expression styleArg,
    Map<String, int> themeColors,
  ) {
    if (themeColors.isEmpty) {
      return null;
    }
    if (styleArg is! PropertyAccess) {
      return null;
    }
    final slotName = styleArg.propertyName.name;
    final mid = styleArg.target;
    if (mid is! PropertyAccess) {
      return null;
    }
    final section = mid.propertyName.name;
    if (section != 'textTheme' && section != 'colorScheme') {
      return null;
    }
    final fg = themeColors['$section.$slotName'];
    if (fg == null) {
      return null;
    }
    final bg = themeColors['scaffoldBackgroundColor'];
    return (fg, bg, null);
  }

  (int?, int?, double?)? _tryAlias(
    Expression styleArg,
    Map<String, ColorAlias> colorAliases,
  ) {
    final alias = colorAliases[styleArg.toSource().trim()];
    if (alias == null) {
      return null;
    }
    return (alias.foreground, alias.background, null);
  }

  void _judge(
    int? fg,
    int? bg,
    double? fontSize,
    WidgetUsage widget,
    ResolvedFile file,
    void Function(int) matched,
    List<Finding> findings,
  ) {
    if (fg == null || bg == null) {
      return;
    }
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
        message: 'Contrast ratio ${ratio.toStringAsFixed(2)}:1 is below '
            '${required.toStringAsFixed(1)}:1 (WCAG AA).',
      ));
    }
  }

  String? _ctorName(Expression expr) {
    if (expr is InstanceCreationExpression) {
      var s = expr.constructorName.type.toSource().trim();
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
    if (expr is MethodInvocation && expr.realTarget == null) {
      return expr.methodName.name;
    }
    return null;
  }

  dynamic _argsOf(Expression expr) {
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
