import 'package:ethos/ethos.dart';

/// Example: using Ethos as a library.
///
/// This example analyzes the `example/fixtures/` folder — a set of Dart
/// files that exist only as input for the analyzer (they are never
/// compiled or executed; Ethos reads them as text and parses their AST).
/// The fixtures contain intentional accessibility issues so you can see
/// how Ethos reports matched, failed, and indeterminate widgets with
/// file:line:column locations.
///
/// The fixtures folder also contains an optional `ethos.yaml` that
/// declares a sample widget alias (CircleIconBtn) — this demonstrates
/// how your own design-system widgets can be taught to Ethos without
/// modifying any package code.
///
/// Run from the package root:
/// ```
/// dart run example/main.dart
/// ```
void main() async {
  print('╔════════════════════════════════════════════════╗');
  print('║              Ethos — Library Example           ║');
  print('╚════════════════════════════════════════════════╝');
  print('');

  try {
    const projectPath = 'example/fixtures';

    print('📋 Loading spec...');
    final analyzer = await CoverageAnalyzer.forProject(projectPath);

    print('Spec v${analyzer.spec.version}');
    print(
        '   WCAG: ${analyzer.spec.wcagVersion} Level ${analyzer.spec.wcagLevel}');
    print('   Rules in spec: ${analyzer.spec.rules.length}');
    print('   Detectors registered: '
        '${analyzer.registry.registeredRuleIds.length}');
    if (analyzer.spec.widgetAliases.isNotEmpty) {
      print(
          '   Widget aliases: ${analyzer.spec.widgetAliases.keys.join(', ')}');
    }
    print('');

    print('🔍 Analyzing project: $projectPath');
    final report = await analyzer.analyze();
    print('✅ Analysis complete');
    print('');

    print('📊 Results');
    print('─' * 50);
    print('Overall Coverage: ${report.overallCoverage.toStringAsFixed(2)}%');
    print('Compliance Level: ${report.complianceLevel}');
    print('Analyzed at: ${report.timestamp.toIso8601String()}');
    print('');

    print('📋 Coverage by Rule');
    print('─' * 50);
    for (final coverage in report.coverage.values) {
      final icon =
          coverage.isCritical ? '⚠️ ' : (coverage.total == 0 ? 'ℹ️ ' : '✅');
      final status = coverage.isCritical
          ? '[CRITICAL]'
          : (coverage.total == 0 ? '[NO DATA]' : '[OK]');

      print('$icon ${coverage.title}');
      print('   ${coverage.percentage.toStringAsFixed(2)}% '
          '(${coverage.matched}/${coverage.total}) $status');

      if (coverage.indeterminate > 0) {
        print('   ⓘ  ${coverage.indeterminate} indeterminate '
            '(value resolved at runtime — not counted)');
      }
      print('');
    }

    final allFindings = [
      for (final c in report.coverage.values) ...c.findings,
    ];

    if (allFindings.isNotEmpty) {
      print('🔎 Findings (${allFindings.length})');
      print('─' * 50);
      for (final f in allFindings) {
        final tag = f.severity == FindingSeverity.indeterminate
            ? 'ⓘ INDETERMINATE'
            : '✗ FAIL';
        print('$tag ${f.filePath}:${f.line}:${f.column}');
        print('   ${f.widgetType} — ${f.message}');
      }
      print('');
    }

    if (report.issues.isNotEmpty) {
      print('⚠️  Engine Issues');
      print('─' * 50);
      for (final issue in report.issues) {
        print('• $issue');
      }
      print('');
    }

    print('📄 Full Report (JSON)');
    print('─' * 50);
    print(report.toJsonString());
  } catch (e, st) {
    print('❌ Error: $e');
    print(st);
  }
}
