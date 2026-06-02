# Ethos

Measure accessibility coverage in Flutter apps using WCAG 2.2 specifications with Spec-Driven Development.

[![Pub](https://img.shields.io/pub/v/ethos.svg)](https://pub.dev/packages/ethos)
[![License: Apache-2.0](https://img.shields.io/badge/License-Apache--2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)

## What is Ethos?

Ethos measures **what percentage of your Flutter widgets comply with WCAG 2.2** accessibility standards.

Unlike tools that detect individual issues, Ethos calculates **coverage metrics** for each rule, giving you a clear picture of your app's overall accessibility maturity.

```
📊 Overall Coverage: 75.5%
✅ Compliance Level: AA

📋 Coverage by Rule:
  ✅ Semantic Labels:  85% (17/20)
  ⚠️  Color Contrast:  60% (6/10)  — CRITICAL
  ✅ Touch Targets:   100% (12/12)
  ✅ Keyboard Nav:     90% (9/10)
  ✅ Focus Order:      95% (19/20)
     ⓘ 6 indeterminate (color from theme — not counted)
```

## Features

- ✅ **WCAG 2.2 alignment** — coverage metrics, not one-off issue lists.
- ✅ **Honest AST analysis** with `package:analyzer` — no regex, no guessing.
- ✅ **Indeterminate accounting** — values from themes or runtime variables are
  reported separately and never inflate pass/fail ratios.
- ✅ **Built-in spec, zero setup** — the WCAG 2.2 rules ship inside the package.
  You don't copy any YAML file.
- ✅ **Optional `ethos.yaml`** — teach Ethos about your own design-system
  widgets and colors in five minutes.
- ✅ **Theme-aware contrast** — resolves `theme.textTheme.X` automatically from
  your `ThemeData`, and accepts explicit `color_aliases` for custom style
  variables.
- ✅ **Pluggable detector registry** — add or replace rules without touching the
  core engine.
- ✅ **CI/CD ready** — JSON, Markdown, and human-readable outputs; exits with
  code `1` on critical failures.

---

## Installation

### As a CLI

```bash
dart pub global activate ethos
ethos -p ./my_flutter_app
```

### As a library

```yaml
dependencies:
  ethos: ^0.3.1
```

```dart
import 'package:ethos/ethos.dart';

void main() async {
  final analyzer = await CoverageAnalyzer.forProject('./my_flutter_app');
  final report  = await analyzer.analyze();
  print('Coverage:   ${report.overallCoverage}%');
  print('Compliance: ${report.complianceLevel}');
}
```

**You do not copy any spec file.** The built-in WCAG 2.2 spec lives inside the
package.

---

## Quick start (local development)

```bash
git clone https://github.com/gearscrafter/ethos.git
cd ethos
dart pub get

# Run against the bundled fixtures
dart run example/main.dart

# Run against your own Flutter project
dart run bin/analyze.dart -p ./my_flutter_app

# Install locally as a global command
dart pub global activate --source path .
ethos -p ./my_flutter_app
```

---

## Configuration (optional): `ethos.yaml`

Ethos works out of the box — the built-in spec already covers Flutter's
standard widgets (`GestureDetector`, `InkWell`, `IconButton`, `TextField`,
etc.).

Most real apps wrap controls in their own design-system components and define
colors in a custom style object. Drop an `ethos.yaml` next to your
`pubspec.yaml` to teach Ethos about them:

```yaml
# ethos.yaml — OPTIONAL. Ethos auto-detects it; no flag needed.

widget_aliases:
  # Key = your widget's class name exactly as written in code.
  CircleIconBtn:
    role: button             # button | text | input
    label_arg: semanticLabel # which arg carries the accessible label
    size_guaranteed: true    # already wraps a >= 48×48 target internally?
    keyboard_ready: true     # keyboard-operable out of the box?

  AppButton:
    role: button
    label_arg: a11yLabel

color_aliases:
  # Teach Ethos about your design-system color expressions so the contrast
  # rule can compute real WCAG ratios instead of reporting "indeterminate".
  # Key = exact source expression as written in code.
  "$styles.text.body":
    foreground: "#212121"   # required — the text color
    background: "#FFFFFF"   # optional — the default background color

  "$styles.colors.primary":
    foreground: "#1565C0"

# Optional: tighten a threshold without rewriting the spec.
# rule_overrides:
#   wcag_1_4_3_contrast_minimum:
#     critical_threshold: 95
```

What each section teaches:

**`widget_aliases`**

| Field             | Detector                                | Effect                                        |
|-------------------|-----------------------------------------|-----------------------------------------------|
| `role: button`    | Semantic Labels, Keyboard, Touch Target | Widget counts as an interactive control.      |
| `label_arg`       | Semantic Labels                         | Look for the semantic label in this argument. |
| `size_guaranteed` | Touch Target Size                       | Auto-PASS — already ≥ 48×48 internally.       |
| `keyboard_ready`  | Keyboard Accessibility                  | Auto-PASS — keyboard-operable out of the box. |

**`color_aliases`**

Maps a design-system style expression to concrete hex colors. Both
`#RRGGBB` and `#AARRGGBB` formats are accepted. When `background` is
omitted, Ethos cannot compute a ratio and the element remains indeterminate.

No `ethos.yaml`? Ethos still runs on the built-in spec. Custom widgets and
colors appear as indeterminate. For a vanilla Flutter project that's already
useful; for a project with a design system, the aliases make all the
difference.

---

## Supported rules

Five built-in rules, all backed by a `RecursiveAstVisitor` on real Dart AST.

### 1. Semantic Labels — `wcag_1_3_1_semantics_label` (WCAG 1.3.1 · Level A)

Custom interactive widgets must have an accessible label.

- **In scope:** `GestureDetector`, `InkWell`, `InkResponse` with tap-like
  gestures, plus any `role: button` alias from `ethos.yaml`.
- **Pass:** wrapped in `Semantics(label: '<non-empty literal>')` as ancestor or
  descendant; or the alias `label_arg` is a non-empty literal.
- **Indeterminate:** label is a variable, interpolation, or runtime call.
- **Excluded automatically:** `excludeFromSemantics: true`, drag/pan-only
  gestures, `onTap: () {}` (block-parent), tap-to-dismiss patterns.

```dart
// ✅ PASS — Semantics as ancestor
Semantics(
  label: 'Open profile',
  child: GestureDetector(onTap: () {}, child: Icon(Icons.person)),
)

// ✅ PASS — Semantics as descendant also works
GestureDetector(
  onTap: () => navigate(),
  child: Semantics(label: 'Go to settings', child: Icon(Icons.settings)),
)

// ❌ FAIL
GestureDetector(onTap: () => navigate(), child: Icon(Icons.settings))
```

### 2. Minimum Color Contrast — `wcag_1_4_3_contrast_minimum` (WCAG 1.4.3 · Level AA)

Text must have at least 4.5:1 contrast (3:1 for large text ≥ 18 pt) using the
real WCAG luminance formula. Resolution is attempted in three layers:

1. **Inline literals** — `TextStyle(color: Color(0xFF...), backgroundColor: ...)`.
2. **ThemeData extraction** — resolves `theme.textTheme.bodyLarge` etc.
   automatically from your `MaterialApp(theme: ThemeData(...))`.
3. **`color_aliases`** — resolves design-system expressions like
   `$styles.text.body` from your `ethos.yaml`.

```dart
// ✅ PASS — ratio 21:1
Text('Hello', style: TextStyle(
  color: Colors.black,
  backgroundColor: Colors.white,
))

// ❌ FAIL — ratio ~1.6:1
Text('Hello', style: TextStyle(
  color: Color(0xFFCCCCCC),
  backgroundColor: Colors.white,
))

Text('Hello', style: theme.textTheme.bodyLarge)

// ✅ PASS via color_aliases (if declared in ethos.yaml)
// Text('Hello', style: $styles.text.body)
```

### 3. Touch Target Size — `wcag_2_5_5_target_size_enhanced` (WCAG 2.5.5 · Level AAA)

Interactive elements must be at least 48×48 logical pixels.

- **Auto-pass:** `IconButton`, `FloatingActionButton` (Flutter guarantees
  48×48); aliases with `size_guaranteed: true`.
- **Verifiable:** custom interactive widget inside a `SizedBox` or `Container`
  with literal `width`/`height` — pass if both ≥ 48, fail otherwise.
- **Indeterminate:** size from a variable, intrinsic content, or
  `tapTargetSize: shrinkWrap`.

### 4. Keyboard Accessibility — `wcag_2_1_1_keyboard` (WCAG 2.1.1 · Level A)

All interactive functionality must be reachable by keyboard.

- **Pass:** Material controls (`ElevatedButton`, `TextField`, `InkWell`, etc.);
  `GestureDetector` under a `Focus`, `FocusScope`, `Shortcuts`, or
  `KeyboardListener` ancestor; aliases with `keyboard_ready: true`.
- **Fail:** `GestureDetector.onTap` with no keyboard path in its ancestor chain.
- **Excluded:** widgets with `excludeFromSemantics: true` (visual-only wrappers).

### 5. Focus Order — `wcag_2_4_3_focus_order` (WCAG 2.4.3 · Level A)

Multi-input layouts must declare explicit focus management.

- **In scope:** `Form` widgets, or any layout with 2+ focusable inputs
  (`TextField`, `Checkbox`, `Radio`, etc.).
- **Pass:** declares `FocusNode`, `FocusScope`, `FocusTraversalGroup`, or
  `autofocus: true`.

---

## CLI reference

```
ethos -p <project-path> [options]

Options:
  -p, --project-path   Path to the Flutter project to analyze (required)
  -c, --config         Path to a custom ethos.yaml (default: auto-detect)
  -r, --report-type    Output format: human | json | markdown | coverage
                       (default: human)
  -o, --output         Write report to this file instead of stdout
  -v, --verbose        Show progress details (written to stderr)
  -h, --help           Show this help

Examples:
  ethos -p ./my_app
  ethos -p ./my_app -c path/to/ethos.yaml
  ethos -p ./my_app -r json -o report.json
  ethos -p ./my_app -r markdown -o report.md
  ethos -p ./my_app -v
```

Verbose logs go to **stderr** so `ethos -p . -r json | jq` works cleanly.
Exit code `1` when any rule is below its critical threshold — useful as a CI
gate.

---

## Compliance levels

| Level | Minimum coverage | Description                           |
|-------|-----------------|---------------------------------------|
| AAA   | ≥ 95%           | Enhanced accessibility                |
| AA    | ≥ 85%           | Strong accessibility (typical target) |
| A     | ≥ 70%           | Basic accessibility                   |
| NONE  | < 70%           | Does not meet minimum standards       |

---

## Library API reference

```dart
// Standard entry point — built-in spec + optional ethos.yaml auto-merge
final analyzer = await CoverageAnalyzer.forProject('./my_app');

// With explicit config file
final analyzer = await CoverageAnalyzer.forProject(
  './my_app',
  configPath: 'path/to/ethos.yaml',
);

// Run analysis
final report = await analyzer.analyze();

// Output options
print(report.overallCoverage);   // double 0–100
print(report.complianceLevel);   // 'A' | 'AA' | 'AAA' | 'NONE'
print(report.toJsonString());    // JSON for CI pipelines
```

Advanced: `CoverageAnalyzer.loadFromFile(specPath, projectPath: ...)` and
`.fromString(yaml, projectPath: ...)` load a fully custom spec instead of the
built-in.

---

## Architecture

```
ethos/
├── bin/
│   └── analyze.dart               # CLI entry point
├── lib/
│   ├── ethos.dart                 # Public barrel export
│   └── src/
│       ├── models/
│       │   ├── spec.dart          # Spec, Rule, WidgetAlias, WidgetRole
│       │   ├── ethos_config.dart  # EthosConfig, ColorAlias, RuleOverride
│       │   └── coverage_report.dart  # CoverageReport, RuleCoverage, Finding
│       ├── specs/v1/
│       │   ├── wcag_2_2.yaml          # Source spec — edit this
│       │   └── wcag_2_2_embedded.dart # Generated constant — do not edit
│       └── analyzer/
│           ├── coverage_analyzer.dart  # Engine (forProject / analyze)
│           ├── spec_loader.dart        # Built-in + ethos.yaml merge
│           ├── detector_registry.dart
│           ├── rule_detector.dart      # RuleDetector interface
│           ├── ast/widget_visitor.dart
│           ├── utils/
│           │   ├── color_resolver.dart  # WCAG luminance + Colors.* map
│           │   └── theme_extractor.dart # ThemeData color extraction
│           └── detectors/
│               ├── semantic_labels_detector.dart
│               ├── contrast_detector.dart
│               ├── touch_target_detector.dart
│               ├── keyboard_detector.dart
│               └── focus_order_detector.dart
├── example/
│   ├── main.dart
│   └── fixtures/
│       ├── ethos.yaml             # Sample widget + color aliases
│       └── lib/                   # Sample Dart files (analysis input only)
├── test/
└── tool/
    └── embed_spec.dart            # Regenerates wcag_2_2_embedded.dart
```

When editing the built-in spec (`lib/src/specs/v1/wcag_2_2.yaml`), regenerate
the embedded constant:

```bash
dart run tool/embed_spec.dart
```

---

## Roadmap

### v1.0.0
- Widget alias inheritance — alias a widget once and child widgets inherit its
  traits automatically.
- Cross-method/cross-file resolution so a `Semantics` wrapper in a parent widget
  connects to a custom button in a child.
- More built-in detectors: text scaling, alternative text on images, animation
  preferences.
- Configurable rule subset — run only the rules you care about.

---

## Contributing

Contributions are welcome. High-value areas:

- Additional WCAG 2.2 detectors.
- Improved theme/`$styles` resolution for the contrast rule.
- CI/CD integration examples (GitHub Actions, GitLab CI).

---

## License

Apache-2.0 — see [LICENSE](LICENSE).

## Author

[@gearscrafter](https://github.com/gearscrafter) — Mobile Developer.

## Resources

- [WCAG 2.2 Quick Reference](https://www.w3.org/WAI/WCAG22/quickref/)
- [Flutter Accessibility Docs](https://docs.flutter.dev/ui/accessibility)
- [Material Design 3 — Accessibility](https://m3.material.io/foundations/accessible-design/overview)
- [WebAIM Contrast Checker](https://webaim.org/resources/contrastchecker/)

---

**Made with ❤️ for inclusive Flutter apps.**