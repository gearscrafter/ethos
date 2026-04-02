import 'dart:io';
import 'package:yaml/yaml.dart';
import '../models/spec.dart';

/// Loads and validates accessibility specifications from YAML files.
///
/// This utility class provides static methods for loading WCAG 2.2 specifications
/// from files or strings, and validating their structure. It also handles the
/// conversion from YAML data structures to Dart-compatible types.
///
/// The class ensures that loaded specifications conform to the expected format
/// with all required fields and valid test cases.
class SpecLoader {
  static Future<Spec> loadFromFile(String filePath) async {
    try {
      final file = File(filePath);

      if (!await file.exists()) {
        throw SpecLoadException(
          'Spec file not found: $filePath',
          code: 'FILE_NOT_FOUND',
        );
      }

      final yamlString = await file.readAsString();
      final yaml = loadYaml(yamlString);

      if (yaml == null || yaml is! Map) {
        throw SpecLoadException(
          'Invalid YAML format in $filePath',
          code: 'INVALID_YAML',
        );
      }

      final spec = Spec.fromYaml(_convertYamlMapToDart(yaml as YamlMap));
      return spec;
    } on SpecLoadException {
      rethrow;
    } catch (e) {
      throw SpecLoadException(
        'Failed to load spec from $filePath: $e',
        code: 'LOAD_ERROR',
      );
    }
  }

  static Spec loadFromString(String yamlContent) {
    try {
      final yaml = loadYaml(yamlContent);

      if (yaml == null || yaml is! Map) {
        throw SpecLoadException('Invalid YAML format', code: 'INVALID_YAML');
      }

      return Spec.fromYaml(_convertYamlMapToDart(yaml as YamlMap));
    } on SpecLoadException {
      rethrow;
    } catch (e) {
      throw SpecLoadException(
        'Failed to load spec from string: $e',
        code: 'LOAD_ERROR',
      );
    }
  }

  static void validate(Spec spec) {
    final errors = <String>[];

    if (spec.version.isEmpty) {
      errors.add('Spec version is empty');
    }

    if (spec.wcagVersion.isEmpty) {
      errors.add('WCAG version is empty');
    }

    if (spec.rules.isEmpty) {
      errors.add('Spec has no rules');
    }

    for (final rule in spec.rules.values) {
      if (rule.ruleId.isEmpty) {
        errors.add('Rule has empty ID');
      }
      if (rule.wcagCriterion.isEmpty) {
        errors.add('Rule ${rule.ruleId} has empty WCAG criterion');
      }
      if (rule.testCases.isEmpty) {
        errors.add('Rule ${rule.ruleId} has no test cases');
      }
      for (final testCase in rule.testCases) {
        if (!['PASS', 'FAIL'].contains(testCase.expectedResult)) {
          errors.add(
            'Rule ${rule.ruleId}, test case "${testCase.name}" has invalid expected result: ${testCase.expectedResult}',
          );
        }
      }
    }

    if (errors.isNotEmpty) {
      throw SpecValidationException(errors);
    }
  }

  /// Converts YamlMap to Map<String, dynamic>
  static Map<String, dynamic> _convertYamlMapToDart(YamlMap yamlMap) {
    final result = <String, dynamic>{};
    for (final key in yamlMap.keys) {
      final value = yamlMap[key];
      if (value is YamlMap) {
        result[key.toString()] = _convertYamlMapToDart(value);
      } else if (value is YamlList) {
        result[key.toString()] = _convertYamlListToDart(value);
      } else {
        result[key.toString()] = value;
      }
    }
    return result;
  }

  /// Converts YamlList to List<dynamic>
  static List<dynamic> _convertYamlListToDart(YamlList yamlList) {
    final result = <dynamic>[];
    for (final item in yamlList) {
      if (item is YamlMap) {
        result.add(_convertYamlMapToDart(item));
      } else if (item is YamlList) {
        result.add(_convertYamlListToDart(item));
      } else {
        result.add(item);
      }
    }
    return result;
  }
}

/// Exception thrown when loading specs fails.
class SpecLoadException implements Exception {
  final String message;
  final String code;

  SpecLoadException(this.message, {required this.code});

  @override
  String toString() => 'SpecLoadException($code): $message';
}

/// Exception thrown when validating specs fails.
class SpecValidationException implements Exception {
  final List<String> errors;

  SpecValidationException(this.errors);

  @override
  String toString() => 'SpecValidationException: ${errors.join(', ')}';
}
