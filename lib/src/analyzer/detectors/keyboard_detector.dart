import '../../models/spec.dart';
import '../../models/coverage_report.dart';
import '../ast/widget_visitor.dart';
import '../rule_detector.dart';

/// Detects WCAG 2.1.1 — Keyboard Accessibility.
///
/// ## Honest scope
///
/// "Is all functionality operable by keyboard?" is not a question static
/// analysis can fully answer — it depends on runtime flow. This detector
/// measures two verifiable signals and combines them:
///
/// **Numerator (matched):** interactive widgets that ARE keyboard-operable
/// out of the box — Material controls (`ElevatedButton`, `TextButton`,
/// `IconButton`, `OutlinedButton`, `FilledButton`, `FloatingActionButton`,
/// `TextField`, `Switch`, `Checkbox`, `Radio`, `Slider`, etc.), plus custom
/// gesture widgets that the developer explicitly made focusable (wrapped in
/// `Focus`/`InkWell` or paired with a keyboard listener).
///
/// **Denominator (total):** the above PLUS custom gesture widgets
/// (`GestureDetector`) with a tap-like action. A `GestureDetector` with
/// `onTap` but no keyboard path is the classic 2.1.1 violation and is
/// flagged.
///
/// Drag/pan-only gesture widgets are skipped here (their keyboard story is
/// different and out of this rule's reliable reach).
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
  };

  @override
  String get ruleId => 'wcag_2_1_1_keyboard';

  @override
  DetectionResult analyze({
    required Rule rule,
    required List<ParsedFile> files,
    Map<String, WidgetAlias> aliases = const {},
  }) {
    int matched = 0;
    int total = 0;
    final findings = <Finding>[];

    for (final file in files) {
      for (final widget in file.widgets) {
        if (_keyboardReady.contains(widget.type)) {
          total++;
          matched++;
          continue;
        }

        if (widget.type == 'GestureDetector' && _hasTapGesture(widget)) {
          total++;
          if (_hasKeyboardProvider(widget)) {
            matched++;
          } else {
            findings.add(Finding(
              filePath: file.path,
              line: widget.line,
              column: widget.column,
              widgetType: 'GestureDetector',
              message:
                  'Tap gesture has no keyboard alternative (no Focus, '
                  'Shortcuts, or keyboard listener ancestor). Keyboard users '
                  'cannot activate it (WCAG 2.1.1).',
            ));
          }
        }
      }
    }

    return DetectionResult(
      matched: matched,
      total: total,
      findings: findings,
    );
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