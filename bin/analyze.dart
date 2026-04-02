import 'package:args/args.dart';
import 'package:ethos/ethos.dart';
import 'dart:io';

/// Entry point for the Accessibility Coverage CLI tool.
///
/// Parses command-line arguments and executes accessibility coverage analysis
/// on a Flutter project.
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
      print('📋 Accessibility Coverage Analyzer');
      print('  Spec: $specPath');
      print('  Project: $projectPath');
      print('  Report format: $reportType');
      print('');
    }

    // Load analyzer
    if (verbose) print('🔄 Loading specifications...');
    late final CoverageAnalyzer analyzer;
    try {
      analyzer = await CoverageAnalyzer.loadFromFile(specPath);
    } catch (e) {
      print('❌ Error loading specs: $e');
      exit(1);
    }

    if (verbose)
      print('✅ Specifications loaded (${analyzer.spec.rules.length} rules)');

    // Run analysis
    if (verbose) print('🔍 Analyzing project...');
    final report = await analyzer.analyze(projectPath: projectPath);

    if (verbose) {
      print('✅ Analysis complete');
      print('  Found: ${report.coverage.length} rules evaluated');
      print('');
    }

    // Generate report
    String reportOutput;
    if (reportType == 'json') {
      reportOutput = report.toJsonString();
    } else if (reportType == 'markdown') {
      reportOutput = _generateMarkdownReport(report);
    } else if (reportType == 'coverage') {
      reportOutput = _generateCoverageReport(report);
    } else {
      reportOutput = _generateHumanReport(report);
    }

    // Output
    if (outputPath != null) {
      await File(outputPath).writeAsString(reportOutput);
      print('✅ Report saved to: $outputPath');
    } else {
      print(reportOutput);
    }

    // Exit with error if critical
    final hasCritical = report.coverage.values.any((c) => c.isCritical);
    if (hasCritical) {
      if (verbose) print('\n⚠️  Critical coverage issues detected');
      exit(1);
    }

    exit(0);
  } on FormatException catch (e) {
    print('❌ Invalid arguments: ${e.message}');
    print('');
    print(parser.usage);
    exit(1);
  } catch (e) {
    print('❌ Error: $e');
    exit(1);
  }
}

/// Generates a human-readable accessibility coverage report.
///
/// Returns a formatted string containing:
/// - Header with spec version
/// - Summary of overall coverage and compliance level
/// - Coverage breakdown by each rule
/// - List of issues found (if any)
///
/// Parameters:
/// - [report]: The [CoverageReport] to format
///
/// Returns: A formatted string with special characters (emojis, lines, etc)
///
/// Example:
/// ```dart
/// final output = _generateHumanReport(report);
/// print(output);
/// ```
String _generateHumanReport(CoverageReport report) {
  final buffer = StringBuffer();

  buffer.writeln('╔════════════════════════════════════════════════╗');
  buffer.writeln('║  Accessibility Coverage Report                 ║');
  buffer
      .writeln('║  Spec v${report.specVersion}                              ║');
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

  // Rules coverage
  buffer.writeln('📋 Coverage by Rule');
  buffer.writeln('─' * 50);

  for (final coverage in report.coverage.values) {
    final icon = coverage.isCritical ? '⚠️ ' : '✅';
    final status = coverage.isCritical ? 'CRITICAL' : 'OK';
    buffer.writeln(
      '$icon ${coverage.title}\n'
      '   Coverage: ${coverage.percentage.toStringAsFixed(2)}% '
      '(${coverage.matched}/${coverage.total}) [$status]\n',
    );
  }

  // Issues
  if (report.issues.isNotEmpty) {
    buffer.writeln('');
    buffer.writeln('⚠️  Issues');
    buffer.writeln('─' * 50);
    for (final issue in report.issues) {
      buffer.writeln('• $issue');
    }
  }

  return buffer.toString();
}

/// Generates a Markdown-formatted accessibility coverage report.
///
/// Returns a string formatted in Markdown that contains:
/// - Title and metadata (spec version, date, project)
/// - Summary with overall coverage and compliance level
/// - Table of coverage by rule
/// - List of issues (if any)
///
/// Parameters:
/// - [report]: The [CoverageReport] to format
///
/// Returns: A string in Markdown format (.md)
///
/// Usage:
/// ```dart
/// final markdown = _generateMarkdownReport(report);
/// File('report.md').writeAsStringSync(markdown);
/// ```
String _generateMarkdownReport(CoverageReport report) {
  final buffer = StringBuffer();

  buffer.writeln('# Accessibility Coverage Report');
  buffer.writeln('');
  buffer.writeln('**Spec:** v${report.specVersion}');
  buffer.writeln('**Date:** ${report.timestamp.toIso8601String()}');
  buffer.writeln('**Project:** ${report.projectPath}');
  buffer.writeln('');

  buffer.writeln('## Summary');
  buffer.writeln('');
  buffer.writeln(
      '- **Overall Coverage:** ${report.overallCoverage.toStringAsFixed(2)}%');
  buffer.writeln('- **Compliance Level:** `${report.complianceLevel}`');
  buffer.writeln('');

  buffer.writeln('## Coverage by Rule');
  buffer.writeln('');
  buffer.writeln('| Rule | Coverage | Status |');
  buffer.writeln('|------|----------|--------|');

  for (final coverage in report.coverage.values) {
    final status = coverage.isCritical ? '⚠️ CRITICAL' : '✅ OK';
    buffer.writeln(
      '| ${coverage.title} | ${coverage.percentage.toStringAsFixed(2)}% (${coverage.matched}/${coverage.total}) | $status |',
    );
  }

  if (report.issues.isNotEmpty) {
    buffer.writeln('');
    buffer.writeln('## Issues');
    buffer.writeln('');
    for (final issue in report.issues) {
      buffer.writeln('- $issue');
    }
  }

  return buffer.toString();
}

/// Generates a coverage summary report.
///
/// Returns a string containing:
/// - Overall coverage percentage (highlighted)
/// - Compliance level (highlighted)
/// - Breakdown by each rule with: coverage %, matched/total, status
///
/// Parameters:
/// - [report]: The [CoverageReport] to format
///
/// Returns: A formatted string with simple structure
String _generateCoverageReport(CoverageReport report) {
  final buffer = StringBuffer();

  buffer.writeln('# Accessibility Coverage Report');
  buffer.writeln('');
  buffer.writeln(
      'Overall Coverage: **${report.overallCoverage.toStringAsFixed(2)}%**');
  buffer.writeln('');
  buffer.writeln('Compliance Level: **${report.complianceLevel}**');
  buffer.writeln('');
  buffer.writeln('## Breakdown');
  buffer.writeln('');

  for (final coverage in report.coverage.values) {
    buffer.writeln('### ${coverage.title}');
    buffer.writeln('- Coverage: ${coverage.percentage.toStringAsFixed(2)}%');
    buffer.writeln('- Matched: ${coverage.matched}/${coverage.total}');
    buffer.writeln('- Status: ${coverage.isCritical ? 'CRITICAL' : 'OK'}');
    buffer.writeln('');
  }

  return buffer.toString();
}

/// Prints the CLI help message to the console.
///
/// Displays:
/// - General description of the tool
/// - Usage syntax
/// - Common usage examples
/// - Available options
///
/// Parameters:
/// - [parser]: The [ArgParser] with command-line argument configuration
void _printHelp(ArgParser parser) {
  print('Accessibility Coverage Analyzer');
  print('');
  print('Usage:');
  print('  dart bin/analyze.dart -p <project-path> [options]');
  print('');
  print('Examples:');
  print('  # Analyze and print human-readable report');
  print('  dart bin/analyze.dart -p ./my_flutter_app');
  print('');
  print('  # Generate JSON report');
  print('  dart bin/analyze.dart -p ./my_flutter_app -r json -o report.json');
  print('');
  print('  # Generate Markdown report');
  print('  dart bin/analyze.dart -p ./my_flutter_app -r markdown -o report.md');
  print('');
  print('Options:');
  print(parser.usage);
}
