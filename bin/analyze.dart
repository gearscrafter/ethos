import 'dart:io';
import 'package:args/args.dart';
import 'package:ethos/ethos.dart';

/// Entry point for the Ethos accessibility coverage CLI.
///
/// Available arguments:
/// - `-p, --project-path`: Path to the project to analyze (required)
/// - `-s, --spec-version`: Specification version (default: v1.0.0)
/// - `-r, --report-type`: Report format (json, human, markdown, coverage)
/// - `-o, --output`: Output file path (optional)
/// - `-v, --verbose`: Verbose mode
/// - `-h, --help`: Show help message
void main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption(
      'project-path',
      abbr: 'p',
      help: 'Path to Flutter project to analyze',
      mandatory: true,
    )
    ..addOption(
      'spec-version',
      abbr: 's',
      help: 'Specification version (default: v1.0.0)',
      defaultsTo: 'v1.0.0',
    )
    ..addOption(
      'spec-path',
      help: 'Path to specs YAML file (default: specs/\$version/wcag_2_2.yaml)',
    )
    ..addOption(
      'report-type',
      abbr: 'r',
      help: 'Report format: json, human, markdown, coverage',
      defaultsTo: 'human',
      allowed: ['json', 'human', 'markdown', 'coverage'],
    )
    ..addOption(
      'output',
      abbr: 'o',
      help: 'Output file path (optional, defaults to stdout)',
    )
    ..addFlag(
      'verbose',
      abbr: 'v',
      help: 'Print detailed information',
      defaultsTo: false,
    )
    ..addFlag(
      'help',
      abbr: 'h',
      help: 'Show help message',
      negatable: false,
    );

  try {
    final results = parser.parse(arguments);

    if (results['help'] as bool) {
      _printHelp(parser);
      exit(0);
    }

    final projectPath = results['project-path'] as String;
    final specVersion = results['spec-version'] as String;
    final specPath =
        results['spec-path'] as String? ?? 'specs/$specVersion/wcag_2_2.yaml';
    final reportType = results['report-type'] as String;
    final outputPath = results['output'] as String?;
    final verbose = results['verbose'] as bool;

    if (verbose) {
      stderr.writeln('📋 Ethos — Accessibility Coverage Analyzer');
      stderr.writeln('  Spec: $specPath');
      stderr.writeln('  Project: $projectPath');
      stderr.writeln('  Report format: $reportType');
      stderr.writeln('');
    }

    // Load analyzer
    if (verbose) stderr.writeln('🔄 Loading specifications...');
    late final CoverageAnalyzer analyzer;
    try {
      analyzer = await CoverageAnalyzer.loadFromFile(specPath);
    } catch (e) {
      stderr.writeln('❌ Error loading specs: $e');
      exit(1);
    }

    if (verbose) {
      stderr.writeln(
        '✅ Specifications loaded (${analyzer.spec.rules.length} rules)',
      );
      stderr.writeln(
        '   Detectors registered: '
        '${analyzer.registry.registeredRuleIds.length}',
      );
    }

    // Run analysis
    if (verbose) stderr.writeln('🔍 Analyzing project...');
    final report = await analyzer.analyze(projectPath: projectPath);

    if (verbose) {
      stderr.writeln('✅ Analysis complete');
      stderr.writeln('  Found: ${report.coverage.length} rules evaluated');
      stderr.writeln('');
    }

    // Generate report
    String reportOutput;
    switch (reportType) {
      case 'json':
        reportOutput = report.toJsonString();
      case 'markdown':
        reportOutput = _generateMarkdownReport(report);
      case 'coverage':
        reportOutput = _generateCoverageReport(report);
      default:
        reportOutput = _generateHumanReport(report);
    }

    // Output
    if (outputPath != null) {
      await File(outputPath).writeAsString(reportOutput);
      stderr.writeln('✅ Report saved to: $outputPath');
    } else {
      stdout.writeln(reportOutput);
    }

    // Exit with error if any rule is critical
    final hasCritical = report.coverage.values.any((c) => c.isCritical);
    if (hasCritical) {
      if (verbose) stderr.writeln('\n⚠️  Critical coverage issues detected');
      exit(1);
    }

    exit(0);
  } on FormatException catch (e) {
    stderr.writeln('❌ Invalid arguments: ${e.message}');
    stderr.writeln('');
    stderr.writeln(parser.usage);
    exit(1);
  } catch (e) {
    stderr.writeln('❌ Error: $e');
    exit(1);
  }
}

/// Generates a human-readable report (console-friendly).
String _generateHumanReport(CoverageReport report) {
  final buffer = StringBuffer();

  buffer.writeln('╔════════════════════════════════════════════════╗');
  buffer.writeln('║  Accessibility Coverage Report                 ║');
  buffer.writeln('${'║  Spec v${report.specVersion}'.padRight(49)}║');
  buffer.writeln('╚════════════════════════════════════════════════╝');
  buffer.writeln('');

  // Summary
  buffer.writeln('📊 Summary');
  buffer.writeln('─' * 50);
  buffer.writeln(
      'Overall Coverage: ${report.overallCoverage.toStringAsFixed(2)}%');
  buffer.writeln('Compliance Level: ${report.complianceLevel}');
  buffer.writeln('Project: ${report.projectPath}');
  buffer.writeln('Analyzed: ${report.timestamp.toIso8601String()}');
  buffer.writeln('');

  // Rules
  buffer.writeln('📋 Coverage by Rule');
  buffer.writeln('─' * 50);
  for (final coverage in report.coverage.values) {
    final icon = coverage.isCritical
        ? '⚠️ '
        : (coverage.total == 0 ? 'ℹ️ ' : '✅');
    final status = coverage.isCritical
        ? 'CRITICAL'
        : (coverage.total == 0 ? 'NO DATA' : 'OK');

    buffer.writeln('$icon ${coverage.title}');
    buffer.writeln(
      '   Coverage: ${coverage.percentage.toStringAsFixed(2)}% '
      '(${coverage.matched}/${coverage.total}) [$status]',
    );
    if (coverage.indeterminate > 0) {
      buffer.writeln(
        '   ⓘ  ${coverage.indeterminate} indeterminate '
        '(value resolved at runtime — not counted)',
      );
    }
    buffer.writeln('');
  }

  // Findings
  final allFindings = [
    for (final c in report.coverage.values) ...c.findings,
  ];
  if (allFindings.isNotEmpty) {
    buffer.writeln('🔎 Findings (${allFindings.length})');
    buffer.writeln('─' * 50);
    for (final f in allFindings) {
      final tag = f.severity == FindingSeverity.indeterminate
          ? 'ⓘ INDETERMINATE'
          : '✗ FAIL          ';
      buffer.writeln('$tag ${f.filePath}:${f.line}:${f.column}');
      buffer.writeln('   ${f.widgetType} — ${f.message}');
    }
    buffer.writeln('');
  }

  // Engine issues
  if (report.issues.isNotEmpty) {
    buffer.writeln('⚠️  Engine Issues');
    buffer.writeln('─' * 50);
    for (final issue in report.issues) {
      buffer.writeln('• $issue');
    }
  }

  return buffer.toString();
}

/// Generates a Markdown report (for PRs, docs, sharing).
String _generateMarkdownReport(CoverageReport report) {
  final buffer = StringBuffer();

  buffer.writeln('# Accessibility Coverage Report');
  buffer.writeln('');
  buffer.writeln('**Spec:** v${report.specVersion}  ');
  buffer.writeln('**Date:** ${report.timestamp.toIso8601String()}  ');
  buffer.writeln('**Project:** `${report.projectPath}`');
  buffer.writeln('');

  buffer.writeln('## Summary');
  buffer.writeln('');
  buffer.writeln(
      '- **Overall Coverage:** ${report.overallCoverage.toStringAsFixed(2)}%');
  buffer.writeln('- **Compliance Level:** `${report.complianceLevel}`');
  buffer.writeln('');

  buffer.writeln('## Coverage by Rule');
  buffer.writeln('');
  buffer.writeln('| Rule | Coverage | Indeterminate | Status |');
  buffer.writeln('|------|----------|---------------|--------|');
  for (final coverage in report.coverage.values) {
    final status = coverage.isCritical
        ? '⚠️ CRITICAL'
        : (coverage.total == 0 ? 'ℹ️ NO DATA' : '✅ OK');
    final ind = coverage.indeterminate > 0 ? '${coverage.indeterminate}' : '—';
    buffer.writeln(
      '| ${coverage.title} '
      '| ${coverage.percentage.toStringAsFixed(2)}% '
      '(${coverage.matched}/${coverage.total}) '
      '| $ind '
      '| $status |',
    );
  }

  final allFindings = [
    for (final c in report.coverage.values) ...c.findings,
  ];
  if (allFindings.isNotEmpty) {
    buffer.writeln('');
    buffer.writeln('## Findings');
    buffer.writeln('');
    for (final f in allFindings) {
      final tag =
          f.severity == FindingSeverity.indeterminate ? 'ⓘ' : '✗';
      buffer.writeln(
        '- $tag `${f.filePath}:${f.line}:${f.column}` '
        '— **${f.widgetType}** — ${f.message}',
      );
    }
  }

  if (report.issues.isNotEmpty) {
    buffer.writeln('');
    buffer.writeln('## Engine Issues');
    buffer.writeln('');
    for (final issue in report.issues) {
      buffer.writeln('- $issue');
    }
  }

  return buffer.toString();
}

/// Generates a compact coverage-only report (Markdown structured).
String _generateCoverageReport(CoverageReport report) {
  final buffer = StringBuffer();

  buffer.writeln('# Accessibility Coverage Report');
  buffer.writeln('');
  buffer.writeln(
      'Overall Coverage: **${report.overallCoverage.toStringAsFixed(2)}%**');
  buffer.writeln('Compliance Level: **${report.complianceLevel}**');
  buffer.writeln('');
  buffer.writeln('## Breakdown');
  buffer.writeln('');

  for (final coverage in report.coverage.values) {
    buffer.writeln('### ${coverage.title}');
    buffer.writeln('- Coverage: ${coverage.percentage.toStringAsFixed(2)}%');
    buffer.writeln('- Matched: ${coverage.matched}/${coverage.total}');
    if (coverage.indeterminate > 0) {
      buffer.writeln('- Indeterminate: ${coverage.indeterminate}');
    }
    final status = coverage.isCritical
        ? 'CRITICAL'
        : (coverage.total == 0 ? 'NO DATA' : 'OK');
    buffer.writeln('- Status: $status');
    buffer.writeln('');
  }

  return buffer.toString();
}

void _printHelp(ArgParser parser) {
  print('Ethos — Accessibility Coverage Analyzer');
  print('');
  print('Usage:');
  print('  ethos -p <project-path> [options]');
  print('');
  print('Examples:');
  print('  # Analyze and print human-readable report');
  print('  ethos -p ./my_flutter_app');
  print('');
  print('  # Generate JSON report (CI/CD friendly)');
  print('  ethos -p ./my_flutter_app -r json -o report.json');
  print('');
  print('  # Generate Markdown report (for PR comments)');
  print('  ethos -p ./my_flutter_app -r markdown -o report.md');
  print('');
  print('Options:');
  print(parser.usage);
}