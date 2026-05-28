import 'package:test/test.dart';
import 'package:ethos/ethos.dart';

void main() {
  group('FocusOrderDetector', () {
    final detector = FocusOrderDetector();
    final rule = _fakeRule();

    test('Form with autofocus → PASS', () {
      const code = '''
        Widget build() => Form(
          child: Column(children: [
            TextField(autofocus: true),
            TextField(),
          ]),
        );
      ''';
      final result = _run(detector, rule, code);
      expect(result.total, 1);
      expect(result.matched, 1);
    });

    test('Form without focus management → FAIL', () {
      const code = '''
        Widget build() => Form(
          child: Column(children: [
            TextField(),
            TextField(),
          ]),
        );
      ''';
      final result = _run(detector, rule, code);
      expect(result.total, 1);
      expect(result.matched, 0);
      expect(result.findings, hasLength(1));
    });

    test('Form with FocusScope → PASS', () {
      const code = '''
        Widget build() => Form(
          child: FocusScope(
            child: Column(children: [TextField(), TextField()]),
          ),
        );
      ''';
      final result = _run(detector, rule, code);
      expect(result.matched, 1);
    });

    test('2+ inputs without Form, no management → FAIL', () {
      const code = '''
        Widget build() => Column(children: [
          TextField(),
          TextField(),
          Checkbox(value: false, onChanged: (_) {}),
        ]);
      ''';
      final result = _run(detector, rule, code);
      expect(result.total, 1);
      expect(result.matched, 0);
    });

    test('single input → not counted (focus order trivial)', () {
      const code = "Widget build() => Column(children: [TextField()]);";
      final result = _run(detector, rule, code);
      expect(result.total, 0);
    });

    test('no inputs → not counted', () {
      const code = "Widget build() => Column(children: [Text('a'), Text('b')]);";
      final result = _run(detector, rule, code);
      expect(result.total, 0);
    });

    test('Form with focusNode argument → PASS', () {
      const code = '''
        Widget build() => Form(
          child: TextField(focusNode: myNode),
        );
      ''';
      final result = _run(detector, rule, code);
      expect(result.matched, 1);
    });
  });
}

DetectionResult _run(RuleDetector detector, Rule rule, String source) {
  final file = parseDartFile('test.dart', source);
  return detector.analyze(rule: rule, files: [file]);
}

Rule _fakeRule() => Rule(
      ruleId: 'wcag_2_4_3_focus_order',
      category: 'focus_management',
      severity: 'high',
      wcagCriterion: '2.4.3',
      wcagLevel: 'A',
      title: 'Focus Order',
      description: '',
      appliesToWidgets: const [],
      excludesWidgets: const [],
      coverageMetric: CoverageMetric(
        id: 'focus_management_coverage',
        formula: '',
        unit: 'percentage',
        target: 95,
        criticalThreshold: 80,
      ),
      testCases: const [],
      howToFix: '',
      references: const {},
    );