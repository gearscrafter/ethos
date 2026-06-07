import 'package:analyzer/dart/ast/ast.dart';

import '../../models/spec.dart';
import '../../models/ethos_config.dart';
import '../../models/coverage_report.dart';
import '../ast/widget_visitor.dart';
import '../rule_detector.dart';

class KeyboardDetector implements RuleDetector {
  static const _keyboardReady = {
    'ElevatedButton',
    'TextButton',
    'OutlinedButton',
    'FilledButton',
    'IconButton',
    'FloatingActionButton',
    'TextField',
    'TextFormField',
    'Switch',
    'SwitchListTile',
    'Checkbox',
    'CheckboxListTile',
    'Radio',
    'RadioListTile',
    'Slider',
    'DropdownButton',
    'PopupMenuButton',
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

  static const _keyboardProviders = {
    'Focus',
    'FocusScope',
    'Shortcuts',
    'CallbackShortcuts',
    'FocusableActionDetector',
    'KeyboardListener',
    'RawKeyboardListener',
    'FullscreenKeyboardListener',
    'MouseRegion',
    'Actions',
    'Semantics',
  };

  @override
  String get ruleId => 'wcag_2_1_1_keyboard';

  @override
  DetectionResult analyze({
    required Rule rule,
    required List<ParsedFile> files,
    Map<String, WidgetAlias> aliases = const {},
    Map<String, ColorAlias> colorAliases = const {},
  }) {
    int matched = 0;
    int total = 0;
    final findings = <Finding>[];

    for (final file in files) {
      for (final widget in file.widgets) {
        final alias = aliases[widget.type];
        if (alias != null &&
            alias.role == WidgetRole.button &&
            alias.keyboardReady) {
          total++;
          matched++;
          continue;
        }

        if (_keyboardReady.contains(widget.type)) {
          total++;
          matched++;
          continue;
        }

        if (widget.type == 'GestureDetector' && _hasTapGesture(widget)) {
          if (_hasExcludeFromSemantics(widget)) continue;

          total++;
          if (_hasKeyboardProvider(widget)) {
            matched++;
          } else {
            findings.add(Finding(
              filePath: file.path,
              line: widget.line,
              column: widget.column,
              widgetType: 'GestureDetector',
              message: 'Tap gesture has no keyboard alternative (no Focus, '
                  'Shortcuts, or keyboard listener ancestor). Keyboard users '
                  'cannot activate it (WCAG 2.1.1).',
            ));
          }
        }
      }
    }

    return DetectionResult(matched: matched, total: total, findings: findings);
  }

  bool _hasExcludeFromSemantics(WidgetUsage widget) {
    final arg = widget.arg('excludeFromSemantics');
    return arg is BooleanLiteral && arg.value == true;
  }

  bool _hasTapGesture(WidgetUsage widget) {
    for (final g in _tapGestures) {
      if (widget.namedArgs.containsKey(g)) return true;
    }
    return false;
  }

  bool _hasKeyboardProvider(WidgetUsage widget) {
    return widget.hasAnyAncestor(_keyboardProviders);
  }
}
