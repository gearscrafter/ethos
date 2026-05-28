import 'package:test/test.dart';
import 'package:ethos/ethos.dart';

void main() {
  group('ColorResolver.contrastRatio', () {
    test('black on white = 21:1 (max)', () {
      final r = ColorResolver.contrastRatio(0xFF000000, 0xFFFFFFFF);
      expect(r, closeTo(21.0, 0.01));
    });

    test('white on white = 1:1 (min)', () {
      final r = ColorResolver.contrastRatio(0xFFFFFFFF, 0xFFFFFFFF);
      expect(r, closeTo(1.0, 0.01));
    });

    test('known mid-contrast pair (#767676 on white ~= 4.54)', () {
      final r = ColorResolver.contrastRatio(0xFF767676, 0xFFFFFFFF);
      expect(r, closeTo(4.54, 0.05));
    });

    test('ratio is symmetric', () {
      final a = ColorResolver.contrastRatio(0xFF123456, 0xFFFEDCBA);
      final b = ColorResolver.contrastRatio(0xFFFEDCBA, 0xFF123456);
      expect(a, closeTo(b, 0.0001));
    });
  });

  group('ContrastDetector', () {
    final detector = ContrastDetector();
    final rule = _fakeRule();

    test('black text on white bg → PASS', () {
      const code = '''
        Widget build() => Text('Hi', style: TextStyle(
          color: Color(0xFF000000),
          backgroundColor: Color(0xFFFFFFFF),
        ));
      ''';
      final result = _run(detector, rule, code);
      expect(result.total, 1);
      expect(result.matched, 1);
    });

    test('light grey text on white bg → FAIL', () {
      const code = '''
        Widget build() => Text('Hi', style: TextStyle(
          color: Color(0xFFCCCCCC),
          backgroundColor: Color(0xFFFFFFFF),
        ));
      ''';
      final result = _run(detector, rule, code);
      expect(result.total, 1);
      expect(result.matched, 0);
      expect(result.findings, hasLength(1));
    });

    test('Colors.* constants resolve', () {
      const code = '''
        Widget build() => Text('Hi', style: TextStyle(
          color: Colors.black,
          backgroundColor: Colors.white,
        ));
      ''';
      final result = _run(detector, rule, code);
      expect(result.matched, 1);
    });

    test('large font relaxes threshold to 3:1', () {
      // #8C8C8C on white ≈ 3.5:1 — fails normal (4.5) but passes large (3.0).
      const code = '''
        Widget build() => Text('Hi', style: TextStyle(
          color: Color(0xFF8C8C8C),
          backgroundColor: Color(0xFFFFFFFF),
          fontSize: 24.0,
        ));
      ''';
      final result = _run(detector, rule, code);
      expect(result.matched, 1, reason: 'large text uses 3:1');
    });

    test('same mid-grey at normal size → FAIL', () {
      const code = '''
        Widget build() => Text('Hi', style: TextStyle(
          color: Color(0xFF8C8C8C),
          backgroundColor: Color(0xFFFFFFFF),
        ));
      ''';
      final result = _run(detector, rule, code);
      expect(result.matched, 0, reason: 'normal text needs 4.5:1');
    });

    test('Text without style → indeterminate', () {
      const code = "Widget build() => Text('Hi');";
      final result = _run(detector, rule, code);
      expect(result.total, 0);
      expect(result.indeterminate, 1);
    });

    test('style from theme → indeterminate', () {
      const code =
          "Widget build() => Text('Hi', style: theme.textTheme.bodyLarge);";
      final result = _run(detector, rule, code);
      expect(result.total, 0);
      expect(result.indeterminate, 1);
    });

    test('color literal but no background → indeterminate', () {
      const code = '''
        Widget build() => Text('Hi', style: TextStyle(
          color: Color(0xFF000000),
        ));
      ''';
      final result = _run(detector, rule, code);
      expect(result.total, 0,
          reason: 'cannot verify contrast without the background');
      expect(result.indeterminate, 1);
    });

    test('color from \$styles → indeterminate', () {
      const code = '''
        Widget build() => Text('Hi', style: TextStyle(
          color: someStyles.colors.offWhite,
          backgroundColor: Color(0xFF000000),
        ));
      ''';
      final result = _run(detector, rule, code);
      expect(result.total, 0);
      expect(result.indeterminate, 1);
    });
  });
}

DetectionResult _run(RuleDetector detector, Rule rule, String source) {
  final file = parseDartFile('test.dart', source);
  return detector.analyze(rule: rule, files: [file]);
}

Rule _fakeRule() => Rule(
      ruleId: 'wcag_1_4_3_contrast_minimum',
      category: 'contrast',
      severity: 'high',
      wcagCriterion: '1.4.3',
      wcagLevel: 'AA',
      title: 'Minimum Color Contrast',
      description: '',
      appliesToWidgets: const [],
      excludesWidgets: const [],
      coverageMetric: CoverageMetric(
        id: 'contrast_coverage',
        formula: '',
        unit: 'percentage',
        target: 100,
        criticalThreshold: 90,
      ),
      testCases: const [],
      howToFix: '',
      references: const {},
    );