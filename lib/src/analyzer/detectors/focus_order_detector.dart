import 'package:analyzer/dart/ast/ast.dart';

import '../../models/spec.dart';
import '../../models/ethos_config.dart';
import '../../models/coverage_report.dart';
import '../ast/widget_visitor.dart';
import '../rule_detector.dart';

class FocusOrderDetector implements RuleDetector {
  static const _focusableInputs = {
    'TextField',
    'TextFormField',
    'Checkbox',
    'CheckboxListTile',
    'Radio',
    'RadioListTile',
    'Switch',
    'SwitchListTile',
    'DropdownButton',
    'Slider',
  };

  static const _focusManagementWidgets = {
    'FocusScope',
    'FocusTraversalGroup',
    'Focus',
    'FocusableActionDetector',
  };

  static const _focusManagementArgs = {'focusNode', 'autofocus'};

  @override
  String get ruleId => 'wcag_2_4_3_focus_order';

  @override
  DetectionResult analyze({
    required Rule rule,
    required List<ParsedFile> files,
    Map<String, WidgetAlias> aliases = const {},
    Map<String, ColorAlias> colorAliases = const {}, // ← added
  }) {
    int matched = 0;
    int total = 0;
    final findings = <Finding>[];

    for (final file in files) {
      final forms = file.widgets.where((w) => w.type == 'Form').toList();

      if (forms.isNotEmpty) {
        for (final form in forms) {
          total++;
          if (_fileHasFocusManagement(file)) {
            matched++;
          } else {
            findings.add(Finding(
              filePath: file.path,
              line: form.line,
              column: form.column,
              widgetType: 'Form',
              message: 'Form has no explicit focus management (FocusNode, '
                  'FocusScope, autofocus, or FocusTraversalGroup). Focus '
                  'order relies on implicit traversal (WCAG 2.4.3).',
            ));
          }
        }
        continue;
      }

      final inputCount =
          file.widgets.where((w) => _focusableInputs.contains(w.type)).length;
      if (inputCount < 2) continue;

      total++;
      if (_fileHasFocusManagement(file)) {
        matched++;
      } else {
        final firstInput =
            file.widgets.firstWhere((w) => _focusableInputs.contains(w.type));
        findings.add(Finding(
          filePath: file.path,
          line: firstInput.line,
          column: firstInput.column,
          widgetType: 'multi-input layout',
          message:
              'Layout with $inputCount focusable inputs has no explicit focus '
              'management. Verify focus order is logical (WCAG 2.4.3).',
        ));
      }
    }

    return DetectionResult(matched: matched, total: total, findings: findings);
  }

  bool _fileHasFocusManagement(ParsedFile file) {
    for (final w in file.widgets) {
      if (_focusManagementWidgets.contains(w.type)) return true;
      for (final arg in _focusManagementArgs) {
        final value = w.arg(arg);
        if (value == null) continue;
        if (arg == 'autofocus') {
          if (value is BooleanLiteral && value.value == true) return true;
        } else {
          return true;
        }
      }
    }
    return false;
  }
}
