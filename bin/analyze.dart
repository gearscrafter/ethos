import 'dart:io';
import 'package:args/args.dart';
import 'package:ethos/ethos.dart';

/// Ethos CLI entry point.
///
/// Supports two subcommands:
///   ethos -p <path> [options]          — run accessibility analysis
///   ethos init -p <path> [options]     — generate starter ethos.yaml
void main(List<String> arguments) async {
  // Check for 'init' subcommand as first argument.
  if (arguments.isNotEmpty && arguments.first == 'init') {
    await _runInit(arguments.sublist(1));
    return;
  }

  await _runAnalyze(arguments);
}

// ─── analyze ─────────────────────────────────────────────────────────────────

Future<void> _runAnalyze(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('project-path',
        abbr: 'p', help: 'Path to Flutter project to analyze', mandatory: true)
    ..addOption('config',
        abbr: 'c', help: 'Path to an ethos.yaml (default: auto-detect).')
    ..addOption('report-type',
        abbr: 'r',
        help: 'Output format: human | json | markdown | coverage',
        defaultsTo: 'human',
        allowed: ['json', 'human', 'markdown', 'coverage'])
    ..addOption('output',
        abbr: 'o', help: 'Write report to this file instead of stdout')
    ..addFlag('deep',
        abbr: 'd',
        help: 'Deep analysis: resolves types and cross-file references.\n'
            'Slower but more precise. Requires `flutter pub get` in the project.\n'
            'Falls back to standard mode automatically if the project is not ready.',
        defaultsTo: false)
    ..addFlag('verbose',
        abbr: 'v',
        help: 'Print progress details (written to stderr)',
        defaultsTo: false)
    ..addFlag('help', abbr: 'h', help: 'Show help message', negatable: false);

  try {
    final results = parser.parse(arguments);
    if (results['help'] as bool) {
      _printAnalyzeHelp(parser);
      exit(0);
    }

    final projectPath = results['project-path'] as String;
    final configPath = results['config'] as String?;
    final reportType = results['report-type'] as String;
    final outputPath = results['output'] as String?;
    final deepMode = results['deep'] as bool;
    final verbose = results['verbose'] as bool;

    if (verbose) {
      stderr.writeln('📋 Ethos — Accessibility Coverage Analyzer');
      stderr.writeln('  Project: $projectPath');
      stderr.writeln('  Mode: ${deepMode ? "deep 🔬" : "standard"}');
      final cfgAuto = '$projectPath${Platform.pathSeparator}ethos.yaml';
      stderr.writeln(configPath != null
          ? '  Config: $configPath (explicit)'
          : File(cfgAuto).existsSync()
              ? '  Config: $cfgAuto (auto-detected)'
              : '  Config: (none — using built-in spec only)');
      stderr.writeln('  Report format: $reportType');
      stderr.writeln('');
    }

    late final CoverageReport report;
    CoverageReport? reportHolder;

    if (deepMode) {
      final deepAnalyzer = await DeepAnalyzer.forProject(
        projectPath,
        configPath: configPath,
      );

      if (verbose) {
        stderr.writeln('✅ Spec v${deepAnalyzer.spec.version} '
            '(${deepAnalyzer.spec.rules.length} rules, '
            '${deepAnalyzer.spec.widgetAliases.length} aliases)');
      }

      stderr.writeln('🔬 Deep analysis mode');
      bool inProgressLine = false;

      await for (final event in deepAnalyzer.analyze()) {
        switch (event) {
          case AnalysisPreparing():
            stderr.writeln('   Checking project readiness...');
          case AnalysisLoadingContext(:final totalFiles):
            stderr.writeln('   Loading context ($totalFiles files)...');
          case AnalysisAnalyzingFile(:final current, :final total, :final path):
            if (verbose) {
              final bar = _progressBar(current, total);
              stderr.writeln('   [$current/$total] $bar '
                  '${path.split(Platform.pathSeparator).last}');
            } else {
              stderr.write('\r   Resolving: $current / $total');
              inProgressLine = true;
            }
          case AnalysisRunningDetector(:final ruleTitle):
            if (inProgressLine) {
              stderr.writeln('');
              inProgressLine = false;
            }
            stderr.writeln('   ✓ $ruleTitle');
          case AnalysisWarning(:final message):
            if (inProgressLine) {
              stderr.writeln('');
              inProgressLine = false;
            }
            stderr.writeln('⚠️  $message');
          case AnalysisComplete():
            final completedReport = (event).report;
            final usedDeep = (event).usedDeepMode;
            if (inProgressLine) {
              stderr.writeln('');
              inProgressLine = false;
            }
            stderr.writeln(usedDeep
                ? '✅ Deep analysis complete'
                : '✅ Analysis complete (fell back to standard mode)');
            stderr.writeln('');
            reportHolder = completedReport;
        }
      }

      if (reportHolder == null) {
        stderr.writeln('❌ Deep analysis did not complete.');
        exit(1);
      }
      report = reportHolder;
    } else {
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
        stderr.writeln('✅ Spec v${analyzer.spec.version} '
            '(${analyzer.spec.rules.length} rules, '
            '${analyzer.spec.widgetAliases.length} aliases)');
        stderr.writeln(
            '   Detectors: ${analyzer.registry.registeredRuleIds.length}');
        stderr.writeln('🔍 Analyzing project...');
      }

      report = await analyzer.analyze();

      if (verbose) {
        stderr.writeln(
            '✅ Analysis complete (${report.coverage.length} rules evaluated)');
        stderr.writeln('');
      }
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
      if (verbose) {
        stderr.writeln('\n⚠️  Critical coverage issues detected');
      }
      exit(1);
    }
    exit(0);
  } on FormatException catch (e) {
    stderr.writeln('❌ Invalid arguments: ${e.message}');
    stderr.writeln(parser.usage);
    exit(1);
  } catch (e) {
    stderr.writeln('❌ Error: $e');
    exit(1);
  }
}

Future<void> _runInit(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('project-path',
        abbr: 'p', help: 'Path to Flutter project to scan', mandatory: true)
    ..addOption('output',
        abbr: 'o',
        help: 'Output path for the generated ethos.yaml.\n'
            'Defaults to <project-path>/ethos.yaml')
    ..addFlag('help', abbr: 'h', help: 'Show help', negatable: false);

  try {
    final results = parser.parse(arguments);
    if (results['help'] as bool) {
      _printInitHelp(parser);
      exit(0);
    }

    final projectPath = results['project-path'] as String;
    final sep = Platform.pathSeparator;
    final outputPath =
        results['output'] as String? ?? '$projectPath${sep}ethos.yaml';

    print('🔍 Scanning $projectPath for custom widgets and color tokens...');

    final dir = Directory(projectPath);
    if (!await dir.exists()) {
      stderr.writeln('❌ Project path not found: $projectPath');
      exit(1);
    }

    final files = <ParsedFile>[];
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      final path = entity.path;
      if (!path.endsWith('.dart')) {
        continue;
      }
      if (path.endsWith('.g.dart') ||
          path.endsWith('.freezed.dart') ||
          path.endsWith('.gr.dart') ||
          path.contains('${sep}generated$sep') ||
          path.contains('$sep.dart_tool$sep') ||
          path.contains('${sep}build$sep')) {
        continue;
      }
      try {
        final source = await entity.readAsString();
        files.add(parseDartFile(path, source));
      } catch (_) {}
    }

    print('   Scanned ${files.length} Dart files');

    final result = WidgetDiscovery.discover(files);

    if (result.isEmpty) {
      print('');
      print('ℹ️  No custom widgets or color expressions found '
          '(threshold: ${WidgetDiscovery.minUsages}+ uses).');
      print('   Your project uses only standard Flutter/Material widgets.');
      print('   Ethos can already analyze it without any configuration.');
      exit(0);
    }

    print('   Found ${result.totalWidgets} custom widget(s), '
        '${result.totalColors} color expression(s)');
    print('');

    final outputFile = File(outputPath);
    if (await outputFile.exists()) {
      stdout.write('⚠️  $outputPath already exists. Overwrite? [y/N] ');
      final response = stdin.readLineSync()?.trim().toLowerCase() ?? '';
      if (response != 'y' && response != 'yes') {
        print('Cancelled. Existing ethos.yaml was not modified.');
        exit(0);
      }
    }

    final yaml = EthosYamlGenerator.generate(
      result,
      projectPath: projectPath,
    );

    await outputFile.writeAsString(yaml);

    print('✅ Generated: $outputPath');
    print('');

    if (result.totalWidgets > 0) {
      print('📦 Custom widgets (fill in role and label_arg):');
      for (final entry in result.widgetUsages.entries) {
        print('   ${entry.key.padRight(30)} ${entry.value} uses');
      }
      print('');
    }

    if (result.totalColors > 0) {
      print('🎨 Color expressions (add hex values to enable contrast checks):');
      for (final entry in result.colorExpressions.entries) {
        print('   ${entry.key.padRight(40)} ${entry.value} uses');
      }
      print('');
    }

    print('Next steps:');
    print('  1. Open $outputPath');
    print('  2. Set role: for each widget_alias');
    print(
        '  3. Uncomment label_arg, size_guaranteed, keyboard_ready as needed');
    print('  4. Fill in hex values under color_aliases');
    print('  5. Run: ethos -p $projectPath -v');
  } on FormatException catch (e) {
    stderr.writeln('❌ Invalid arguments: ${e.message}');
    stderr.writeln(parser.usage);
    exit(1);
  } catch (e) {
    stderr.writeln('❌ Error: $e');
    exit(1);
  }
}

String _progressBar(int current, int total) {
  const width = 15;
  final filled = (current / total * width).round();
  return '[${'█' * filled}${'░' * (width - filled)}]';
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
    buffer.writeln('   Coverage: ${c.percentage.toStringAsFixed(2)}% '
        '(${c.matched}/${c.total}) [$status]');
    if (c.indeterminate > 0) {
      buffer.writeln('   ⓘ  ${c.indeterminate} indeterminate '
          '(value resolved at runtime — not counted)');
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
    buffer.writeln('| ${c.title} | ${c.percentage.toStringAsFixed(2)}% '
        '(${c.matched}/${c.total}) | $ind | $status |');
  }
  final allFindings = [for (final c in report.coverage.values) ...c.findings];
  if (allFindings.isNotEmpty) {
    buffer.writeln('');
    buffer.writeln('## Findings');
    buffer.writeln('');
    for (final f in allFindings) {
      final tag = f.severity == FindingSeverity.indeterminate ? 'ⓘ' : '✗';
      buffer.writeln('- $tag `${f.filePath}:${f.line}:${f.column}` '
          '— **${f.widgetType}** — ${f.message}');
    }
  }
  return buffer.toString();
}

String _generateCoverageReport(CoverageReport report) {
  final buffer = StringBuffer();
  buffer.writeln(
      'Overall Coverage: **${report.overallCoverage.toStringAsFixed(2)}%**');
  buffer.writeln('Compliance Level: **${report.complianceLevel}**');
  buffer.writeln('');
  for (final c in report.coverage.values) {
    buffer.writeln('### ${c.title}');
    buffer.writeln('- Coverage: ${c.percentage.toStringAsFixed(2)}%');
    buffer.writeln('- Matched: ${c.matched}/${c.total}');
    if (c.indeterminate > 0) {
      buffer.writeln('- Indeterminate: ${c.indeterminate}');
    }
    buffer.writeln(
        '- Status: ${c.isCritical ? "CRITICAL" : (c.total == 0 ? "NO DATA" : "OK")}');
    buffer.writeln('');
  }
  return buffer.toString();
}

void _printAnalyzeHelp(ArgParser parser) {
  print('Ethos — Accessibility Coverage Analyzer');
  print('');
  print('Usage: ethos -p <project-path> [options]');
  print('       ethos init -p <project-path>    (generate starter ethos.yaml)');
  print('');
  print('Examples:');
  print('  ethos -p ./my_app');
  print('  ethos -p ./my_app --deep');
  print('  ethos -p ./my_app --deep -v');
  print('  ethos -p ./my_app -r json -o report.json');
  print('  ethos -p ./my_app -r markdown -o report.md');
  print('  ethos init -p ./my_app');
  print('');
  print('Options:');
  print(parser.usage);
}

void _printInitHelp(ArgParser parser) {
  print('Ethos init — Generate a starter ethos.yaml');
  print('');
  print('Scans your project for custom widgets and color expressions,');
  print('then generates an ethos.yaml with the most-used ones pre-filled.');
  print('');
  print('Usage: ethos init -p <project-path> [options]');
  print('');
  print('Examples:');
  print('  ethos init -p ./my_app');
  print('  ethos init -p ./my_app -o config/ethos.yaml');
  print('');
  print('Options:');
  print(parser.usage);
}
