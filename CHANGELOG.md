# 0.2.0

- Built-in WCAG 2.2 specification with automatic project configuration via `ethos.yaml`; no external spec files required.

- Extensible design-system support through `widget_aliases` and per-rule customization through `rule_overrides`, allowing custom widgets to participate in accessibility analysis.

- Improved analysis accuracy with alias-aware detectors, precise source-level findings, explicit `Indeterminate` tracking, and better support for modern Dart syntax and widget detection patterns.


## 0.1.0

- Pure static analysis (AST) using `package:analyzer` and `RecursiveAstVisitor` to map Flutter widgets without runtime analysis.

- Transparent metrics: Rigorous classification of nodes into Pass, Fail, or Undetermined (for dynamic styles or `Theme.of(context)` inheritance).

- Complete decoupling: Detectors (`SemanticLabels`, `Contrast`, `TouchTarget`, `Keyboard`, `FocusOrder`) are registered independently in a `DetectorRegistry`.

## 0.0.1

- Initial MVP with 5 WCAG 2.2 coverage rules (semantics, contrast, touch targets, keyboard, focus)
- Spec-Driven Development with formal YAML specifications
- CLI tool with JSON, human, and markdown report formats
- Compliance level determination (A/AA/AAA)
- Full test suite and documentation