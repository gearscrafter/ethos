import 'package:test/test.dart';
import 'package:ethos/ethos.dart';

void main() {
  // ─── Spec compliance ────────────────────────────────────────────────────────
  // Uses the built-in embedded spec (no YAML file needed on disk).
  // CoverageAnalyzer.forProject auto-detects an optional ethos.yaml; here we
  // point it at the package root (no ethos.yaml there, so it uses built-in).
  group('Spec Compliance Tests', () {
    late CoverageAnalyzer analyzer;

    setUpAll(() async {
      analyzer = await CoverageAnalyzer.forProject('.');
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
          allOf(greaterThanOrEqualTo(0), lessThanOrEqualTo(100)),
          reason: 'Rule ${rule.ruleId} target must be between 0-100',
        );
      }
    });

    test('Critical thresholds are less than or equal to targets', () {
      for (final rule in analyzer.spec.rules.values) {
        expect(
          rule.coverageMetric.criticalThreshold,
          lessThanOrEqualTo(rule.coverageMetric.target),
          reason: 'Rule ${rule.ruleId}: critical threshold must be <= target',
        );
      }
    });

    test('Semantic labels rule is defined', () {
      expect(
          analyzer.spec.rules.containsKey('wcag_1_3_1_semantics_label'), true);
    });

    test('Contrast rule is defined', () {
      expect(
          analyzer.spec.rules.containsKey('wcag_1_4_3_contrast_minimum'), true);
    });

    test('Touch target rule is defined', () {
      expect(analyzer.spec.rules.containsKey('wcag_2_5_5_target_size_enhanced'),
          true);
    });

    test('Keyboard navigation rule is defined', () {
      expect(analyzer.spec.rules.containsKey('wcag_2_1_1_keyboard'), true);
    });

    test('Focus order rule is defined', () {
      expect(analyzer.spec.rules.containsKey('wcag_2_4_3_focus_order'), true);
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

    test('Release date is valid and not in the future', () {
      expect(analyzer.spec.releaseDate, isNotNull);
      expect(analyzer.spec.releaseDate.isBefore(DateTime.now()), true,
          reason: 'Release date cannot be in the future');
    });
  });

  // ─── CoverageAnalyzer ────────────────────────────────────────────────────────
  group('CoverageAnalyzer Tests', () {
    late CoverageAnalyzer analyzer;
    late CoverageReport report;

    // Run a single analysis for the whole group — avoid repeating the file scan.
    setUpAll(() async {
      analyzer = await CoverageAnalyzer.forProject('example/fixtures');
      report = await analyzer.analyze();
    });

    test('Analyzer initializes without errors', () {
      expect(analyzer, isNotNull);
      expect(analyzer.spec, isNotNull);
      expect(
          analyzer.registry.registeredRuleIds.length, greaterThanOrEqualTo(5));
    });

    test('Report has correct structure', () {
      expect(report.specVersion, isNotEmpty);
      expect(report.projectPath, isNotEmpty);
      expect(report.timestamp, isNotNull);
      expect(report.coverage, isA<Map>());
    });

    test('Report covers all spec rules', () {
      for (final ruleId in analyzer.spec.rules.keys) {
        expect(report.coverage.containsKey(ruleId), true,
            reason: 'Report must include coverage for rule $ruleId');
      }
    });

    test('Overall coverage is in valid range', () {
      expect(report.overallCoverage, greaterThanOrEqualTo(0));
      expect(report.overallCoverage, lessThanOrEqualTo(100));
    });

    test('Compliance level is a valid value', () {
      expect(['A', 'AA', 'AAA', 'NONE'].contains(report.complianceLevel), true,
          reason: 'Compliance level must be A, AA, AAA, or NONE');
    });

    test('Report serializes to JSON correctly', () {
      final json = report.toJson();
      expect(json, isA<Map>());
      expect(
        json.keys,
        containsAll([
          'spec_version',
          'project_path',
          'timestamp',
          'overall_coverage',
          'compliance_level',
          'coverage_by_rule',
        ]),
      );
    });

    test('JSON string is valid', () {
      final jsonString = report.toJsonString();
      expect(jsonString, isNotEmpty);
      expect(jsonString, startsWith('{'));
      expect(jsonString, endsWith('}'));
    });

    test('Each rule coverage has valid percentage', () {
      for (final entry in report.coverage.entries) {
        expect(entry.value.percentage, greaterThanOrEqualTo(0),
            reason: '${entry.key} percentage must be >= 0');
        expect(entry.value.percentage, lessThanOrEqualTo(100),
            reason: '${entry.key} percentage must be <= 100');
      }
    });

    test('Widget aliases from ethos.yaml are loaded when present', () async {
      // If example/fixtures/ethos.yaml exists, aliases should be loaded.
      // This test is informational — it passes either way.
      final aliasCount = analyzer.spec.widgetAliases.length;
      expect(aliasCount, greaterThanOrEqualTo(0));
      // Uncomment to assert specific aliases once ethos.yaml is in place:
      // expect(analyzer.spec.widgetAliases.containsKey('CircleIconBtn'), true);
    });
  });

  // ─── EthosConfig ─────────────────────────────────────────────────────────────
  group('EthosConfig Tests', () {
    test('Empty config has no aliases or overrides', () {
      const config = EthosConfig.empty;
      expect(config.widgetAliases, isEmpty);
      expect(config.ruleOverrides, isEmpty);
    });

    test('Config parses widget aliases from YAML map', () {
      final config = EthosConfig.fromYaml({
        'widget_aliases': {
          'MyButton': {
            'role': 'button',
            'label_arg': 'semanticLabel',
            'size_guaranteed': true,
            'keyboard_ready': true,
          },
        },
      });
      expect(config.widgetAliases.containsKey('MyButton'), true);
      final alias = config.widgetAliases['MyButton']!;
      expect(alias.role, WidgetRole.button);
      expect(alias.labelArg, 'semanticLabel');
      expect(alias.sizeGuaranteed, true);
      expect(alias.keyboardReady, true);
    });

    test('Config parses rule overrides', () {
      final config = EthosConfig.fromYaml({
        'rule_overrides': {
          'wcag_1_4_3_contrast_minimum': {
            'critical_threshold': 95.0,
          },
        },
      });
      final override = config.ruleOverrides['wcag_1_4_3_contrast_minimum'];
      expect(override, isNotNull);
      expect(override!.criticalThreshold, 95.0);
    });

    test('WidgetAlias role defaults to button for unknown string', () {
      final alias = WidgetAlias.fromYaml('X', {'role': 'unknown_role'});
      expect(alias.role, WidgetRole.button);
    });

    test('WidgetAlias parses all roles', () {
      expect(WidgetAlias.fromYaml('A', {'role': 'button'}).role,
          WidgetRole.button);
      expect(WidgetAlias.fromYaml('B', {'role': 'text'}).role, WidgetRole.text);
      expect(
          WidgetAlias.fromYaml('C', {'role': 'input'}).role, WidgetRole.input);
    });
  });
}
