import 'package:test/test.dart';
import 'package:ethos/ethos.dart';

/// These tests use the test_cases that live in the YAML spec as fixtures.
/// This is the SDD payoff: the spec defines PASS/FAIL examples, and the
/// detector is validated against the same examples that users will read
/// in the YAML.
void main() {
  group('SemanticLabelsDetector', () {
    final detector = SemanticLabelsDetector();
    final rule = _fakeRule();

    test('GestureDetector wrapped in Semantics(label: literal) → PASS', () {
      const code = '''
        import 'package:flutter/material.dart';
        Widget build() => Semantics(
          label: 'Submit button',
          child: GestureDetector(
            onTap: () {},
            child: Text('Submit'),
          ),
        );
      ''';
      final result = _run(detector, rule, code);
      expect(result.total, 1);
      expect(result.matched, 1);
      expect(result.indeterminate, 0);
    });

    test('GestureDetector without Semantics → FAIL', () {
      const code = '''
        Widget build() => GestureDetector(
          onTap: () {},
          child: Text('Submit'),
        );
      ''';
      final result = _run(detector, rule, code);
      expect(result.total, 1);
      expect(result.matched, 0);
      expect(result.findings, hasLength(1));
      expect(result.findings.first.severity, FindingSeverity.fail);
    });

    test('ElevatedButton is NOT in scope (built-in semantics)', () {
      const code = '''
        Widget build() => ElevatedButton(
          onPressed: () {},
          child: Text('Submit'),
        );
      ''';
      final result = _run(detector, rule, code);
      expect(result.total, 0,
          reason: 'ElevatedButton must not be counted by this rule');
    });

    test('Semantics + GestureDetector in DIFFERENT subtrees → FAIL', () {
      // This is the regression the AST migration fixes: the old regex-based
      // detector counted these as a match because both strings appeared
      // in the same file.
      const code = '''
        Widget build() => Column(children: [
          Semantics(label: 'Other thing', child: Icon(Icons.info)),
          GestureDetector(onTap: () {}, child: Text('Submit')),
        ]);
      ''';
      final result = _run(detector, rule, code);
      expect(result.total, 1);
      expect(result.matched, 0,
          reason: 'Semantics is a sibling, not an ancestor of GestureDetector');
    });

    test('Semantics(label: variable) → indeterminate', () {
      const code = '''
        Widget build(String dynamicLabel) => Semantics(
          label: dynamicLabel,
          child: GestureDetector(onTap: () {}, child: Text('Submit')),
        );
      ''';
      final result = _run(detector, rule, code);
      expect(result.indeterminate, 1);
      expect(result.total, 0,
          reason: 'indeterminados no entran al denominador');
    });

    test('Semantics(label: "") → FAIL (empty label)', () {
      const code = '''
        Widget build() => Semantics(
          label: '',
          child: GestureDetector(onTap: () {}, child: Text('Submit')),
        );
      ''';
      final result = _run(detector, rule, code);
      expect(result.matched, 0);
      expect(result.total, 1);
    });

    test('InkWell and InkResponse are also in scope', () {
      const code = '''
        Widget build() => Column(children: [
          InkWell(onTap: () {}, child: Text('a')),
          InkResponse(onTap: () {}, child: Text('b')),
        ]);
      ''';
      final result = _run(detector, rule, code);
      expect(result.total, 2);
      expect(result.matched, 0);
    });

    test('GestureDetector with excludeFromSemantics: true → not counted', () {
      const code = '''
        Widget build() => GestureDetector(
          excludeFromSemantics: true,
          onTap: () {},
          child: Text('press effect'),
        );
      ''';
      final result = _run(detector, rule, code);
      expect(result.total, 0,
          reason: 'developer opted out via excludeFromSemantics');
      expect(result.findings, isEmpty);
    });

    test('GestureDetector with only drag gestures → not counted', () {
      const code = '''
        Widget build() => GestureDetector(
          onVerticalDragUpdate: (_) {},
          onPanUpdate: (_) {},
          child: Container(),
        );
      ''';
      final result = _run(detector, rule, code);
      expect(result.total, 0,
          reason: 'drag-only gesture is a 2.1.1 concern, not 1.3.1');
    });

    test('GestureDetector with tap AND drag → counted (has tap)', () {
      const code = '''
        Widget build() => GestureDetector(
          onTap: () {},
          onPanUpdate: (_) {},
          child: Container(),
        );
      ''';
      final result = _run(detector, rule, code);
      expect(result.total, 1,
          reason: 'a tap gesture makes it a button regardless of drag');
      expect(result.matched, 0);
    });

    test('excludeFromSemantics: false → still counted', () {
      const code = '''
        Widget build() => GestureDetector(
          excludeFromSemantics: false,
          onTap: () {},
          child: Text('x'),
        );
      ''';
      final result = _run(detector, rule, code);
      // onTap: () {} is now treated as non-interactive (empty body),
      // so it's skipped regardless of excludeFromSemantics.
      expect(result.total, 0);
    });

    test('Semantics as DESCENDANT (child) → PASS', () {
      // Wonderous range_selector pattern: GestureDetector wraps Semantics.
      const code = '''
        Widget build() => GestureDetector(
          onTap: () => doSomething(),
          child: Semantics(
            label: 'Adjust time range',
            child: Container(),
          ),
        );
      ''';
      final result = _run(detector, rule, code);
      expect(result.total, 1);
      expect(result.matched, 1,
          reason: 'Semantics in the child subtree counts');
    });

    test('Semantics descendant with runtime label → indeterminate', () {
      const code = '''
        Widget build() => GestureDetector(
          onTap: () => doSomething(),
          child: Semantics(
            label: someStrings.rangeLabel,
            child: Container(),
          ),
        );
      ''';
      final result = _run(detector, rule, code);
      expect(result.indeterminate, 1);
    });

    test('onTap: () {} (empty, block-parent) → not counted', () {
      const code = '''
        Widget build() => GestureDetector(
          onTap: () {},
          child: Container(),
        );
      ''';
      final result = _run(detector, rule, code);
      expect(result.total, 0,
          reason: 'empty tap handler is not a real control');
    });

    test('onTap: unfocus (tap-to-dismiss) → not counted', () {
      const code = '''
        Widget build() => GestureDetector(
          onTap: FocusManager.instance.primaryFocus?.unfocus,
          child: Column(),
        );
      ''';
      final result = _run(detector, rule, code);
      expect(result.total, 0,
          reason: 'tap-to-dismiss keyboard has nothing to announce');
    });

    test('descendant Semantics does not leak across nested interactive', () {
      // The inner GestureDetector should NOT borrow the outer one's
      // descendant Semantics — each is evaluated independently.
      const code = '''
        Widget build() => GestureDetector(
          onTap: () => outer(),
          child: GestureDetector(
            onTap: () => inner(),
            child: Semantics(label: 'inner label', child: Container()),
          ),
        );
      ''';
      final result = _run(detector, rule, code);
      // Inner: PASS (has descendant Semantics).
      // Outer: its nearest descendant Semantics is blocked by the inner
      // interactive widget → FAIL.
      expect(result.total, 2);
      expect(result.matched, 1, reason: 'only the inner one is labelled');
    });
  });
}

DetectionResult _run(RuleDetector detector, Rule rule, String source) {
  final file = parseDartFile('test.dart', source);
  return detector.analyze(rule: rule, files: [file]);
}

/// Builds a minimal Rule for tests; only the fields the detector reads
/// need real values.
Rule _fakeRule() => Rule(
      ruleId: 'wcag_1_3_1_semantics_label',
      category: 'semantics',
      severity: 'critical',
      wcagCriterion: '1.3.1',
      wcagLevel: 'A',
      title: 'Semantic Labels',
      description: '',
      appliesToWidgets: const [],
      excludesWidgets: const [],
      coverageMetric: CoverageMetric(
        id: 'semantic_label_coverage',
        formula: '',
        unit: 'percentage',
        target: 100,
        criticalThreshold: 80,
      ),
      testCases: const [],
      howToFix: '',
      references: const {},
    );