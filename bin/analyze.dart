import 'dart:io';
import 'package:args/args.dart';
import 'package:ethos/ethos.dart';

/// Ethos CLI entry point.
///
/// Usage:
///   ethos -p <project-path> [options]
///
/// Ethos ships with the built-in WCAG 2.2 spec. You do NOT copy any spec
/// file. To extend with your design system, create an optional `ethos.yaml`
/// at your project root; Ethos auto-detects it.
void main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('project-path',
        abbr: 'p', help: 'Path to Flutter project to analyze', mandatory: true)
    ..addOption('config',
        abbr: 'c',
        help:
            'Path to an ethos.yaml. Defaults to <project-path>/ethos.yaml if present.')
    ..addOption('report-type',
        abbr: 'r',
        help: 'Report format: json, human, markdown, coverage',
        defaultsTo: 'human',
        allowed: ['json', 'human', 'markdown', 'coverage'])
    ..addOption('output',
        abbr: 'o', help: 'Output file path (optional, defaults to stdout)')
    ..addFlag('verbose',
        abbr: 'v', help: 'Print detailed information', defaultsTo: false)
    ..addFlag('help', abbr: 'h', help: 'Show help message', negatable: false);

  try {
    final results = parser.parse(arguments);
    if (results['help'] as bool) {
      _printHelp(parser);
      exit(0);
    }

    final projectPath = results['project-path'] as String;
    final configPath = results['config'] as String?;
    final reportType = results['report-type'] as String;
    final outputPath = results['output'] as String?;
    final verbose = results['verbose'] as bool;

    if (verbose) {
      stderr.writeln('📋 Ethos — Accessibility Coverage Analyzer');
      stderr.writeln('  Project: $projectPath');
      if (configPath != null) {
        stderr.writeln('  Config: $configPath (explicit)');
      } else {
        final auto = '$projectPath${Platform.pathSeparator}ethos.yaml';
        stderr.writeln(File(auto).existsSync()
            ? '  Config: $auto (auto-detected)'
            : '  Config: (none — using built-in spec only)');
      }
      stderr.writeln('  Report format: $reportType');
      stderr.writeln('');
    }

    late final CoverageAnalyzer analyzer;
    try {
      analyzer = await CoverageAnalyzer.forProject(
        projectPath,
        configPath: configPath,
      );
    } catch (e) {
      stderr.writeln('❌ Error loading spec: $e');
      exit(1);
    }

    if (verbose) {
      stderr.writeln('✅ Spec loaded: v${analyzer.spec.version} '
          '(${analyzer.spec.rules.length} rules, '
          '${analyzer.spec.widgetAliases.length} aliases)');
      stderr.writeln(
          '   Detectors registered: ${analyzer.registry.registeredRuleIds.length}');
      stderr.writeln('🔍 Analyzing project...');
    }

    final report = await analyzer.analyze();

    if (verbose) {
      stderr.writeln(
          '✅ Analysis complete (${report.coverage.length} rules evaluated)');
      stderr.writeln('');
    }

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

    if (outputPath != null) {
      await File(outputPath).writeAsString(reportOutput);
      stderr.writeln('✅ Report saved to: $outputPath');
    } else {
      stdout.writeln(reportOutput);
    }

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

String _generateHumanReport(CoverageReport report) {
  final buffer = StringBuffer();
  buffer.writeln('╔════════════════════════════════════════════════╗');
  buffer.writeln('║  Accessibility Coverage Report                 ║');
  buffer.writeln('${'║  Spec v${report.specVersion}'.padRight(49)}║');
  buffer.writeln('╚════════════════════════════════════════════════╝');
  buffer.writeln('');
  buffer.writeln('📊 Summary');
  buffer.writeln('─' * 50);
  buffer.writeln(
      'Overall Coverage: ${report.overallCoverage.toStringAsFixed(2)}%');
  buffer.writeln('Compliance Level: ${report.complianceLevel}');
  buffer.writeln('Project: ${report.projectPath}');
  buffer.writeln('Analyzed: ${report.timestamp.toIso8601String()}');
  buffer.writeln('');
  buffer.writeln('📋 Coverage by Rule');
  buffer.writeln('─' * 50);
  for (final c in report.coverage.values) {
    final icon = c.isCritical ? '⚠️ ' : (c.total == 0 ? 'ℹ️ ' : '✅');
    final status =
        c.isCritical ? 'CRITICAL' : (c.total == 0 ? 'NO DATA' : 'OK');
    buffer.writeln('$icon ${c.title}');
    buffer.writeln(
        '   Coverage: ${c.percentage.toStringAsFixed(2)}% (${c.matched}/${c.total}) [$status]');
    if (c.indeterminate > 0) {
      buffer.writeln(
          '   ⓘ  ${c.indeterminate} indeterminate (value resolved at runtime — not counted)');
    }
    buffer.writeln('');
  }
  final allFindings = [for (final c in report.coverage.values) ...c.findings];
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
  if (report.issues.isNotEmpty) {
    buffer.writeln('⚠️  Engine Issues');
    buffer.writeln('─' * 50);
    for (final issue in report.issues) {
      buffer.writeln('• $issue');
    }
  }
  return buffer.toString();
}

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
  for (final c in report.coverage.values) {
    final status =
        c.isCritical ? '⚠️ CRITICAL' : (c.total == 0 ? 'ℹ️ NO DATA' : '✅ OK');
    final ind = c.indeterminate > 0 ? '${c.indeterminate}' : '—';
    buffer.writeln(
        '| ${c.title} | ${c.percentage.toStringAsFixed(2)}% (${c.matched}/${c.total}) | $ind | $status |');
  }
  final allFindings = [for (final c in report.coverage.values) ...c.findings];
  if (allFindings.isNotEmpty) {
    buffer.writeln('');
    buffer.writeln('## Findings');
    buffer.writeln('');
    for (final f in allFindings) {
      final tag = f.severity == FindingSeverity.indeterminate ? 'ⓘ' : '✗';
      buffer.writeln(
          '- $tag `${f.filePath}:${f.line}:${f.column}` — **${f.widgetType}** — ${f.message}');
    }
  }
  return buffer.toString();
}

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
  for (final c in report.coverage.values) {
    buffer.writeln('### ${c.title}');
    buffer.writeln('- Coverage: ${c.percentage.toStringAsFixed(2)}%');
    buffer.writeln('- Matched: ${c.matched}/${c.total}');
    if (c.indeterminate > 0) {
      buffer.writeln('- Indeterminate: ${c.indeterminate}');
    }
    final status =
        c.isCritical ? 'CRITICAL' : (c.total == 0 ? 'NO DATA' : 'OK');
    buffer.writeln('- Status: $status');
    buffer.writeln('');
  }
  return buffer.toString();
}

void _printHelp(ArgParser parser) {
  print('Ethos — Accessibility Coverage Analyzer');
  print('');
  print('Ethos ships with the built-in WCAG 2.2 spec — you do NOT copy any');
  print('spec file. To extend with your design-system widgets or override');
  print('thresholds, create an optional ethos.yaml at your project root.');
  print('');
  print('Usage:');
  print('  ethos -p <project-path> [options]');
  print('');
  print('Examples:');
  print('  ethos -p ./my_app');
  print('  ethos -p ./my_app -c custom-ethos.yaml');
  print('  ethos -p ./my_app -r json -o report.json');
  print('  ethos -p ./my_app -r markdown -o report.md');
  print('');
  print('Options:');
  print(parser.usage);
}
