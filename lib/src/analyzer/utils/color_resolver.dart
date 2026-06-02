import 'dart:math' as math;

import 'package:analyzer/dart/ast/ast.dart';

/// Resolves Dart color expressions to concrete ARGB values and computes
/// WCAG contrast ratios.
///
/// Resolution is intentionally limited to what can be verified from source
/// alone:
/// - `Color(0xAARRGGBB)` integer literals.
/// - `Colors.<name>` constants from the Material palette (see [_material]).
/// - `Colors.<name>.shadeNNN` resolves to the base entry (a documented
///   approximation — shades aren't tracked individually).
///
/// Anything else (theme lookups, `$styles.colors.x`, variables, `.withOpacity`,
/// `Color.lerp`, etc.) returns `null` — the caller treats that as
/// "indeterminate" rather than guessing.
class ColorResolver {
  /// Attempts to resolve [expr] to a 32-bit ARGB value. Returns `null` if
  /// the color cannot be determined from source.
  static int? resolve(Expression expr) {
    // Color(0xFF2196F3)
    if (expr is InstanceCreationExpression || expr is MethodInvocation) {
      final name = _ctorName(expr);
      if (name == 'Color') {
        final args = _args(expr);
        if (args != null && args.isNotEmpty) {
          final first = args.first;
          if (first is IntegerLiteral) {
            return _normalize(first.value);
          }
        }
      }
      return null;
    }

    if (expr is PrefixedIdentifier) {
      if (expr.prefix.name == 'Colors') {
        return _material[expr.identifier.name];
      }
    }
    if (expr is PropertyAccess) {
      final target = expr.target;
      if (target is PrefixedIdentifier && target.prefix.name == 'Colors') {
        return _material[target.identifier.name];
      }
    }

    return null;
  }

  static double contrastRatio(int argb1, int argb2) {
    final l1 = _relativeLuminance(argb1);
    final l2 = _relativeLuminance(argb2);
    final lighter = math.max(l1, l2);
    final darker = math.min(l1, l2);
    return (lighter + 0.05) / (darker + 0.05);
  }

  /// WCAG relative luminance of an ARGB color.
  static double _relativeLuminance(int argb) {
    final r = _linearize(((argb >> 16) & 0xFF) / 255.0);
    final g = _linearize(((argb >> 8) & 0xFF) / 255.0);
    final b = _linearize((argb & 0xFF) / 255.0);
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
  }

  static double _linearize(double channel) {
    return channel <= 0.03928
        ? channel / 12.92
        : math.pow((channel + 0.055) / 1.055, 2.4).toDouble();
  }

  /// Ensures a full 32-bit ARGB value. `Color(0xFF...)` already includes
  /// alpha; a bare `Color(0x2196F3)` (no alpha byte) is treated as opaque.
  static int? _normalize(int? value) {
    if (value == null) return null;
    if (value <= 0xFFFFFF) {
      return 0xFF000000 | value; // force opaque
    }
    return value & 0xFFFFFFFF;
  }

  static String? _ctorName(Expression expr) {
    if (expr is InstanceCreationExpression) {
      return expr.constructorName.type.name2.lexeme;
    }
    if (expr is MethodInvocation && expr.realTarget == null) {
      return expr.methodName.name;
    }
    return null;
  }

  static NodeList<Expression>? _args(Expression expr) {
    if (expr is InstanceCreationExpression) return expr.argumentList.arguments;
    if (expr is MethodInvocation) return expr.argumentList.arguments;
    return null;
  }

  /// Material primary swatch base values (shade500), plus the basic colors.
  /// ARGB, fully opaque. Source: Flutter's Colors class documented values.
  static const Map<String, int> _material = {
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
