import 'package:test/test.dart';
import 'package:ethos/ethos.dart';

void main() {
  group('Spec Compliance Tests', () {
    late CoverageAnalyzer analyzer;

    setUpAll(() async {
      analyzer =
          await CoverageAnalyzer.loadFromFile('specs/v1.0.0/wcag_2_2.yaml');
    });

    test('Spec loads successfully', () {
      expect(analyzer.spec, isNotNull);
      expect(analyzer.spec.version, equals('1.0.0'));
    });

    test('Spec has correct WCAG version', () {
      expect(analyzer.spec.wcagVersion, equals('2.2'));
      expect(analyzer.spec.wcagLevel, equals('AA'));
    });

    test('Spec has minimum 5 rules', () {
      expect(analyzer.spec.rules.length, greaterThanOrEqualTo(5));
    });

    test('All rules have required fields', () {
      for (final rule in analyzer.spec.rules.values) {
        expect(rule.ruleId, isNotEmpty, reason: 'Rule ID cannot be empty');
        expect(rule.title, isNotEmpty, reason: 'Rule title cannot be empty');
        expect(rule.wcagCriterion, isNotEmpty,
            reason: 'WCAG criterion cannot be empty');
        expect(rule.coverageMetric, isNotNull,
            reason: 'Coverage metric is required');
      }
    });

    test('All rules have test cases', () {
      for (final rule in analyzer.spec.rules.values) {
        expect(rule.testCases, isNotEmpty,
            reason: 'Rule ${rule.ruleId} must have test cases');
      }
    });

    test('All test cases have valid expected results', () {
      for (final rule in analyzer.spec.rules.values) {
        for (final testCase in rule.testCases) {
          expect(['PASS', 'FAIL'].contains(testCase.expectedResult), true,
              reason: 'Rule ${rule.ruleId}, test "${testCase.name}" '
                  'has invalid expected result: ${testCase.expectedResult}');
        }
      }
    });

    test('All rules have proper severity levels', () {
      final validSeverities = {'critical', 'high', 'medium', 'low'};
      for (final rule in analyzer.spec.rules.values) {
        expect(validSeverities.contains(rule.severity), true,
            reason:
                'Rule ${rule.ruleId} has invalid severity: ${rule.severity}');
      }
    });

    test('All rules have references', () {
      for (final rule in analyzer.spec.rules.values) {
        expect(rule.references, isNotEmpty,
            reason: 'Rule ${rule.ruleId} must have references');
      }
    });

    test('Coverage metrics have valid targets', () {
      for (final rule in analyzer.spec.rules.values) {
        expect(
            rule.coverageMetric.target,
            allOf(
              greaterThanOrEqualTo(0),
              lessThanOrEqualTo(100),
            ),
            reason: 'Rule ${rule.ruleId} target must be between 0-100');
      }
    });

    test('Critical thresholds are less than targets', () {
      for (final rule in analyzer.spec.rules.values) {
        expect(rule.coverageMetric.criticalThreshold,
            lessThanOrEqualTo(rule.coverageMetric.target),
            reason:
                'Rule ${rule.ruleId}: critical threshold must be <= target');
      }
    });

    test('Semantic labels rule is defined', () {
      expect(
          analyzer.spec.rules.containsKey('wcag_1_3_1_semantics_label'), true,
          reason: 'Semantic labels rule (WCAG 1.3.1) must be defined');
    });

    test('Contrast rule is defined', () {
      expect(
          analyzer.spec.rules.containsKey('wcag_1_4_3_contrast_minimum'), true,
          reason: 'Contrast rule (WCAG 1.4.3) must be defined');
    });

    test('Touch target rule is defined', () {
      expect(analyzer.spec.rules.containsKey('wcag_2_5_5_target_size_enhanced'),
          true,
          reason: 'Touch target rule (WCAG 2.5.5) must be defined');
    });

    test('Keyboard navigation rule is defined', () {
      expect(analyzer.spec.rules.containsKey('wcag_2_1_1_keyboard'), true,
          reason: 'Keyboard navigation rule (WCAG 2.1.1) must be defined');
    });

    test('Focus order rule is defined', () {
      expect(analyzer.spec.rules.containsKey('wcag_2_4_3_focus_order'), true,
          reason: 'Focus order rule (WCAG 2.4.3) must be defined');
    });

    test('Compliance levels are defined', () {
      expect(analyzer.spec.complianceLevels, isNotEmpty);
      expect(analyzer.spec.complianceLevels.keys,
          containsAll(['level_a', 'level_aa', 'level_aaa']));
    });

    test('Each compliance level has required rules', () {
      for (final level in analyzer.spec.complianceLevels.values) {
        expect(level.requiredRules, isNotEmpty,
            reason: 'Compliance level ${level.name} must have required rules');
      }
    });

    test('Release date is valid', () {
      expect(analyzer.spec.releaseDate, isNotNull,
          reason: 'Spec must have a valid release date');
      expect(analyzer.spec.releaseDate.isBefore(DateTime.now()), true,
          reason: 'Release date cannot be in the future');
    });
  });

  group('CoverageAnalyzer Tests', () {
    late CoverageAnalyzer analyzer;

    setUpAll(() async {
      analyzer =
          await CoverageAnalyzer.loadFromFile('specs/v1.0.0/wcag_2_2.yaml');
    });

    test('Analyzer initializes without errors', () {
      expect(analyzer, isNotNull);
      expect(analyzer.spec, isNotNull);
    });

    test('Analyzer can analyze current project', () async {
      final report = await analyzer.analyze(projectPath: '.');
      expect(report, isNotNull);
      expect(report.coverage, isNotEmpty);
    });

    test('Report has correct structure', () async {
      final report = await analyzer.analyze(projectPath: '.');

      expect(report.specVersion, isNotEmpty);
      expect(report.projectPath, isNotEmpty);
      expect(report.timestamp, isNotNull);
      expect(report.coverage, isMap);
    });

    test('Report calculates overall coverage', () async {
      final report = await analyzer.analyze(projectPath: '.');
      report.calculateOverall();

      expect(report.overallCoverage, greaterThanOrEqualTo(0));
      expect(report.overallCoverage, lessThanOrEqualTo(100));
    });

    test('Report determines compliance level', () async {
      final report = await analyzer.analyze(projectPath: '.');
      report.calculateOverall();
      report.determineComplianceLevel();

      expect(['A', 'AA', 'AAA', 'NONE'].contains(report.complianceLevel), true,
          reason: 'Compliance level must be A, AA, AAA, or NONE');
    });

    test('Report can be converted to JSON', () async {
      final report = await analyzer.analyze(projectPath: '.');
      report.calculateOverall();
      report.determineComplianceLevel();

      final json = report.toJson();
      expect(json, isMap);
      expect(
          json.keys,
          containsAll([
            'spec_version',
            'project_path',
            'timestamp',
            'overall_coverage',
            'compliance_level',
            'coverage_by_rule',
          ]));
    });
  });
}
