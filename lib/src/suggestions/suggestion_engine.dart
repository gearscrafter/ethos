import '../models/coverage_report.dart';

/// A concrete suggestion for making indeterminate rule coverage
/// verifiable by static analysis.
class Suggestion {
  final String ruleId;
  final String ruleTitle;
  final int indeterminateCount;
  final String problem;
  final List<SuggestionFix> fixes;

  const Suggestion({
    required this.ruleId,
    required this.ruleTitle,
    required this.indeterminateCount,
    required this.problem,
    required this.fixes,
  });
}

class SuggestionFix {
  final String label;
  final String description;
  final String? codeExample;
  final String? yamlExample;

  const SuggestionFix({
    required this.label,
    required this.description,
    this.codeExample,
    this.yamlExample,
  });
}

class SuggestionEngine {
  static List<Suggestion> generate(CoverageReport report) {
    final suggestions = <Suggestion>[];
    for (final coverage in report.coverage.values) {
      if (coverage.indeterminate == 0) {
        continue;
      }
      final s = _suggest(coverage);
      if (s != null) {
        suggestions.add(s);
      }
    }
    return suggestions;
  }

  static Suggestion? _suggest(RuleCoverage coverage) {
    switch (coverage.ruleId) {
      case 'wcag_2_5_5_target_size_enhanced':
        return _touchTargetSuggestion(coverage);
      case 'wcag_1_3_1_semantics_label':
        return _semanticLabelSuggestion(coverage);
      case 'wcag_1_4_3_contrast_minimum':
        return _contrastSuggestion(coverage);
      case 'wcag_1_1_1_non_text_content':
        return _nonTextSuggestion(coverage);
      default:
        return null;
    }
  }

  static Suggestion _touchTargetSuggestion(RuleCoverage c) => Suggestion(
        ruleId: c.ruleId,
        ruleTitle: c.title,
        indeterminateCount: c.indeterminate,
        problem:
            '${c.indeterminate} interactive widgets have a size that depends '
            'on layout constraints — Ethos cannot measure them statically.',
        fixes: [
          SuggestionFix(
            label: 'Option A — Wrap with SizedBox (recommended)',
            description:
                'Wrap GestureDetector / InkWell with an explicit 48×48 '
                'SizedBox. Ethos will detect this statically on the next run.',
            codeExample: '''
// ❌ Before — size unknown
GestureDetector(onTap: () => action(), child: child)

// ✅ After — Ethos can verify statically
SizedBox(
  width: 48,
  height: 48,
  child: GestureDetector(onTap: () => action(), child: child),
)''',
          ),
          SuggestionFix(
            label: 'Option B — Declare size_guaranteed in ethos.yaml',
            description: 'If your custom widget always renders at ≥48×48px by '
                'design, declare it so Ethos treats it as PASS.',
            yamlExample: '''
# ethos.yaml
widget_aliases:
  YourCustomButton:
    role: button
    size_guaranteed: true''',
          ),
          SuggestionFix(
            label: 'Option C — Use ConstrainedBox with minimum size',
            description: 'Ethos detects minWidth/minHeight in BoxConstraints.',
            codeExample: '''
// ✅ Also verifiable statically
ConstrainedBox(
  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
  child: GestureDetector(onTap: () => action(), child: child),
)''',
          ),
        ],
      );

  static Suggestion _semanticLabelSuggestion(RuleCoverage c) => Suggestion(
        ruleId: c.ruleId,
        ruleTitle: c.title,
        indeterminateCount: c.indeterminate,
        problem:
            '${c.indeterminate} interactive widgets have a Semantics label '
            'that is a runtime variable — Ethos cannot verify it is non-empty statically.',
        fixes: [
          SuggestionFix(
            label: 'Option A — Use a literal string or non-empty fallback',
            description:
                'Replace the runtime variable with a literal, or add a '
                'non-empty fallback.',
            codeExample: '''
// ❌ Indeterminate — label could be empty at runtime
Semantics(label: widget.title, child: GestureDetector(...))

// ✅ Option A1 — literal string
Semantics(label: 'Open details', child: GestureDetector(...))

// ✅ Option A2 — non-empty fallback
Semantics(
  label: widget.title.isNotEmpty ? widget.title : 'Open details',
  child: GestureDetector(...),
)''',
          ),
          SuggestionFix(
            label: 'Option B — Declare label_arg in ethos.yaml',
            description:
                'If your custom widget always receives a non-empty label '
                'argument, declare label_arg so Ethos checks it directly.',
            yamlExample: '''
# ethos.yaml
widget_aliases:
  YourButton:
    role: button
    label_arg: label  # Ethos will check this arg is a non-empty literal''',
          ),
          SuggestionFix(
            label: 'Option C — Run with --deep',
            description:
                'Deep mode follows variable references across files and '
                'may resolve more labels automatically.',
            codeExample: 'ethos --deep --suggest',
          ),
        ],
      );

  static Suggestion _contrastSuggestion(RuleCoverage c) => Suggestion(
        ruleId: c.ruleId,
        ruleTitle: c.title,
        indeterminateCount: c.indeterminate,
        problem: '${c.indeterminate} Text widgets use colors from ThemeData or '
            'design-system variables — Ethos cannot compute the contrast ratio statically.',
        fixes: [
          SuggestionFix(
            label: 'Option A — Add color_aliases in ethos.yaml',
            description:
                'Map your design-system color expressions to hex values. '
                'Run `ethos init` to auto-detect them.',
            yamlExample: r'''
# ethos.yaml
color_aliases:
  "$styles.colors.primary":
    foreground: "#1565C0"
    background: "#FFFFFF"''',
          ),
          SuggestionFix(
            label: 'Option B — Use inline Color literals',
            description: 'Replace theme/variable colors with hex literals.',
            codeExample: '''
// ✅ Ethos verifies 4.5:1 ratio automatically
Text(
  'Hello',
  style: TextStyle(
    color: Color(0xFF1565C0),
    backgroundColor: Color(0xFFFFFFFF),
  ),
)''',
          ),
          SuggestionFix(
            label: 'Option C — Run with --deep',
            description: 'Deep mode follows variable references across files '
                'and may resolve colors defined elsewhere automatically.',
            codeExample: 'ethos --deep',
          ),
        ],
      );

  static Suggestion _nonTextSuggestion(RuleCoverage c) => Suggestion(
        ruleId: c.ruleId,
        ruleTitle: c.title,
        indeterminateCount: c.indeterminate,
        problem: '${c.indeterminate} image/icon widget(s) have a semanticLabel '
            'that is a runtime variable — Ethos cannot verify it is non-empty statically.',
        fixes: [
          SuggestionFix(
            label: 'Option A — Use a string literal',
            description:
                'Replace the variable with a descriptive literal string.',
            codeExample: '''
// ❌ Indeterminate
Icon(Icons.search, semanticLabel: iconLabel)

// ✅ Ethos verifies this
Icon(Icons.search, semanticLabel: 'Search artifacts')''',
          ),
          SuggestionFix(
            label: 'Option B — Mark as decorative',
            description: 'If the image/icon conveys no information, explicitly '
                'exclude it from the semantic tree.',
            codeExample: '''
// ✅ Decorative — excluded from semantics
Semantics(
  excludeSemantics: true,
  child: Icon(Icons.decoration),
)''',
          ),
        ],
      );
}
