import 'dart:io';

import 'package:ethos/src/specs/v1.0.0/wcag_2_2_embedded.dart';
import 'package:yaml/yaml.dart';

import '../models/spec.dart';
import '../models/ethos_config.dart';

/// Loads the Ethos accessibility spec.
///
/// The built-in spec ships embedded inside the package as [wcag22V1Yaml].
/// [SpecLoader.load] starts from that built-in and optionally merges in an
/// `ethos.yaml` from the user's project root.
///
class SpecLoader {
  static Future<Spec> load({
    String? projectPath,
    String? configPath,
  }) async {
    final base = _parseSpecYaml(wcag22V1Yaml);
    final configFile = await _locateConfig(
      projectPath: projectPath,
      configPath: configPath,
    );
    if (configFile == null) {
      return _materialize(base, EthosConfig.empty);
    }
    final configYaml = await configFile.readAsString();
    final config = _parseConfigYaml(configYaml);
    return _materialize(base, config);
  }

  static Future<Spec> loadFromFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw SpecLoadException(
        'Spec file not found: $filePath',
        code: 'FILE_NOT_FOUND',
      );
    }
    return _parseSpecYaml(await file.readAsString());
  }

  static Spec loadFromString(String yamlContent) {
    return _parseSpecYaml(yamlContent);
  }

  static void validate(Spec spec) {
    final errors = <String>[];
    if (spec.version.isEmpty) errors.add('Spec version is empty');
    if (spec.wcagVersion.isEmpty) errors.add('WCAG version is empty');
    if (spec.rules.isEmpty) errors.add('Spec has no rules');
    for (final rule in spec.rules.values) {
      if (rule.ruleId.isEmpty) errors.add('Rule has empty ID');
      if (rule.wcagCriterion.isEmpty) {
        errors.add('Rule ${rule.ruleId} has empty WCAG criterion');
      }
      for (final testCase in rule.testCases) {
        if (!['PASS', 'FAIL'].contains(testCase.expectedResult)) {
          errors.add(
            'Rule ${rule.ruleId}, test case "${testCase.name}" '
            'has invalid expected result: ${testCase.expectedResult}',
          );
        }
      }
    }
    if (errors.isNotEmpty) throw SpecValidationException(errors);
  }

  static Future<File?> _locateConfig({
    String? projectPath,
    String? configPath,
  }) async {
    if (configPath != null) {
      final f = File(configPath);
      if (!await f.exists()) {
        throw SpecLoadException(
          'Ethos config not found: $configPath',
          code: 'CONFIG_NOT_FOUND',
        );
      }
      return f;
    }
    if (projectPath == null) return null;
    final candidate = File('$projectPath${Platform.pathSeparator}ethos.yaml');
    return await candidate.exists() ? candidate : null;
  }

  static Spec _parseSpecYaml(String yamlString) {
    try {
      final yaml = loadYaml(yamlString);
      if (yaml == null || yaml is! Map) {
        throw SpecLoadException('Invalid YAML format', code: 'INVALID_YAML');
      }
      return Spec.fromYaml(_yamlMapToDart(yaml as YamlMap));
    } on SpecLoadException {
      rethrow;
    } catch (e) {
      throw SpecLoadException('Failed to parse spec: $e', code: 'LOAD_ERROR');
    }
  }

  static EthosConfig _parseConfigYaml(String yamlString) {
    try {
      final yaml = loadYaml(yamlString);
      if (yaml == null) return EthosConfig.empty;
      if (yaml is! Map) {
        throw SpecLoadException(
          'Invalid ethos.yaml: root must be a map',
          code: 'INVALID_YAML',
        );
      }
      return EthosConfig.fromYaml(_yamlMapToDart(yaml as YamlMap));
    } on SpecLoadException {
      rethrow;
    } catch (e) {
      throw SpecLoadException(
        'Failed to parse ethos.yaml: $e',
        code: 'LOAD_ERROR',
      );
    }
  }

  static Spec _materialize(Spec base, EthosConfig config) {
    final mergedAliases = <String, WidgetAlias>{
      ...base.widgetAliases,
      ...config.widgetAliases,
    };
    final mergedColorAliases = <String, ColorAlias>{
      ...base.colorAliases,
      ...config.colorAliases,
    };
    final mergedRules = <String, Rule>{};
    base.rules.forEach((id, rule) {
      final override = config.ruleOverrides[id];
      if (override == null) {
        mergedRules[id] = rule;
        return;
      }
      mergedRules[id] = Rule(
        ruleId: rule.ruleId,
        category: rule.category,
        severity: rule.severity,
        wcagCriterion: rule.wcagCriterion,
        wcagLevel: rule.wcagLevel,
        title: rule.title,
        description: rule.description,
        appliesToWidgets: rule.appliesToWidgets,
        excludesWidgets: rule.excludesWidgets,
        coverageMetric: CoverageMetric(
          id: rule.coverageMetric.id,
          formula: rule.coverageMetric.formula,
          unit: rule.coverageMetric.unit,
          target: override.target ?? rule.coverageMetric.target,
          criticalThreshold: override.criticalThreshold ??
              rule.coverageMetric.criticalThreshold,
        ),
        testCases: rule.testCases,
        howToFix: rule.howToFix,
        references: rule.references,
      );
    });
    return Spec(
      version: base.version,
      wcagVersion: base.wcagVersion,
      wcagLevel: base.wcagLevel,
      releaseDate: base.releaseDate,
      categories: base.categories,
      rules: mergedRules,
      complianceLevels: base.complianceLevels,
      widgetAliases: mergedAliases,
      colorAliases: mergedColorAliases,
    );
  }

  static Map<String, dynamic> _yamlMapToDart(YamlMap yamlMap) {
    final result = <String, dynamic>{};
    for (final key in yamlMap.keys) {
      final value = yamlMap[key];
      if (value is YamlMap) {
        result[key.toString()] = _yamlMapToDart(value);
      } else if (value is YamlList) {
        result[key.toString()] = _yamlListToDart(value);
      } else {
        result[key.toString()] = value;
      }
    }
    return result;
  }

  static List<dynamic> _yamlListToDart(YamlList yamlList) {
    final result = <dynamic>[];
    for (final item in yamlList) {
      if (item is YamlMap) {
        result.add(_yamlMapToDart(item));
      } else if (item is YamlList) {
        result.add(_yamlListToDart(item));
      } else {
        result.add(item);
      }
    }
    return result;
  }
}

class SpecLoadException implements Exception {
  final String message;
  final String code;
  SpecLoadException(this.message, {required this.code});
  @override
  String toString() => 'SpecLoadException($code): $message';
}

class SpecValidationException implements Exception {
  final List<String> errors;
  SpecValidationException(this.errors);
  @override
  String toString() => 'SpecValidationException: ${errors.join(', ')}';
}
