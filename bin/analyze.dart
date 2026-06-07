import 'dart:async';
import 'dart:io';
import 'package:args/args.dart';
import 'package:ethos/ethos.dart';
import 'package:ethos/src/update_checker.dart';

/// Ethos CLI entry point.
///
/// Supports three subcommands:
///   ethos -p `<path>` [options]          — run accessibility analysis
///   ethos init -p `<path>` [options]     — generate starter ethos.yaml
///   ethos watch -p `<path>` [options]    — watch for changes and re-analyze
void main(List<String> arguments) async {
  if (arguments.isNotEmpty &&
      (arguments.first == '--version' ||
          arguments.first == '-V' ||
          arguments.first == 'version')) {
    stdout.writeln('ethos $kEthosVersion');
    return;
  }

  final updateChecker = UpdateChecker();
  final fetchFuture = updateChecker.fetch();

  if (arguments.isNotEmpty && arguments.first == 'init') {
    await _runInit(arguments.sublist(1));
    await fetchFuture;
    updateChecker.printUpdateHintIfNeeded();
    return;
  }

  if (arguments.isNotEmpty && arguments.first == 'watch') {
    await _runWatch(arguments.sublist(1));
    return; // watch runs forever — no update hint
  }

  await _runAnalyze(arguments, updateChecker, fetchFuture);
}

Future<void> _runAnalyze(List<String> arguments, UpdateChecker updateChecker,
    Future<void> fetchFuture) async {
  final parser = ArgParser()
    ..addOption('project-path',
        abbr: 'p',
        help: 'Path to Flutter project to analyze (default: current directory)')
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
    ..addFlag('suggest',
        abbr: 's',
        help: 'Show step-by-step suggestions to make indeterminate findings '
            'verifiable by static analysis. Useful during development; '
            'not recommended for CI output.',
        negatable: false)
    ..addFlag('version',
        abbr: 'V', help: 'Print version and exit', negatable: false)
    ..addFlag('help', abbr: 'h', help: 'Show help message', negatable: false);

  try {
    final results = parser.parse(arguments);
    if (results['help'] as bool) {
      _printAnalyzeHelp(parser);
      exit(0);
    }
    if (results['version'] as bool) {
      stdout.writeln('ethos $kEthosVersion');
      exit(0);
    }

    final projectPath =
        (results['project-path'] as String?) ?? Directory.current.path;
    final configPath = results['config'] as String?;
    final reportType = results['report-type'] as String;
    final outputPath = results['output'] as String?;
    final deepMode = results['deep'] as bool;
    final verbose = results['verbose'] as bool;
    final suggest = results['suggest'] as bool;

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
        stderr.writeln(' Spec v${deepAnalyzer.spec.version} '
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
        stderr.writeln(' Spec v${analyzer.spec.version} '
            '(${analyzer.spec.rules.length} rules, '
            '${analyzer.spec.widgetAliases.length} aliases)');
        stderr.writeln(
            '   Detectors: ${analyzer.registry.registeredRuleIds.length}');
        stderr.writeln('🔍 Analyzing project...');
      }

      report = await analyzer.analyze();

      if (verbose) {
        stderr.writeln(
            ' Analysis complete (${report.coverage.length} rules evaluated)');
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
        reportOutput = _generateHumanReport(report, suggest: suggest);
    }

    if (outputPath != null) {
      await File(outputPath).writeAsString(reportOutput);
      stderr.writeln(' Report saved to: $outputPath');
    } else {
      stdout.writeln(reportOutput);
    }

    final hasCritical = report.coverage.values.any((c) => c.isCritical);
    await fetchFuture;
    updateChecker.printUpdateHintIfNeeded();
    if (hasCritical) {
      if (verbose) {
        stderr.writeln('\n  Critical coverage issues detected');
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
        abbr: 'p',
        help: 'Path to Flutter project to scan (default: current directory)')
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

    final projectPath =
        (results['project-path'] as String?) ?? Directory.current.path;
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
      print('  No custom widgets or color expressions found '
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

    final yaml = EthosYamlGenerator.generate(result, projectPath: projectPath);
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
    print('  5. Run: ethos -v');
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

const _reset = '\x1B[0m';
const _bold = '\x1B[1m';
const _red = '\x1B[31m';
const _green = '\x1B[32m';
const _yellow = '\x1B[33m';
const _blue = '\x1B[34m';
const _magenta = '\x1B[35m';
const _cyan = '\x1B[36m';
const _dim = '\x1B[2m';

String _c(String text, String color) => '$color$text$_reset';
String _b(String text) => '$_bold$text$_reset';

bool _supportsAnsi() => stdout.hasTerminal;

String _generateHumanReport(CoverageReport report, {bool suggest = false}) {
  final color = _supportsAnsi();
  final buffer = StringBuffer();

  final header = color
      ? '$_bold$_cyan╔════════════════════════════════════════════════╗$_reset\n'
          '$_bold$_cyan║  Accessibility Coverage Report                 ║$_reset\n'
          '$_bold$_cyan║  Spec v${report.specVersion}${''.padRight(41 - report.specVersion.length)}║$_reset'
          '\n$_bold$_cyan╚════════════════════════════════════════════════╝$_reset'
      : '${'╔════════════════════════════════════════════════╗\n'
          '║  Accessibility Coverage Report                 ║\n'
          '║  Spec v${report.specVersion}'.padRight(49)}║\n╚════════════════════════════════════════════════╝';
  buffer.writeln(header);
  buffer.writeln('');

  buffer.writeln(color ? _b('📊 Summary') : '📊 Summary');
  buffer.writeln('─' * 50);

  final pct = report.overallCoverage;
  final pctStr = '${pct.toStringAsFixed(2)}%';
  final pctColored = color
      ? (pct >= 85
          ? _c(pctStr, _green)
          : pct >= 70
              ? _c(pctStr, _yellow)
              : _c(pctStr, _red))
      : pctStr;

  final level = report.complianceLevel;
  final levelColored = color
      ? (level == 'AAA' || level == 'AA' || level == 'A'
          ? _c(level, _green)
          : _c(level, _red))
      : level;

  buffer.writeln('Overall Coverage: $pctColored');
  buffer.writeln('Compliance Level: ${color ? _b(levelColored) : level}');
  buffer.writeln('Project: ${report.projectPath}');
  buffer.writeln(
      'Analyzed: ${color ? _c(report.timestamp.toIso8601String(), _dim) : report.timestamp.toIso8601String()}');
  buffer.writeln('');

  buffer.writeln(color ? _b('📋 Coverage by Rule') : '📋 Coverage by Rule');
  buffer.writeln('─' * 50);

  for (final c in report.coverage.values) {
    final isCritical = c.isCritical;
    final noData = c.total == 0;
    final icon = isCritical ? '⚠️ ' : (noData ? 'ℹ️ ' : '✅');
    final status = isCritical ? 'CRITICAL' : (noData ? 'NO DATA' : 'OK');
    final titleStr = color
        ? (isCritical
            ? _c(c.title, _red)
            : noData
                ? _c(c.title, _cyan)
                : _c(c.title, _green))
        : c.title;
    final statusStr = color
        ? (isCritical
            ? _c('[$status]', _red)
            : noData
                ? _c('[$status]', _cyan)
                : _c('[$status]', _green))
        : '[$status]';
    buffer.writeln('$icon ${color ? _b(titleStr) : titleStr}');
    buffer.writeln(
        '   Coverage: ${c.percentage.toStringAsFixed(2)}% (${c.matched}/${c.total}) $statusStr');
    if (noData && c.indeterminate == 0) {
      final noDataHint = _noDataHint(c.ruleId);
      buffer.writeln('   ${color ? _c(noDataHint, _dim) : noDataHint}');
    }
    if (c.indeterminate > 0) {
      final hint = _indeterminateHint(c.ruleId);
      final indStr = 'ⓘ  ${c.indeterminate} indeterminate — $hint';
      buffer.writeln('   ${color ? _c(indStr, _dim) : indStr}');
    }
    buffer.writeln('');
  }

  final allFindings = [for (final c in report.coverage.values) ...c.findings];
  if (allFindings.isNotEmpty) {
    buffer.writeln(color
        ? _b('🔎 Findings (${allFindings.length})')
        : '🔎 Findings (${allFindings.length})');
    buffer.writeln('─' * 50);

    for (final c in report.coverage.values) {
      if (c.findings.isEmpty) {
        continue;
      }

      final ruleColor = _ruleColor(c.ruleId);
      final ruleIcon = _ruleIcon(c.ruleId);

      final ruleHeader = '$ruleIcon ${c.title} (${c.findings.length})';
      buffer.writeln(color ? _b(_c(ruleHeader, ruleColor)) : ruleHeader);

      for (final f in c.findings) {
        final isIndet = f.severity == FindingSeverity.indeterminate;
        if (isIndet) {
          final tag = color ? _c('  ⓘ', _cyan) : '  ⓘ';
          final loc = color
              ? _c('${f.filePath}:${f.line}:${f.column}', _dim)
              : '${f.filePath}:${f.line}:${f.column}';
          buffer.writeln('$tag $loc');
          buffer.writeln(
              '     ${color ? _c(f.widgetType, _cyan) : f.widgetType} — ${f.message}');
        } else {
          final tag = color ? _c('  ✗', ruleColor) : '  ✗';
          final loc = color
              ? '${_c(f.filePath, _dim)}${_c(':${f.line}:${f.column}', _yellow)}'
              : '${f.filePath}:${f.line}:${f.column}';
          buffer.writeln('$tag $loc');
          buffer.writeln(
              '     ${color ? _c(f.widgetType, ruleColor) : f.widgetType} — ${f.message}');
        }
      }
      buffer.writeln('');
    }
  }

  if (report.issues.isNotEmpty) {
    buffer.writeln(
        color ? _c('⚠️  Engine Issues', _yellow) : '⚠️  Engine Issues');
    buffer.writeln('─' * 50);
    for (final issue in report.issues) {
      buffer.writeln('• ${color ? _c(issue, _yellow) : issue}');
    }
  }

  if (suggest) {
    final suggestions = SuggestionEngine.generate(report);
    buffer.writeln('');
    if (suggestions.isEmpty) {
      buffer.writeln(color ? _b('💡 Suggestions') : '💡 Suggestions');
      buffer.writeln('─' * 50);
      buffer.writeln('  No indeterminate findings — nothing to suggest. ✅');
    } else {
      buffer.writeln(color ? _b('💡 Suggestions') : '💡 Suggestions');
      buffer.writeln('─' * 50);
      buffer.writeln(color
          ? _c(
              '  How to make indeterminate findings verifiable by static '
              'analysis on the next run:',
              _dim)
          : '  How to make indeterminate findings verifiable by static '
              'analysis on the next run:');
      buffer.writeln('');

      for (final s in suggestions) {
        final ruleColor = _ruleColor(s.ruleId);
        final header = '${_ruleIcon(s.ruleId)} ${s.ruleTitle} '
            '(${s.indeterminateCount} indeterminate)';
        buffer.writeln(color ? _b(_c(header, ruleColor)) : header);
        buffer.writeln('  ${color ? _c(s.problem, _dim) : s.problem}');
        buffer.writeln('');

        for (var j = 0; j < s.fixes.length; j++) {
          final fix = s.fixes[j];
          buffer.writeln(color ? '  ${_b(fix.label)}' : '  ${fix.label}');
          buffer.writeln(
              '  ${color ? _c(fix.description, _dim) : fix.description}');

          if (fix.codeExample != null) {
            buffer.writeln('');
            for (final line in fix.codeExample!.trim().split('\n')) {
              buffer.writeln(color ? '    ${_c(line, _dim)}' : '    $line');
            }
          }
          if (fix.yamlExample != null) {
            buffer.writeln('');
            for (final line in fix.yamlExample!.trim().split('\n')) {
              buffer.writeln(color ? '    ${_c(line, _cyan)}' : '    $line');
            }
          }
          if (j < s.fixes.length - 1) {
            buffer.writeln('');
          }
        }
        buffer.writeln('');
      }
    }
  } else {
    final totalIndeterminate =
        report.coverage.values.fold(0, (sum, c) => sum + c.indeterminate);
    if (totalIndeterminate > 0) {
      buffer.writeln('');
      buffer.writeln(color
          ? _c(
              '  💡 Run with --suggest to get step-by-step fixes for '
              '$totalIndeterminate indeterminate finding(s).',
              _dim)
          : '  💡 Run with --suggest to get step-by-step fixes for '
              '$totalIndeterminate indeterminate finding(s).');
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
  print('Ethos $kEthosVersion — Accessibility Coverage Analyzer');
  print('');
  print(
      'Usage: ethos [options]                     (analyzes current directory)');
  print('       ethos -p <project-path> [options]');
  print(
      '       ethos init                          (generate starter ethos.yaml)');
  print('       ethos watch                         (watch for changes)');
  print('       ethos --version                     (print version)');
  print('');
  print('Examples:');
  print('  ethos                        # analyze current directory');
  print('  ethos --deep -v              # deep mode in current directory');
  print(
      '  ethos --suggest              # show fixes for indeterminate findings');
  print('  ethos --deep --suggest       # deep mode + suggestions');
  print('  ethos -p ./my_app');
  print('  ethos -p ./my_app --deep -v');
  print('  ethos -p ./my_app -r json -o report.json');
  print('  ethos -p ./my_app -r markdown -o report.md');
  print('  ethos init');
  print('  ethos watch');
  print('  ethos watch --deep');
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
  print('Usage: ethos init [options]');
  print('');
  print('Examples:');
  print('  ethos init');
  print('  ethos init -p ./my_app');
  print('  ethos init -p ./my_app -o config/ethos.yaml');
  print('');
  print('Options:');
  print(parser.usage);
}

Future<void> _runWatch(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('project-path',
        abbr: 'p',
        help: 'Path to Flutter project to watch (default: current directory)')
    ..addOption('config',
        abbr: 'c', help: 'Path to a custom ethos.yaml (default: auto-detect).')
    ..addFlag('deep',
        abbr: 'd',
        help: 'Use deep analysis on each change (slower, more precise).',
        defaultsTo: false)
    ..addFlag('help', abbr: 'h', help: 'Show help', negatable: false);

  try {
    final results = parser.parse(arguments);
    if (results['help'] as bool) {
      _printWatchHelp(parser);
      exit(0);
    }

    final projectPath =
        (results['project-path'] as String?) ?? Directory.current.path;
    final configPath = results['config'] as String?;
    final deepMode = results['deep'] as bool;
    final sep = Platform.pathSeparator;

    stderr.writeln('👁  Ethos Watch');
    stderr.writeln('  Project: $projectPath');
    stderr.writeln('  Mode: ${deepMode ? "deep 🔬" : "standard"}');
    stderr.writeln('  Watching: lib/, test/, example/');
    stderr.writeln('  Press Ctrl+C to stop.');
    stderr.writeln('');

    stderr.write('⏳ Initial scan...');
    final engine = await WatchEngine.forProject(
      projectPath,
      configPath: configPath,
      deepMode: deepMode,
    );

    final initialReport = await engine.initialScan(
      onProgress: (current, total, path) {
        stderr.write('\r⏳ Scanning [$current/$total] '
            '${path.split(sep).last}          ');
      },
    );

    stderr.writeln('\r✅ Initial scan complete '
        '(${engine.cachedFileCount} files)          ');
    stderr.writeln('');

    _printWatchReport(initialReport, diff: null, changedFile: null);

    final watchDirs = ['lib', 'test', 'example']
        .map((d) => Directory('$projectPath$sep$d'))
        .where((d) => d.existsSync())
        .toList();

    if (watchDirs.isEmpty) {
      stderr.writeln('❌ No lib/, test/, or example/ found in $projectPath.');
      exit(1);
    }

    final Map<String, DateTime> lastEvent = {};
    const debounce = Duration(milliseconds: 300);

    final controller = StreamController<FileSystemEvent>();
    for (final dir in watchDirs) {
      dir
          .watch(events: FileSystemEvent.all, recursive: true)
          .listen(controller.add, onError: (_) {});
    }

    await for (final event in controller.stream) {
      final path = event.path;
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

      final now = DateTime.now();
      final last = lastEvent[path];
      if (last != null && now.difference(last) < debounce) {
        continue;
      }
      lastEvent[path] = now;

      final fileName = path.split(sep).last;
      final timeStr = _timeString(now);

      stderr.writeln('');
      stderr.writeln('─' * 50);
      stderr.writeln('🔄  $fileName changed ($timeStr)');
      stderr.writeln('─' * 50);
      stderr.writeln('');
      stderr.write('⏳ Re-analyzing...');

      try {
        final (newReport, diff) = await engine.reanalyzeFile(path);
        stderr.writeln('\r✅ Done                    ');
        stderr.writeln('');
        _printWatchReport(newReport, diff: diff, changedFile: fileName);
      } catch (e) {
        stderr.writeln('\r❌ Error: $e');
      }
    }
  } on FormatException catch (e) {
    stderr.writeln('❌ Invalid arguments: ${e.message}');
    stderr.writeln(parser.usage);
    exit(1);
  } catch (e) {
    stderr.writeln('❌ Error: $e');
    exit(1);
  }
}

void _printWatchReport(
  CoverageReport report, {
  required ReportDiff? diff,
  required String? changedFile,
}) {
  final overallStr = report.overallCoverage.toStringAsFixed(1).padLeft(5);
  final deltaStr = diff != null && diff.overallDelta.abs() > 0.01
      ? _deltaStr(diff.overallDelta)
      : '';

  stdout.writeln('📊 Overall: $overallStr%  $deltaStr'
      ' · Compliance: ${report.complianceLevel}');
  stdout.writeln('');

  for (final c in report.coverage.values) {
    final icon = c.isCritical ? '⚠️ ' : (c.total == 0 ? 'ℹ️ ' : '✅');
    final pct = '${c.percentage.toStringAsFixed(1)}%'.padLeft(6);
    final counts = c.total > 0 ? '(${c.matched}/${c.total})' : '     ';
    final ruleDelta = diff?.ruleDelta[c.ruleId];
    final ruleTag = ruleDelta != null && ruleDelta.abs() > 0.01
        ? '  ${_deltaStr(ruleDelta)}'
        : '';
    final ind = c.indeterminate > 0 ? '  ⓘ ${c.indeterminate}' : '';
    stdout.writeln('$icon ${c.title.padRight(35)} $pct $counts$ruleTag$ind');
  }

  if (diff != null) {
    if (diff.newCritical.isNotEmpty) {
      stdout.writeln('');
      stdout.writeln('🔴 Went critical:');
      for (final id in diff.newCritical) {
        stdout.writeln('   • $id');
      }
    }
    if (diff.resolvedCritical.isNotEmpty) {
      stdout.writeln('');
      stdout.writeln('🟢 No longer critical:');
      for (final id in diff.resolvedCritical) {
        stdout.writeln('   • $id');
      }
    }
  }

  if (changedFile != null) {
    final fileFindings = [
      for (final c in report.coverage.values)
        ...c.findings.where((f) => f.filePath.endsWith(changedFile)),
    ];
    if (fileFindings.isNotEmpty) {
      stdout.writeln('');
      stdout.writeln('🔎 Findings in $changedFile:');
      for (final f in fileFindings) {
        final tag = f.severity == FindingSeverity.indeterminate ? 'ⓘ' : '✗';
        stdout.writeln('  $tag line ${f.line} — ${f.widgetType}: ${f.message}');
      }
    }
  }

  stdout.writeln('');
  stdout.writeln('Watching for changes... (Ctrl+C to stop)');
}

String _deltaStr(double delta) {
  final sign = delta >= 0 ? '▲' : '▼';
  return '$sign ${delta.abs().toStringAsFixed(1)}%';
}

String _timeString(DateTime dt) => '${dt.hour.toString().padLeft(2, '0')}:'
    '${dt.minute.toString().padLeft(2, '0')}:'
    '${dt.second.toString().padLeft(2, '0')}';

String _ruleColor(String ruleId) {
  switch (ruleId) {
    case 'wcag_1_3_1_semantics_label':
      return _magenta;
    case 'wcag_1_4_3_contrast_minimum':
      return _yellow;
    case 'wcag_2_5_5_target_size_enhanced':
      return _blue;
    case 'wcag_2_1_1_keyboard':
      return _cyan;
    case 'wcag_2_4_3_focus_order':
      return _cyan;
    case 'wcag_1_1_1_non_text_content':
      return _red;
    case 'wcag_1_4_4_resize_text':
      return _green;
    default:
      return _red;
  }
}

String _ruleIcon(String ruleId) {
  switch (ruleId) {
    case 'wcag_1_3_1_semantics_label':
      return '🏷️ ';
    case 'wcag_1_4_3_contrast_minimum':
      return '🎨';
    case 'wcag_2_5_5_target_size_enhanced':
      return '👆';
    case 'wcag_2_1_1_keyboard':
      return '⌨️ ';
    case 'wcag_2_4_3_focus_order':
      return '🔀';
    case 'wcag_1_1_1_non_text_content':
      return '🖼️ ';
    case 'wcag_1_4_4_resize_text':
      return '🔤';
    default:
      return '⚠️ ';
  }
}

String _indeterminateHint(String ruleId) {
  switch (ruleId) {
    case 'wcag_1_4_3_contrast_minimum':
      return 'colors from Theme or variables — '
          'add hex values to color_aliases in ethos.yaml, '
          'or run with --deep to resolve cross-file references';
    case 'wcag_1_3_1_semantics_label':
      return 'labels are runtime variables — '
          'static analysis cannot verify these; '
          'runtime verification is on the Ethos roadmap';
    case 'wcag_2_5_5_target_size_enhanced':
      return 'size depends on layout constraints at runtime — '
          'WCAG 2.5.5 exempts targets whose size is determined by the layout '
          'engine (animations, full-screen regions, inherited constraints). '
          'For verifiable targets, wrap in SizedBox(width:48, height:48) '
          'or declare size_guaranteed: true in ethos.yaml. '
          'Remaining cases require runtime measurement (ethos_runtime, roadmap)';
    case 'wcag_1_1_1_non_text_content':
      return 'labels are runtime variables — '
          'use literal strings in semanticLabel or Semantics(label:) '
          'where possible';
    case 'wcag_1_4_4_resize_text':
      return 'scale factor is a variable — '
          'ensure it is never clamped below 1.0';
    default:
      return 'value resolved at runtime — not counted in coverage score';
  }
}

String _noDataHint(String ruleId) {
  switch (ruleId) {
    case 'wcag_1_4_3_contrast_minimum':
      return 'no Text with inline color literals found — '
          'add color_aliases in ethos.yaml to enable contrast checks';
    case 'wcag_1_4_4_resize_text':
      return '✓ no hardcoded textScaleFactor found — '
          'your project respects system font-size preferences';
    case 'wcag_2_5_5_target_size_enhanced':
      return 'no GestureDetector/InkWell with measurable size found — '
          'use SizedBox or add widget_aliases in ethos.yaml';
    default:
      return 'no widgets in scope found in this project';
  }
}

void _printWatchHelp(ArgParser parser) {
  print('Ethos watch — Watch for changes and re-analyze on save');
  print('');
  print('Performs an initial full scan, then re-analyzes only the');
  print('file that changed. Prints the full report after each change.');
  print('');
  print('Usage: ethos watch [options]');
  print('');
  print('Examples:');
  print('  ethos watch');
  print('  ethos watch --deep');
  print('  ethos watch -p ./my_app');
  print('');
  print('Options:');
  print(parser.usage);
}
