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
  ✅ Semantic Labels: 85% (17/20)
  ⚠️  Color Contrast: 60% (6/10) - CRITICAL
  ✅ Touch Targets: 100% (12/12)
  ✅ Keyboard Nav: 90% (9/10)
  ✅ Focus Order: 95% (19/20)
```

## Features

- ✅ **WCAG 2.2 Alignment**: Focuses on core accessibility metrics mapped to standard specs.
- ✅ **Honest Static AST Analysis**: Powered by `package:analyzer`, parsing the real syntax tree instead of raw, unreliable regex pattern matching.
- ✅ **The "Honesty" Architecture**: Explicitly tracks **Indeterminate** results (e.g., dynamic colors, size variables, inherited themes) so they do not pollute your pass/fail ratios with guesswork.
- ✅ **Spec-Driven Design**: Decouples rules and criteria via YAML specifications loaded and validated dynamically.
- ✅ **Pluggable Detector Registry**: Easily add, replace, or extend rules without modifying the core analysis pipeline.
- ✅ **CLI Executable**: Ready for local terminal inspections and CI/CD integration.

---

## Supported Architecture & Rules

Ethos includes 5 built-in rules that walk your Flutter codebase using a robust `RecursiveAstVisitor`:

### 1. Semantic Labels (`wcag_1_3_1_semantics`)
Ensures custom interactive components have an accessible label.
- **In-Scope (Denominator)**: Custom gesture widgets (`GestureDetector`, `InkWell`, `InkResponse`) that act as active targets. Excludes elements explicitly hidden via `excludeFromSemantics: true` or handling continuous drag/pan gestures.
- **Pass (Numerator)**: Wrapped in a `Semantics` widget with a literal, non-empty `label`.
- **Indeterminate**: Wrapped in `Semantics` but the label is a variable, string interpolation, or runtime method call.

### 2. Minimum Color Contrast (`wcag_1_4_3_contrast`)
Checks text legibility according to WCAG AA (4.5:1 / 3.0:1) parameters.
- **In-Scope (Denominator)**: `Text` widgets where both text color and background color are declared inline as resolvable literals.
- **Pass (Numerator)**: The calculated contrast ratio meets WCAG thresholds.
- **Indeterminate**: Text colors from `Theme.of(context)`, custom global style variables (`$styles.text.body`), or when the background is inherited from a parent `Container`/`Scaffold`.

### 3. Touch Target Size (`wcag_2_5_5_touch_target`)
Verifies interactive element targets meet the standard $48 \times 48$ logical pixel minimum.
- **Pass (Numerator)**: Material controls with built-in size guarantees (`IconButton`, `FloatingActionButton`), or custom gesture nodes explicitly sized via an enclosing `SizedBox` or `Container` with literal dimensions $\ge 48$.
- **Indeterminate**: Size derived from runtime constraints, intrinsic dimensions, or custom button properties opting out of layout rules (`MaterialTapTargetSize.shrinkWrap`).

### 4. Keyboard Accessibility (`wcag_2_1_1_keyboard`)
Detects whether interactive workflows are accessible via external inputs.
- **Denominator**: All interactive nodes.
- **Pass (Numerator)**: Built-in Material buttons (`ElevatedButton`, `TextButton`, etc.) that handle focus natively, or custom tap targets properly wrapped in a `Focus` node / keyboard listener.
- **Fail**: A raw `GestureDetector.onTap` completely missing alternative keyboard paths.

### 5. Focus Order (`wcag_2_4_3_focus_order`)
Ensures multi-input user flows manage the focus traversal sequence.
- **Context**: Triggered by full `Form` scopes or layouts containing 2 or more focusable input nodes (`TextField`, `Checkbox`, etc.).
- **Pass (Numerator)**: Layout declares explicit focus management mechanisms via `FocusNode`, `FocusScope`, `FocusTraversalGroup`, or `autofocus`.

---

## Installation

### As a library

Add to your `pubspec.yaml`:

```yaml
dependencies:
  ethos: ^0.0.1
```

### Local Development

For development, you can test the CLI directly:

```bash
git clone https://github.com/gearscrafter/ethos.git
cd ethos
dart pub get

# Run CLI directly
dart run bin/analyze.dart -p ./lib

# Or install locally
dart pub global activate --path .
ethos -p ./lib
```

## Quick Start

### Option 1: Global CLI Tool

#### 1. Install globally

```bash
dart pub global activate ethos
```

#### 2. Analyze a Flutter Project

```bash
ethos -p ./my_flutter_app
```

Output:
```
╔════════════════════════════════════════════════╗
║  Accessibility Coverage Report                 ║
║  Spec v1.0.0                                   ║
╚════════════════════════════════════════════════╝

📊 Summary
──────────────────────────────────────────────────
Overall Coverage: 75.50%
Compliance Level: AA
Project: ./my_flutter_app
Analyzed: 2026-04-01T12:34:56.789Z

📋 Coverage by Rule
──────────────────────────────────────────────────
✅ Semantic Labels on Interactive Widgets
   Coverage: 85.00% (17/20) [OK]

⚠️  Minimum Color Contrast
   Coverage: 60.00% (6/10) [CRITICAL]

✅ Touch Target Size (Enhanced)
   Coverage: 100.00% (12/12) [OK]

✅ Keyboard Accessibility
   Coverage: 90.00% (9/10) [OK]

✅ Focus Order
   Coverage: 95.00% (19/20) [OK]
```

#### 3. Generate JSON Report

```bash
ethos -p ./my_app -r json -o report.json
```

#### 4. Generate Markdown Report

```bash
ethos -p ./my_app -r markdown -o report.md
```

### Option 2: Use as Dart Library

#### 1. Add to your project

```bash
dart pub add ethos
```

#### 2. Use in your code

```dart
import 'package:ethos/ethos.dart';

void main() async {
  // Load analyzer with specs
  final analyzer = await CoverageAnalyzer.loadFromFile(
    'specs/v1.0.0/wcag_2_2.yaml'
  );
  
  // Analyze project
  final report = await analyzer.analyze(
    projectPath: './my_flutter_app'
  );
  
  // Use results
  print('Coverage: ${report.overallCoverage}%');
  print('Compliance: ${report.complianceLevel}');
  
  // Output JSON
  print(report.toJsonString());
}
```

#### 3. Or run with dart

```bash
dart run ethos -p ./my_app
```

## CLI Usage

After installing globally with `dart pub global activate ethos`:

```bash
ethos [options]

Options:
  -p, --project-path      Path to Flutter project (required)
  -s, --spec-version      Specification version (default: v1.0.0)
  -r, --report-type       Format: json, human, markdown (default: human)
  -o, --output            Output file path (optional)
  -v, --verbose           Verbose output
  -h, --help              Show help

Examples:
  # Basic analysis
  ethos -p ./my_app

  # JSON output to file
  ethos -p ./my_app -r json -o report.json

  # Markdown report
  ethos -p ./my_app -r markdown -o report.md

  # Verbose mode
  ethos -p ./my_app -v

  # Help
  ethos -h
```

## WCAG 2.2 Rules

### 1. Semantic Labels (WCAG 1.3.1)

All interactive widgets must have semantic labels for screen readers.

```dart
// ✅ PASS
Semantics(
  label: 'Submit button',
  child: GestureDetector(
    onTap: () {},
    child: Text('Submit')
  )
)

// ❌ FAIL
GestureDetector(
  onTap: () {},
  child: Text('Submit')
)
```

**Target Coverage:** 100%  
**Critical Threshold:** 80%

### 2. Color Contrast (WCAG 1.4.3)

Text must have sufficient color contrast (4.5:1 for normal text).

```dart
// ✅ PASS - Good contrast
Text(
  'Hello',
  style: TextStyle(color: Colors.black87)
)

// ❌ FAIL - Low contrast
Text(
  'Hello',
  style: TextStyle(color: Colors.grey)
)
```

**Target Coverage:** 100%  
**Critical Threshold:** 90%

### 3. Touch Target Size (WCAG 2.5.5)

Interactive elements must be at least 48x48 logical pixels (Material Design 3).

```dart
// ✅ PASS - Material button (auto 48x48)
ElevatedButton(
  onPressed: () {},
  child: Text('Click')
)

// ✅ PASS - Custom size
SizedBox(
  width: 48,
  height: 48,
  child: GestureDetector(onTap: () {})
)

// ❌ FAIL - Too small
GestureDetector(
  onTap: () {},
  child: SizedBox(width: 32, height: 32)
)
```

**Target Coverage:** 100%  
**Critical Threshold:** 90%

### 4. Keyboard Navigation (WCAG 2.1.1)

All functionality must be operable via keyboard.

```dart
// ✅ PASS - Built-in keyboard support
ElevatedButton(
  onPressed: () {},
  child: Text('Submit')
)

// ❌ FAIL - No keyboard support
GestureDetector(
  onTap: () {},
  child: Container()
)
```

**Target Coverage:** 100%  
**Critical Threshold:** 95%

### 5. Focus Order (WCAG 2.4.3)

Focus must be visible and managed logically.

```dart
// ✅ PASS - Logical focus order
Form(
  child: Column(
    children: [
      TextField(autofocus: true),
      TextField(),
      ElevatedButton(onPressed: () {})
    ]
  )
)
```

**Target Coverage:** 95%  
**Critical Threshold:** 80%

## Compliance Levels

| Level | Coverage | Description |
|-------|----------|-------------|
| **AAA** | ≥ 95% | Enhanced accessibility |
| **AA** | ≥ 85% | Strong accessibility (most organizations target this) |
| **A** | ≥ 70% | Basic accessibility |
| **NONE** | < 70% | Does not meet minimum standards |

## Specifications

Rules are defined in `specs/v1.0.0/wcag_2_2.yaml`:

```yaml
spec:
  version: "1.0.0"
  wcag_version: "2.2"
  wcag_level: "AA"

rules:
  - rule_id: "wcag_1_3_1_semantics_label"
    title: "Semantic Labels on Interactive Widgets"
    coverage_metric:
      target: 100
      critical_threshold: 80
    test_cases:
      - name: "GestureDetector with Semantics"
        expected_result: "PASS"
      - name: "GestureDetector without Semantics"
        expected_result: "FAIL"
```

## Testing

```bash
# Run all tests
dart test

# Run specific test file
dart test test/spec_compliance_test.dart -v

# Run single test
dart test -n "Spec loads successfully"

# With coverage
dart test --coverage=coverage
```

## Architecture

```
ethos/
├── lib/
│   ├── ethos.dart                    # Main exports
│   └── src/
│       ├── models/
│       │   ├── spec.dart             # Specification models
│       │   └── coverage_report.dart  # Report models
│       └── analyzer/
│           ├── spec_loader.dart      # YAML loader
│           └── coverage_analyzer.dart # Analysis engine
├── bin/
│   └── analyze.dart                  # CLI tool
├── specs/v1.0.0/
│   └── wcag_2_2.yaml                # WCAG 2.2 specs
├── example/
│   └── main.dart                     # Usage examples
└── test/
    └── spec_compliance_test.dart    # Tests
```

## Extending with New Rules

Add a rule to `specs/v1.0.0/wcag_2_2.yaml`:

```yaml
rules:
  - rule_id: "wcag_3_2_1_on_focus"
    category: "predictability"
    severity: "high"
    wcag_criterion: "3.2.1"
    wcag_level: "A"
    title: "On Focus"
    description: "Components must not cause unexpected context changes on focus"
    
    coverage_metric:
      id: "on_focus_coverage"
      formula: "(compliant_components / total_components) * 100"
      target: 100
      critical_threshold: 90
    
    test_cases:
      - name: "Focus without unexpected change"
        expected_result: "PASS"
      - name: "Focus causes navigation"
        expected_result: "FAIL"
    
    how_to_fix: "Avoid triggering actions on focus events"
    references:
      wcag: "https://www.w3.org/WAI/WCAG21/Understanding/on-focus"
```

Then implement detection in `lib/src/analyzer/coverage_analyzer.dart`:

```dart
(int matched, int total) _analyzeOnFocus(String code) {
  // Your analysis implementation
  return (matched, total);
}
```

## Limitations (MVP)

- Pattern matching via regex (not full AST parsing)
- No runtime analysis (static code analysis only)
- Limited widget pattern detection
- No actual color contrast calculation (pattern-based only)

## Roadmap

### v0.2.0
- Improved AST parsing using `analyzer` package
- Real color contrast calculation
- Precise touch target size measurement
- Runtime overlay widget


## Contributing

Contributions welcome! Areas for improvement:

- Better Dart AST parsing
- More comprehensive rule implementations
- Additional WCAG 2.2 rules
- Performance optimizations
- CI/CD integration examples
- Language translations

## License

MIT License - see [LICENSE](LICENSE) file

## Author

[@gearscrafter](https://github.com/gearscrafter)
Mobile Developer

## Resources

- [WCAG 2.2 Guidelines](https://www.w3.org/WAI/WCAG22/quickref/)
- [Flutter Accessibility](https://docs.flutter.dev/ui/accessibility)
- [Material Design 3](https://m3.material.io/)
- [WebAIM Contrast Checker](https://webaim.org/resources/contrastchecker/)


## Support

Found a bug? Have a feature request?

Open an issue on [GitHub](https://github.com/gearscrafter/ethos/issues)

---

**Made with ❤️ for inclusive Flutter apps**