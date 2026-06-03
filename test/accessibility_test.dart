import 'package:test/test.dart';
import 'package:ethos/ethos_test.dart';

/// Example test file showing how to use Ethos matchers in a test suite.
///
/// Copy this file into your Flutter project's `test/` directory and adjust
/// the project path and thresholds to match your requirements.
///
/// Run with:
///   dart test test/accessibility_test.dart
void main() {
  group('Accessibility coverage — example/fixtures', () {
    late CoverageReport report;

    setUpAll(() async {
      report = await EthosTestHelper.analyzeProject('example/fixtures');
    });

    test('has a defined compliance level', () {
      expect(report.complianceLevel, isNotNull);
      expect(report.complianceLevel, isNotEmpty);
    });

    test('semantic labels has some coverage data', () {
      final coverage = report.coverage['wcag_1_3_1_semantics_label'];
      expect(coverage, isNotNull);
      expect(coverage!.total, greaterThan(0));
    });

    test('touch target rule has coverage data', () {
      final coverage = report.coverage['wcag_2_5_5_target_size_enhanced'];
      expect(coverage, isNotNull);
      // SizedBox 48x48 passes, SizedBox 32x32 fails.
      expect(coverage!.total, greaterThan(0));
    });

    test('high contrast text passes', () {
      final coverage = report.coverage['wcag_1_4_3_contrast_minimum'];
      expect(coverage, isNotNull);
      expect(coverage!.matched, greaterThan(0));
    });

    test('low contrast text produces findings', () {
      final coverage = report.coverage['wcag_1_4_3_contrast_minimum'];
      expect(coverage, isNotNull);
      expect(coverage!.findings, isNotEmpty);
    });

    test('overall coverage is below 70% (fixtures have intentional issues)',
        () {
      expect(report.overallCoverage, lessThan(70));
    });

    test('overall coverage is above 0% (fixtures have some passing widgets)',
        () {
      expect(report.overallCoverage, greaterThan(0));
    });
  });

  test('GestureDetector with Semantics ancestor passes', () async {
    final report = await EthosTestHelper.analyzeSource('''
        Semantics(
          label: 'Open profile',
          child: GestureDetector(
            onTap: () => print('tap'),
            child: Icon(Icons.person),
          ),
        )
      ''');
    expect(report, passesRule('wcag_1_3_1_semantics_label'));
  });

  test('GestureDetector without Semantics fails', () async {
    final report = await EthosTestHelper.analyzeSource('''
        GestureDetector(
          onTap: () => print('tap'),
          child: Icon(Icons.person),
        )
      ''');
    final coverage = report.coverage['wcag_1_3_1_semantics_label'];
    expect(coverage, isNotNull);
    expect(coverage!.findings, isNotEmpty);
  });

  group('NonTextContentDetector', () {
    test('Icon with semanticLabel passes', () async {
      final report = await EthosTestHelper.analyzeSource(
        "Icon(Icons.search, semanticLabel: 'Search')",
      );
      final coverage = report.coverage['wcag_1_1_1_non_text_content'];
      expect(coverage, isNotNull);
      expect(coverage!.matched, greaterThan(0));
      expect(coverage.findings, isEmpty);
    });

    test('Icon without semanticLabel fails', () async {
      final report = await EthosTestHelper.analyzeSource(
        'Icon(Icons.close)',
      );
      final coverage = report.coverage['wcag_1_1_1_non_text_content'];
      expect(coverage, isNotNull);
      expect(coverage!.findings, isNotEmpty);
    });
  });

  group('ResizeTextDetector', () {
    test('Text without textScaleFactor has no data (correct)', () async {
      final report = await EthosTestHelper.analyzeSource(
        "Text('Hello', style: TextStyle(fontSize: 16))",
      );
      final coverage = report.coverage['wcag_1_4_4_resize_text'];
      expect(coverage?.total, equals(0));
    });

    test('Text with hardcoded textScaleFactor is flagged', () async {
      final report = await EthosTestHelper.analyzeSource(
        "Text('Hello', textScaleFactor: 1.0)",
      );
      final coverage = report.coverage['wcag_1_4_4_resize_text'];
      expect(coverage, isNotNull);
      expect(coverage!.findings, isNotEmpty);
    });
  });
}
