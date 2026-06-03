## 0.8.0
 
- **Flutter test integration** — new `package:ethos/ethos_test.dart` barrel
  with matchers and helpers for use in `dart test` or `flutter_test` suites.
  Import path is separate from the main API so test utilities never reach
  production builds.
  
- **`analyzer 8.x` compatibility fixes** — several breaking AST API changes
  introduced in `analyzer 8.x` are now handled across all detectors and
  utilities:
  - `NamedArgument.name` is now a `Token` (not a `Label`) — reading the
    parameter name via `token.toString()` with a `label?.name` fallback for
    7.x.
  - `NamedArgument.argumentExpression` replaces `.expression` as the canonical
    getter for the argument value — tried first with `.expression` fallback.
  - `PositionalArgument` no longer implements `Expression` — unwrapped via
    `.argumentExpression` before type checks.
  - `NodeList<Argument>` replaces `NodeList<Expression>` in
    `ArgumentList.arguments` — all argument iteration uses `dynamic` typing
    with duck-typed helpers.



## 0.7.0
 
- **`ethos watch` subcommand** — incremental re-analysis on file save. Performs
  a full scan on startup, then re-parses only the changed file and recomputes
  the report from the cached results of all other files. Prints the full report
  after each change with `▲/▼` coverage deltas and highlights findings in the
  modified file only.

### 0.6.0

- **2 new WCAG detectors** (7 rules covered):

  - **Non-text Content (1.1.1, Level A):** detects images and icons without an accessible text alternative (`Semantics(label:)`, `semanticLabel`, or explicitly marked as decorative).
  - **Resize Text (1.4.4, Level AA):** detects fixed `textScaleFactor` and `textScaler` values that ignore system text-size preferences.
- **`ethos init`** automatically generates a starter `ethos.yaml` with custom widgets and color definitions that require manual configuration.
- **Public API for `ethos init`** via `WidgetDiscovery.discover()` and `EthosYamlGenerator.generate()`.
- **Compliance levels updated:** WCAG 1.1.1 added to A/AA/AAA, and WCAG 1.4.4 added to AA/AAA.


### 0.5.1

- Resolve absolute path issue for package_config.json

### 0.5.0

- **Deep analysis mode:** a new CLI flag and `DeepAnalyzer`
  API that uses `AnalysisContextCollection` to resolve the full project —
  cross-file references, class hierarchies, and type information. Detects
  widgets and accessibility issues that standard syntactic analysis misses
  entirely. Falls back to standard mode automatically when the project is not
  ready (no `flutter pub get` run).

## 0.4.0
 
- Improved compatibility with newer `analyzer` versions (up to 13.x), ensuring Ethos works reliably across supported releases.

- Added official desktop platform support (`Windows`, `macOS`, and `Linux`) and resolved analyzer/lint-related issues.

- Significantly enhanced color contrast detection by automatically extracting colors from `ThemeData` and supporting custom `color_aliases` in `ethos.yaml`, reducing indeterminate results in real-world applications.


- Introduced `ColorAlias` and `ThemeExtractor` to resolve design-system and theme-based colors into actual WCAG contrast calculations.


# 0.3.0

- CLI command renamed from `accessibility-coverage` to `ethos`.

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