import 'package:ethos/ethos.dart';

/// Example: Using ethos as a library
void main() async {
  print('╔════════════════════════════════════════════════╗');
  print('║            Accessibility Coverage              ║');
  print('╚════════════════════════════════════════════════╝');
  print('');

  try {
    print('📋 Loading specifications...');
    final analyzer =
        await CoverageAnalyzer.loadFromFile('specs/v1.0.0/wcag_2_2.yaml');
    print('✅ Loaded: ${analyzer.spec.version}');
    print(
        '   WCAG: ${analyzer.spec.wcagVersion} Level ${analyzer.spec.wcagLevel}');
    print('   Rules: ${analyzer.spec.rules.length}');
    print('');

    const projectPath = '.';

    print('🔍 Analyzing project: $projectPath');
    final report = await analyzer.analyze(projectPath: projectPath);
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
      final icon = coverage.isCritical ? '⚠️ ' : '✅';
      final status = coverage.isCritical ? '[CRITICAL]' : '[OK]';
      print('$icon${coverage.title}\n'
          '   ${coverage.percentage.toStringAsFixed(2)}% '
          '(${coverage.matched}/${coverage.total}) $status\n');
    }

    if (report.issues.isNotEmpty) {
      print('');
      print('⚠️  Issues Found');
      print('─' * 50);
      for (final issue in report.issues) {
        print('• $issue');
      }
    }

    print('');
    print('📄 Full Report (JSON)');
    print('─' * 50);
    print(report.toJsonString());
  } catch (e) {
    print('❌ Error: $e');
  }
}
