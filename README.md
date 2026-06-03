# Ethos

Measure accessibility coverage in Flutter apps using WCAG 2.2 specifications with Spec-Driven Development.

[![Pub](https://img.shields.io/pub/v/ethos.svg)](https://pub.dev/packages/ethos)
[![License: Apache-2.0](https://img.shields.io/badge/License-Apache--2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)

## What is Ethos?

Ethos measures **what percentage of your Flutter widgets comply with WCAG 2.2** accessibility standards.

Unlike tools that detect individual issues, Ethos calculates **coverage metrics** for each rule, giving you a clear picture of your app's overall accessibility maturity.

```
📊 Overall Coverage: 44.6%
Compliance Level: NONE

📋 Coverage by Rule:
  ✅ Semantic Labels:  96% (26/27)
  ℹ️  Color Contrast:   NO DATA  ⓘ 82 indeterminate
  ℹ️  Touch Targets:    NO DATA  ⓘ 905 indeterminate
  ⚠️  Keyboard Nav:    66% (8/12)  — CRITICAL
  ⚠️  Focus Order:     0%  (0/1)   — CRITICAL
  ⚠️  Non-text Content: 15% (7/45) — CRITICAL
  ℹ️  Resize Text:      NO DATA (no hardcoded scale — ✅ correct)
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
- ✅ **Deep analysis mode (`--deep`)** — uses `AnalysisContextCollection` to
  resolve cross-file references, class hierarchies, and type information.
  Emits `Stream<AnalysisProgress>` events for live progress. Falls back to
  standard mode automatically if the project is not ready.
- ✅ **Pluggable detector registry** — add or replace rules without touching the
  core engine.
- ✅ **Watch mode (`ethos watch`)** — re-analyzes only the changed file on every
  save, prints the full report with `▲/▼` deltas, and highlights new findings.
- ✅ **Flutter test integration** — `package:ethos/ethos_test.dart` provides
  `expect(report, meetsAccessibilityLevel(WcagLevel.a))` matchers and
  `EthosTestHelper.analyzeSource(dartCode)` for inline detector unit tests.

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
  ethos: ^0.6.0
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

## Standard vs Deep analysis

Ethos has two analysis modes:

| | Standard | Deep (`--deep`) |
|---|---|---|
| Speed | Fast (seconds) | Slower (10–60s) |
| Cross-file resolution | ✗ | ✅ |
| Class hierarchy traversal | ✗ | ✅ |
| Variable type resolution | ✗ | ✅ |
| Progress stream | ✗ | ✅ |
| Requires `flutter pub get` | ✗ | ✅ (auto-detects) |

Standard mode is ideal for quick checks and CI gates. Deep mode is for
comprehensive audits — it finds widgets that standard mode misses because
they are defined in a different file from where they are used.

```bash
# Standard
ethos -p ./my_app

# Deep — with live progress
ethos -p ./my_app --deep -v
```

Deep mode falls back to standard automatically if the project context cannot
be built (e.g. `flutter pub get` has not been run).

### Deep mode as a library

```dart
final deepAnalyzer = await DeepAnalyzer.forProject('./my_app');

await for (final event in deepAnalyzer.analyze()) {
  switch (event) {
    case AnalysisLoadingContext(:final totalFiles):
      print('Loading $totalFiles files...');
    case AnalysisAnalyzingFile(:final current, :final total):
      print('[$current/$total]');
    case AnalysisWarning(:final message):
      print('⚠️  $message');
    case AnalysisComplete():
      final report = (event as AnalysisComplete).report;
      print(report.toJsonString());
    default:
      break;
  }
}
```

---

## Getting started with `ethos init`

If your project uses a custom design system, the first thing to do after
installing Ethos is run `ethos init`. It scans your project for custom widgets
and unresolvable color expressions, then generates a starter `ethos.yaml` with
everything pre-filled — you just review and fill in the values it can't infer.

```bash
ethos init -p ./my_app
```

Example output:

```
🔍 Scanning ./my_app for custom widgets and color tokens...
   Scanned 189 Dart files

   Found 12 custom widget(s), 5 color expression(s)

✅ Generated: ./my_app/ethos.yaml

📦 Custom widgets (fill in role and label_arg):
   CircleIconBtn                  47 uses
   AppBtn                         23 uses
   WonderIllustration             18 uses
   AppHeader                       9 uses

🎨 Color expressions (add hex values to enable contrast checks):
   $styles.text.body              31 uses
   $styles.colors.offWhite        14 uses

Next steps:
  1. Open ./my_app/ethos.yaml
  2. Set role: for each widget_alias
  3. Uncomment label_arg, size_guaranteed, keyboard_ready as needed
  4. Fill in hex values under color_aliases
  5. Run: ethos -p ./my_app -v
```

The generated `ethos.yaml` looks like this — nothing is invented, only
discovered. Values that require human knowledge are left as comments:

```yaml
# ethos.yaml — generated by `ethos init`

widget_aliases:

  # CircleIconBtn — used 47 times
  CircleIconBtn:
    role: button           # button | text | input — REQUIRED
    # label_arg: ???       # e.g. semanticLabel, a11yLabel, label
    # size_guaranteed: true
    # keyboard_ready: true

  # AppBtn — used 23 times
  AppBtn:
    role: button
    # label_arg: ???

color_aliases:
  # used 31 times
  # "$styles.text.body":
  #   foreground: "#REPLACE_ME"
  #   background: "#REPLACE_ME"
```

Once you fill in the values and re-run `ethos -p ./my_app`, the widgets that
were previously invisible (indeterminate) will start contributing to your
coverage score.

---

## Live feedback with `ethos watch`

`ethos watch` performs an initial full scan and then re-analyzes only the
file you just saved. Every change prints the full report with coverage deltas
so you can see the impact of each edit immediately.

```bash
ethos watch -p ./my_app

# With deep analysis on each change:
ethos watch -p ./my_app --deep
```

Example output after saving a file:

```
──────────────────────────────────────────────────
🔄  buttons.dart changed (14:23:05)
──────────────────────────────────────────────────

✅ Initial scan complete (189 files)

📊 Overall:  71.4%  ▲ +2.1%  · Compliance: A

✅ Semantic Labels           85.0% (17/20)   ▲ +5.0%
ℹ️  Color Contrast           100.0% (8/8)
✅ Touch Targets             100.0% (8/8)
⚠️  Keyboard Nav              66.7% (8/12)   ▼ -3.3%
✅ Focus Order                95.0% (19/20)
⚠️  Non-text Content          15.6% (7/45)   CRITICAL
ℹ️  Resize Text               NO DATA

🔎 Findings in buttons.dart:
  ✗ line 42 — GestureDetector: Tap gesture has no keyboard alternative

Watching for changes... (Ctrl+C to stop)
```

Watch mode observes `lib/`, `test/`, and `example/` with a 300 ms debounce.
Generated files (`.g.dart`, `.freezed.dart`) are ignored automatically.

### Watch mode as a library

```dart
final engine = await WatchEngine.forProject('./my_app');

// Initial full scan
final baseline = await engine.initialScan(
  onProgress: (current, total, path) {
    print('[$current/$total] $path');
  },
);

// Re-analyze on file change
final (newReport, diff) = await engine.reanalyzeFile(changedPath);

print('Overall delta: ${diff.overallDelta > 0 ? "▲" : "▼"} ${diff.overallDelta.abs().toStringAsFixed(1)}%');
print('New critical rules: ${diff.newCritical}');
print('Resolved rules: ${diff.resolvedCritical}');
```

---

## Testing your Flutter project's accessibility

Ethos ships a separate test utilities library so you can write accessibility
assertions directly inside your existing `dart test` or `flutter_test` suites.

### Setup

Add Ethos as a dev dependency:

```yaml
# pubspec.yaml
dev_dependencies:
  ethos: ^0.7.0
  test: ^1.24.0   # or flutter_test if you're in a Flutter project
```

### Project-level accessibility test

Analyze your whole `lib/` folder once in `setUpAll` and assert against the
report. This is the recommended pattern for CI gates:

```dart
// test/accessibility_test.dart
import 'package:test/test.dart';
import 'package:ethos/ethos_test.dart';

void main() {
  group('Accessibility coverage', () {
    late CoverageReport report;

    setUpAll(() async {
      report = await EthosTestHelper.analyzeProject('lib/');
    });

    test('meets WCAG Level A', () {
      expect(report, meetsAccessibilityLevel(WcagLevel.a));
    });

    test('semantic labels above 80%', () {
      expect(report, hasRuleCoverage(
        'wcag_1_3_1_semantics_label',
        greaterThan(80),
      ));
    });

    test('no critical failures', () {
      expect(report, hasNoCriticalFailures());
    });

    test('no image accessibility issues', () {
      expect(report, hasNoFindingsFor('wcag_1_1_1_non_text_content'));
    });
  });
}
```

Run it with:

```bash
dart test test/accessibility_test.dart
# or
flutter test test/accessibility_test.dart
```

Exit code `1` when any assertion fails — plugs straight into CI.

### Detector unit tests with inline source

`EthosTestHelper.analyzeSource` parses a Dart snippet in memory without
touching the filesystem. Use it to test specific widgets in isolation:

```dart
import 'package:test/test.dart';
import 'package:ethos/ethos_test.dart';

void main() {
  group('Icon accessibility', () {
    test('Icon with semanticLabel passes', () async {
      final report = await EthosTestHelper.analyzeSource(
        "Icon(Icons.search, semanticLabel: 'Search artifacts')",
      );
      expect(report, passesRule('wcag_1_1_1_non_text_content'));
    });

    test('Icon without semanticLabel fails', () async {
      final report = await EthosTestHelper.analyzeSource('Icon(Icons.close)');
      final cov = report.coverage['wcag_1_1_1_non_text_content'];
      expect(cov?.findings, isNotEmpty);
    });
  });

  group('GestureDetector accessibility', () {
    test('with Semantics ancestor passes', () async {
      final report = await EthosTestHelper.analyzeSource('''
        Semantics(
          label: 'Open profile',
          child: GestureDetector(
            onTap: () => navigate(),
            child: Icon(Icons.person),
          ),
        )
      ''');
      expect(report, passesRule('wcag_1_3_1_semantics_label'));
    });

    test('without Semantics fails', () async {
      final report = await EthosTestHelper.analyzeSource('''
        GestureDetector(onTap: () => navigate(), child: Icon(Icons.settings))
      ''');
      final cov = report.coverage['wcag_1_3_1_semantics_label'];
      expect(cov?.findings, isNotEmpty);
    });
  });

  group('Color contrast', () {
    test('black on white passes', () async {
      final report = await EthosTestHelper.analyzeSource(
        "Text('Hello', style: TextStyle(color: Colors.black, backgroundColor: Colors.white))",
      );
      expect(report, passesRule('wcag_1_4_3_contrast_minimum'));
    });

    test('light grey on white fails', () async {
      final report = await EthosTestHelper.analyzeSource(
        "Text('Hello', style: TextStyle(color: Color(0xFFCCCCCC), backgroundColor: Color(0xFFFFFFFF)))",
      );
      final cov = report.coverage['wcag_1_4_3_contrast_minimum'];
      expect(cov?.findings, isNotEmpty);
    });
  });
}
```

### Available matchers

| Matcher | Description |
|---------|-------------|
| `meetsAccessibilityLevel(WcagLevel.a)` | Overall coverage meets Level A (≥70%), AA (≥85%), or AAA (≥95%) |
| `passesRule('rule_id')` | A specific rule is not below its critical threshold |
| `hasRuleCoverage('rule_id', greaterThan(80))` | Rule coverage satisfies any `Matcher` |
| `hasNoCriticalFailures()` | No rule is below its critical threshold |
| `hasNoFindingsFor('rule_id')` | No findings for a specific rule |

### One-liner smoke test

For a quick CI check with no setup:

```dart
test('no critical a11y failures', () async {
  await EthosTestHelper.expectNoCriticalFailures('lib/');
});
```

Throws a descriptive `TestFailure` listing every critical rule if any exist.

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
omitted, the element remains indeterminate.

No `ethos.yaml`? Ethos still runs on the built-in spec. For a vanilla Flutter
project that's already useful; for a project with a design system, the aliases
make all the difference — and deep mode can discover many of them automatically.

---

## Supported rules

Seven built-in rules, all backed by `RecursiveAstVisitor` on real Dart AST.
Deep mode runs enhanced versions of rules 1 and 2.

### 1. Semantic Labels — `wcag_1_3_1_semantics_label` (WCAG 1.3.1 · Level A)

Custom interactive widgets must have an accessible label.

- **In scope:** `GestureDetector`, `InkWell`, `InkResponse` with tap-like
  gestures, plus any `role: button` alias from `ethos.yaml`.
- **Pass:** wrapped in `Semantics(label: '<non-empty literal>')` as ancestor or
  descendant; or the alias `label_arg` is a non-empty literal.
- **Indeterminate:** label is a variable, interpolation, or runtime call.
- **Excluded automatically:** `excludeFromSemantics: true`, drag/pan-only
  gestures, `onTap: () {}` (block-parent), tap-to-dismiss patterns.
- **Deep mode:** also follows widget definitions across files and detects
  cross-method `Semantics` wrappers.

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

Text must have at least 4.5:1 contrast (3:1 for large text ≥ 18 pt).
Resolution is attempted in layers:

1. **Inline literals** — `TextStyle(color: Color(0xFF...), backgroundColor: ...)`.
2. **ThemeData extraction** — resolves `theme.textTheme.bodyLarge` etc.
3. **`color_aliases`** — resolves design-system expressions from `ethos.yaml`.
4. **Deep mode only** — follows variable references across files.

```dart
// ✅ PASS — ratio 21:1
Text('Hello', style: TextStyle(color: Colors.black, backgroundColor: Colors.white))

// ❌ FAIL — ratio ~1.6:1
Text('Hello', style: TextStyle(color: Color(0xFFCCCCCC), backgroundColor: Colors.white))

// ⓘ INDETERMINATE in standard mode; resolved in deep mode
Text('Hello', style: TextStyle(color: bodyColor))  // bodyColor defined elsewhere
```

### 3. Touch Target Size — `wcag_2_5_5_target_size_enhanced` (WCAG 2.5.5 · Level AAA)

Interactive elements must be at least 48×48 logical pixels.

- **Auto-pass:** `IconButton`, `FloatingActionButton`; aliases with `size_guaranteed: true`.
- **Verifiable:** custom widget in a `SizedBox`/`Container` with literal dimensions.
- **Indeterminate:** size from a variable or intrinsic content.

### 4. Keyboard Accessibility — `wcag_2_1_1_keyboard` (WCAG 2.1.1 · Level A)

All interactive functionality must be reachable by keyboard.

- **Pass:** Material controls; `GestureDetector` under `Focus`/`FocusScope`/
  `Shortcuts`/`KeyboardListener`; aliases with `keyboard_ready: true`.
- **Fail:** `GestureDetector.onTap` with no keyboard path.
- **Excluded:** `excludeFromSemantics: true` (visual-only wrappers).

### 5. Focus Order — `wcag_2_4_3_focus_order` (WCAG 2.4.3 · Level A)

Multi-input layouts must declare explicit focus management.

- **In scope:** `Form` widgets, or layouts with 2+ focusable inputs.
- **Pass:** declares `FocusNode`, `FocusScope`, `FocusTraversalGroup`, or `autofocus: true`.

### 6. Non-text Content — `wcag_1_1_1_non_text_content` (WCAG 1.1.1 · Level A)

All images and icons that convey information must have a text alternative.
Purely decorative content must be explicitly excluded from the semantic tree.

- **In scope:** `Image`, `Image.asset`, `Image.network`, `Image.file`,
  `SvgPicture.asset`, `SvgPicture.network`, `Icon`.
- **Pass:** wrapped in `Semantics(label: '...')`, or `excludeFromSemantics: true`
  (decorative); for `Icon`, a non-empty literal `semanticLabel:` argument.
- **Indeterminate:** label is a runtime variable.
- **Fail:** no label and no explicit decoration marker.

```dart
// ✅ PASS — informative image with label
Semantics(
  label: 'Photo of the Colosseum',
  child: Image.network(url),
)

// ✅ PASS — decorative image explicitly excluded
Image.asset('assets/bg.png', excludeFromSemantics: true)

// ✅ PASS — icon with semantic label
Icon(Icons.search, semanticLabel: 'Search artifacts')

// ❌ FAIL — image without any accessibility annotation
Image.network(artifactUrl)

// ❌ FAIL — icon without semanticLabel
Icon(Icons.close)
```

### 7. Resize Text — `wcag_1_4_4_resize_text` (WCAG 1.4.4 · Level AA)

Text must be resizable up to 200% without loss of content. Hardcoding
`textScaleFactor` or `textScaler` to a fixed value ignores system font-size
preferences set by users with visual impairments.

- **In scope:** only `Text` and `MediaQuery` widgets that explicitly set
  `textScaleFactor` or `textScaler`. Widgets without these args are correct by
  default and are not counted.
- **Pass:** `textScaleFactor: null` (inherits system), or variable-based scaling
  that cannot be verified statically.
- **Fail:** literal `textScaleFactor`, `TextScaler.noScaling`, or
  `TextScaler.linear(<literal>)`.

```dart
// ✅ PASS — inherits system preference (the right default)
Text('Hello')

// ✅ PASS — explicitly null (same as default)
Text('Hello', textScaleFactor: null)

// ❌ FAIL — locks font size, ignores accessibility settings
Text('Hello', textScaleFactor: 1.0)

// ❌ FAIL — forces no scaling
Text('Hello', textScaler: TextScaler.noScaling)
```

> **NO DATA is a good sign** for Resize Text. It means your project does not
> override text scaling anywhere — which is exactly what WCAG requires.

---

## CLI reference

```
ethos -p <project-path> [options]
ethos init -p <project-path>        (generate starter ethos.yaml)
ethos watch -p <project-path>       (watch for changes and re-analyze)

Options (analyze):
  -p, --project-path   Path to the Flutter project to analyze (required)
  -c, --config         Path to a custom ethos.yaml (default: auto-detect)
  -r, --report-type    Output format: human | json | markdown | coverage
                       (default: human)
  -o, --output         Write report to this file instead of stdout
  -d, --deep           Deep analysis: resolves types and cross-file references.
                       Slower but more precise. Requires `flutter pub get`.
                       Falls back to standard mode if project is not ready.
  -v, --verbose        Show progress details (written to stderr)
  -h, --help           Show this help

Options (watch):
  -p, --project-path   Path to the Flutter project to watch (required)
  -d, --deep           Use deep analysis on each change
  -h, --help           Show this help

Examples:
  ethos -p ./my_app
  ethos -p ./my_app --deep
  ethos -p ./my_app --deep -v
  ethos -p ./my_app -c path/to/ethos.yaml
  ethos -p ./my_app -r json -o report.json
  ethos -p ./my_app -r markdown -o report.md
  ethos init -p ./my_app
  ethos init -p ./my_app -o path/to/ethos.yaml
  ethos watch -p ./my_app
  ethos watch -p ./my_app --deep
```

Verbose logs go to **stderr** so `ethos -p . -r json | jq` works cleanly.
Exit code `1` when any rule is below its critical threshold — useful as a CI gate.

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
// Standard entry point
final analyzer = await CoverageAnalyzer.forProject('./my_app');
final report = await analyzer.analyze();

// Deep entry point
final deepAnalyzer = await DeepAnalyzer.forProject('./my_app');
await for (final event in deepAnalyzer.analyze()) {
  if (event is AnalysisComplete) {
    final report = (event as AnalysisComplete).report;
    print(report.toJsonString());
  }
}

// Watch entry point
final engine = await WatchEngine.forProject('./my_app');
final baseline = await engine.initialScan();
final (newReport, diff) = await engine.reanalyzeFile(changedPath);

// Output
print(report.overallCoverage);   // double 0–100
print(report.complianceLevel);   // 'A' | 'AA' | 'AAA' | 'NONE'
print(report.toJsonString());    // JSON for CI pipelines
```

Two separate import paths keep test utilities out of production builds:

```dart
import 'package:ethos/ethos.dart';       // main API — use in production code
import 'package:ethos/ethos_test.dart';  // matchers + helpers — use in tests only
```

---

## Architecture

```
ethos/
├── bin/
│   └── analyze.dart               # CLI (analyze + init + watch subcommands)
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
│           ├── coverage_analyzer.dart  # Standard engine
│           ├── spec_loader.dart
│           ├── detector_registry.dart
│           ├── rule_detector.dart      # RuleDetector interface
│           ├── ast/widget_visitor.dart
│           ├── utils/
│           │   ├── color_resolver.dart
│           │   └── theme_extractor.dart
│           ├── detectors/              # 7 standard detectors
│           │   ├── semantic_labels_detector.dart
│           │   ├── contrast_detector.dart
│           │   ├── touch_target_detector.dart
│           │   ├── keyboard_detector.dart
│           │   ├── focus_order_detector.dart
│           │   ├── non_text_content_detector.dart
│           │   └── resize_text_detector.dart
│           ├── deep/
│           │   ├── deep_analyzer.dart       # Deep engine (Stream)
│           │   ├── deep_detector.dart       # DeepDetector interface
│           │   ├── analysis_progress.dart   # Sealed class: 6 event types
│           │   ├── resolved_file.dart       # ResolvedFile + ProjectIndex
│           │   └── detectors/
│           │       ├── cross_file_semantic_labels_detector.dart
│           │       └── resolved_contrast_detector.dart
│           ├── watch/
│           │   └── watch_engine.dart        # Incremental cache + ReportDiff
│           └── init/
│               ├── widget_discovery.dart    # Scans for custom widgets/colors
│               └── ethos_yaml_generator.dart # Generates starter ethos.yaml
├── example/
│   ├── main.dart
│   └── fixtures/
│       ├── ethos.yaml
│       └── lib/
└── tool/
    └── embed_spec.dart
```

---

## Roadmap

### v1.0.0
- Animation preferences detector (`wcag_2_3_1`) — flag `AnimationController`
  and transitions that don't respect `MediaQuery.disableAnimations`.
- Configurable rule subset — run only the rules you care about.
- Stable public API with full WCAG 2.2 Level AA coverage.

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