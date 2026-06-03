import '../analyzer/ast/widget_visitor.dart';
import '../analyzer/coverage_analyzer.dart';
import '../analyzer/spec_loader.dart';
import '../models/coverage_report.dart';

/// Test utilities for using Ethos inside a `dart test` or `flutter_test` suite.
class EthosTestHelper {
  EthosTestHelper._();

  /// Analyzes the Dart files in [projectPath] and returns a [CoverageReport].
  ///
  /// An optional [configPath] can point to a custom `ethos.yaml`; if omitted,
  /// Ethos auto-detects one at `<projectPath>/ethos.yaml`. If neither is found
  /// the built-in WCAG 2.2 spec is used as-is.
  static Future<CoverageReport> analyzeProject(
    String projectPath, {
    String? configPath,
  }) async {
    final analyzer = await CoverageAnalyzer.forProject(
      projectPath,
      configPath: configPath,
    );
    return analyzer.analyze();
  }

  /// Analyzes an inline Dart [source] snippet and returns a [CoverageReport].
  ///
  /// Does NOT touch the filesystem — the source is parsed in memory and run
  /// through every detector directly. Use this in detector unit tests:
  ///
  /// ```dart
  /// final report = await EthosTestHelper.analyzeSource(
  ///   "Icon(Icons.search, semanticLabel: 'Search')",
  /// );
  /// expect(report, passesRule('wcag_1_1_1_non_text_content'));
  /// ```
  static Future<CoverageReport> analyzeSource(
    String source, {
    String? configPath,
  }) async {
    // Wrap in a minimal Flutter preamble so widget names are recognised.
    final wrapped = '''
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

void main() {
  $source;
}
''';

    final parsedFile = parseDartFile('inline_test.dart', wrapped);

    // Load the built-in spec (no project path needed — use '.' which always
    // exists, and skip configPath so we never hit CONFIG_NOT_FOUND).
    final spec = await SpecLoader.load(
      projectPath: '.',
      configPath: configPath,
    );
    final analyzer = CoverageAnalyzer(spec: spec, projectPath: '.');

    // Bypass the file-system scan and run directly on our in-memory file.
    return analyzer.analyzeFiles([parsedFile]);
  }

  /// Asserts that [projectPath] has no critical accessibility failures.
  ///
  /// Throws a [TestFailure] with a human-readable summary if any rule is
  /// below its critical threshold. Useful as a one-liner smoke test:
  ///
  /// ```dart
  /// test('no critical a11y failures', () async {
  ///   await EthosTestHelper.expectNoCriticalFailures('lib/');
  /// });
  /// ```
  static Future<void> expectNoCriticalFailures(
    String projectPath, {
    String? configPath,
  }) async {
    final report = await analyzeProject(projectPath, configPath: configPath);
    final critical = report.coverage.values.where((c) => c.isCritical).toList();
    if (critical.isEmpty) {
      return;
    }

    final lines = critical.map((c) {
      final pct = c.percentage.toStringAsFixed(1);
      return '  • ${c.title} ($pct% — below ${c.ruleId} threshold)';
    }).join('\n');

    throw TestFailure(
      'Ethos found ${critical.length} critical accessibility failure(s):\n'
      '$lines\n\n'
      'Run `ethos -p $projectPath` for full details.',
    );
  }
}

/// Thrown by [EthosTestHelper.expectNoCriticalFailures] when critical failures
/// are detected.
class TestFailure implements Exception {
  final String message;
  const TestFailure(this.message);
  @override
  String toString() => 'TestFailure: $message';
}
