import 'package:test/test.dart';
import 'package:ethos/ethos.dart';

void main() {
  group('KeyboardDetector', () {
    final detector = KeyboardDetector();
    final rule = _fakeRule();

    test('ElevatedButton → keyboard-ready PASS', () {
      const code =
          "Widget build() => ElevatedButton(onPressed: () {}, child: Text('x'));";
      final result = _run(detector, rule, code);
      expect(result.total, 1);
      expect(result.matched, 1);
    });

    test('TextField → keyboard-ready PASS', () {
      const code = 'Widget build() => TextField();';
      final result = _run(detector, rule, code);
      expect(result.matched, 1);
    });

    test('GestureDetector with onTap, no keyboard path → FAIL', () {
      const code =
          "Widget build() => GestureDetector(onTap: () {}, child: Text('x'));";
      final result = _run(detector, rule, code);
      expect(result.total, 1);
      expect(result.matched, 0);
      expect(result.findings, hasLength(1));
    });

    test('GestureDetector under Focus → PASS', () {
      const code = '''
        Widget build() => Focus(
          child: GestureDetector(onTap: () {}, child: Text('x')),
        );
      ''';
      final result = _run(detector, rule, code);
      expect(result.total, 1);
      expect(result.matched, 1);
    });

    test('GestureDetector under KeyboardListener → PASS', () {
      const code = '''
        Widget build() => KeyboardListener(
          focusNode: node,
          child: GestureDetector(onTap: () {}, child: Text('x')),
        );
      ''';
      final result = _run(detector, rule, code);
      expect(result.matched, 1);
    });

    test('drag-only GestureDetector → not counted', () {
      const code =
          'Widget build() => GestureDetector(onPanUpdate: (_) {}, child: Container());';
      final result = _run(detector, rule, code);
      expect(result.total, 0);
    });
  });
}

DetectionResult _run(RuleDetector detector, Rule rule, String source) {
  final file = parseDartFile('test.dart', source);
  return detector.analyze(rule: rule, files: [file]);
}

Rule _fakeRule() => Rule(
      ruleId: 'wcag_2_1_1_keyboard',
      category: 'keyboard_navigation',
      severity: 'critical',
      wcagCriterion: '2.1.1',
      wcagLevel: 'A',
      title: 'Keyboard Accessibility',
      description: '',
      appliesToWidgets: const [],
      excludesWidgets: const [],
      coverageMetric: CoverageMetric(
        id: 'keyboard_navigation_coverage',
        formula: '',
        unit: 'percentage',
        target: 100,
        criticalThreshold: 95,
      ),
      testCases: const [],
      howToFix: '',
      references: const {},
    );
