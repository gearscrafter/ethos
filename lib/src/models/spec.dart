/// Represents a complete WCAG specification (loaded from YAML)
class Spec {
  final String version;
  final String wcagVersion;
  final String wcagLevel;
  final DateTime releaseDate;
  final Map<String, Category> categories;
  final Map<String, Rule> rules;
  final Map<String, ComplianceLevel> complianceLevels;

  Spec({
    required this.version,
    required this.wcagVersion,
    required this.wcagLevel,
    required this.releaseDate,
    required this.categories,
    required this.rules,
    required this.complianceLevels,
  });

  /// Loads the spec from a YAML map
  factory Spec.fromYaml(Map<String, dynamic> yaml) {
    final specData = yaml['spec'] as Map<String, dynamic>;

    // Parse categories
    final categories = <String, Category>{};
    final categoriesYaml = yaml['categories'] as Map<String, dynamic>?;
    if (categoriesYaml != null) {
      categoriesYaml.forEach((key, value) {
        categories[key] = Category.fromYaml(value as Map<String, dynamic>);
      });
    }

    // Parse rules
    final rules = <String, Rule>{};
    final rulesYaml = yaml['rules'] as List?;
    if (rulesYaml != null) {
      for (final ruleYaml in rulesYaml) {
        final rule = Rule.fromYaml(ruleYaml as Map<String, dynamic>);
        rules[rule.ruleId] = rule;
      }
    }

    // Parse compliance levels
    final complianceLevels = <String, ComplianceLevel>{};
    final complianceYaml = yaml['compliance'] as Map<String, dynamic>?;
    if (complianceYaml != null) {
      complianceYaml.forEach((key, value) {
        complianceLevels[key] = ComplianceLevel.fromYaml(
          value as Map<String, dynamic>,
        );
      });
    }

    return Spec(
      version: specData['version'] as String,
      wcagVersion: specData['wcag_version'] as String,
      wcagLevel: specData['wcag_level'] as String,
      releaseDate: DateTime.parse(specData['release_date'] as String),
      categories: categories,
      rules: rules,
      complianceLevels: complianceLevels,
    );
  }

  @override
  String toString() =>
      'Spec(v$version, WCAG $wcagVersion Level $wcagLevel, ${rules.length} rules)';
}

/// Accessibility category (e.g., semantics, contrast, etc.)
class Category {
  final String id;
  final String name;
  final String description;
  final List<String> wcagPrinciples;

  Category({
    required this.id,
    required this.name,
    required this.description,
    required this.wcagPrinciples,
  });

  factory Category.fromYaml(Map<String, dynamic> yaml) {
    return Category(
      id: yaml['id'] as String,
      name: yaml['name'] as String,
      description: yaml['description'] as String,
      wcagPrinciples: List<String>.from(yaml['wcag_principles'] ?? []),
    );
  }

  @override
  String toString() => 'Category($id: $name)';
}

/// A specific WCAG rule with its coverage metric.
class Rule {
  final String ruleId;
  final String category;
  final String severity; // critical, high, medium, low
  final String wcagCriterion; // e.g., 1.3.1
  final String wcagLevel; // A, AA, AAA
  final String title;
  final String description;
  final List<String> appliesToWidgets;
  final List<String> excludesWidgets;
  final CoverageMetric coverageMetric;
  final List<RuleTestCase> testCases;
  final String howToFix;
  final Map<String, String> references;

  Rule({
    required this.ruleId,
    required this.category,
    required this.severity,
    required this.wcagCriterion,
    required this.wcagLevel,
    required this.title,
    required this.description,
    required this.appliesToWidgets,
    required this.excludesWidgets,
    required this.coverageMetric,
    required this.testCases,
    required this.howToFix,
    required this.references,
  });

  factory Rule.fromYaml(Map<String, dynamic> yaml) {
    return Rule(
      ruleId: yaml['rule_id'] as String,
      category: yaml['category'] as String,
      severity: yaml['severity'] as String,
      wcagCriterion: yaml['wcag_criterion'] as String,
      wcagLevel: yaml['wcag_level'] as String,
      title: yaml['title'] as String,
      description: yaml['description'] as String,
      appliesToWidgets: List<String>.from(yaml['applies_to'] ?? []),
      excludesWidgets: List<String>.from(yaml['excludes'] ?? []),
      coverageMetric: CoverageMetric.fromYaml(
        yaml['coverage_metric'] as Map<String, dynamic>,
      ),
      testCases: (yaml['test_cases'] as List?)
              ?.map((t) => RuleTestCase.fromYaml(t as Map<String, dynamic>))
              .toList() ??
          [],
      howToFix: yaml['how_to_fix'] as String? ?? '',
      references: Map<String, String>.from(yaml['references'] ?? {}),
    );
  }

  @override
  String toString() => 'Rule($ruleId: $title)';
}

/// Coverage metric for a specific rule.
class CoverageMetric {
  final String id;
  final String formula;
  final String unit;
  final double target;
  final double criticalThreshold;

  CoverageMetric({
    required this.id,
    required this.formula,
    required this.unit,
    required this.target,
    required this.criticalThreshold,
  });

  factory CoverageMetric.fromYaml(Map<String, dynamic> yaml) {
    return CoverageMetric(
      id: yaml['id'] as String,
      formula: yaml['formula'] as String,
      unit: yaml['unit'] as String,
      target: (yaml['target'] as num).toDouble(),
      criticalThreshold: (yaml['critical_threshold'] as num).toDouble(),
    );
  }

  @override
  String toString() => 'CoverageMetric($id, target: $target%)';
}

/// Test case linked to a rule.
class RuleTestCase {
  final String name;
  final String? code;
  final String? textColor;
  final String? bgColor;
  final String? size;
  final String expectedResult; // PASS or FAIL
  final String? issue;
  final String? reason;

  RuleTestCase({
    required this.name,
    this.code,
    this.textColor,
    this.bgColor,
    this.size,
    required this.expectedResult,
    this.issue,
    this.reason,
  });

  factory RuleTestCase.fromYaml(Map<String, dynamic> yaml) {
    return RuleTestCase(
      name: yaml['name'] as String,
      code: yaml['code'] as String?,
      textColor: yaml['text_color'] as String?,
      bgColor: yaml['bg_color'] as String?,
      size: yaml['size'] as String?,
      expectedResult: yaml['expected_result'] as String,
      issue: yaml['issue'] as String?,
      reason: yaml['reason'] as String?,
    );
  }

  @override
  String toString() => 'TestCase($name => $expectedResult)';
}

/// WCAG compliance level (A, AA, AAA)
class ComplianceLevel {
  final String name;
  final String description;
  final List<String> requiredRules;

  ComplianceLevel({
    required this.name,
    required this.description,
    required this.requiredRules,
  });

  factory ComplianceLevel.fromYaml(Map<String, dynamic> yaml) {
    return ComplianceLevel(
      name: yaml['name'] as String,
      description: yaml['description'] as String,
      requiredRules: List<String>.from(yaml['required_rules'] ?? []),
    );
  }

  @override
  String toString() =>
      'ComplianceLevel($name: ${requiredRules.length} required rules)';
}
