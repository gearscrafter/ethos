import 'dart:async';
import 'dart:io';
import 'package:args/args.dart';
import 'package:ethos/ethos.dart';

/// Ethos CLI entry point.
///
/// Supports three subcommands:
///   ethos -p `<path>` [options]          — run accessibility analysis
///   ethos init -p `<path>` [options]     — generate starter ethos.yaml
///   ethos watch -p `<path>` [options]    — watch for changes and re-analyze
void main(List<String> arguments) async {
  if (arguments.isNotEmpty && arguments.first == 'init') {
    await _runInit(arguments.sublist(1));
    return;
  }

  if (arguments.isNotEmpty && arguments.first == 'watch') {
    await _runWatch(arguments.sublist(1));
    return;
  }

  await _runAnalyze(arguments);
}

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
        stderr.writeln('Spec v${deepAnalyzer.spec.version} '
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
        stderr.writeln(' Deep analysis did not complete.');
        exit(1);
      }
      report = reportHolder!;
    } else {
      late final CoverageAnalyzer analyzer;
      try {
        analyzer = await CoverageAnalyzer.forProject(
          projectPath,
          configPath: configPath,
        );
      } catch (e) {
        stderr.writeln(' Error loading spec: $e');
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
        reportOutput = _generateHumanReport(report);
    }

    if (outputPath != null) {
      await File(outputPath).writeAsString(reportOutput);
      stderr.writeln(' Report saved to: $outputPath');
    } else {
      stdout.writeln(reportOutput);
    }

    final hasCritical = report.coverage.values.any((c) => c.isCritical);
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
      stderr.writeln(' Project path not found: $projectPath');
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

    final yaml = EthosYamlGenerator.generate(
      result,
      projectPath: projectPath,
    );

    await outputFile.writeAsString(yaml);

    print(' Generated: $outputPath');
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

const _reset = '\x1B[0m';
const _bold = '\x1B[1m';
const _red = '\x1B[31m';
const _green = '\x1B[32m';
const _yellow = '\x1B[33m';
const _cyan = '\x1B[36m';
const _white = '\x1B[37m';
const _dim = '\x1B[2m';

String _c(String text, String color) => '$color$text$_reset';
String _b(String text) => '$_bold$text$_reset';

bool _supportsAnsi() {
  return stdout.hasTerminal;
}

String _generateHumanReport(CoverageReport report) {
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
    final pctRuleStr =
        '${c.percentage.toStringAsFixed(2)}% (${c.matched}/${c.total})';

    buffer.writeln('$icon ${color ? _b(titleStr) : titleStr}');
    buffer.writeln('   Coverage: $pctRuleStr $statusStr');
    if (c.indeterminate > 0) {
      final indStr =
          'ⓘ  ${c.indeterminate} indeterminate (value resolved at runtime — not counted)';
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
    for (final f in allFindings) {
      final isIndet = f.severity == FindingSeverity.indeterminate;
      if (isIndet) {
        final tag = color ? _c('ⓘ INDETERMINATE', _cyan) : 'ⓘ INDETERMINATE';
        final loc = color
            ? _c('${f.filePath}:${f.line}:${f.column}', _dim)
            : '${f.filePath}:${f.line}:${f.column}';
        buffer.writeln('$tag $loc');
        buffer.writeln(
            '   ${color ? _c(f.widgetType, _cyan) : f.widgetType} — ${f.message}');
      } else {
        final tag = color ? _c('✗ FAIL', _red) : '✗ FAIL';
        final loc = color
            ? '${_c(f.filePath, _dim)}${_c(':${f.line}:${f.column}', _yellow)}'
            : '${f.filePath}:${f.line}:${f.column}';
        buffer.writeln('$tag  $loc');
        buffer.writeln(
            '   ${color ? _b(_c(f.widgetType, _red)) : f.widgetType} — ${f.message}');
      }
    }
    buffer.writeln('');
  }

  if (report.issues.isNotEmpty) {
    buffer.writeln(
        color ? _c('⚠️  Engine Issues', _yellow) : '⚠️  Engine Issues');
    buffer.writeln('─' * 50);
    for (final issue in report.issues) {
      buffer.writeln('• ${color ? _c(issue, _yellow) : issue}');
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

Future<void> _runWatch(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('project-path',
        abbr: 'p', help: 'Path to Flutter project to watch', mandatory: true)
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

    final projectPath = results['project-path'] as String;
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

    // Watch lib/, test/, and example/ if they exist.
    final watchDirs = ['lib', 'test', 'example']
        .map((d) => Directory('$projectPath$sep$d'))
        .where((d) => d.existsSync())
        .toList();

    if (watchDirs.isEmpty) {
      stderr.writeln('❌ No lib/, test/, or example/ found in $projectPath.');
      exit(1);
    }

    // Debounce: ignore rapid successive events on the same file.
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

      // Debounce.
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
        stderr.writeln('\r Done                    ');
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
  // Overall summary line.
  final overallStr = report.overallCoverage.toStringAsFixed(1).padLeft(5);
  final deltaStr = diff != null && diff.overallDelta.abs() > 0.01
      ? _deltaStr(diff.overallDelta)
      : '';

  stdout.writeln('📊 Overall: $overallStr%  $deltaStr'
      ' · Compliance: ${report.complianceLevel}');
  stdout.writeln('');

  // Per-rule compact table.
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

void _printWatchHelp(ArgParser parser) {
  print('Ethos watch — Watch for changes and re-analyze on save');
  print('');
  print('Performs an initial full scan, then re-analyzes only the');
  print('file that changed. Prints the full report after each change.');
  print('');
  print('Usage: ethos watch -p <project-path> [options]');
  print('');
  print('Examples:');
  print('  ethos watch -p ./my_app');
  print('  ethos watch -p ./my_app --deep');
  print('');
  print('Options:');
  print(parser.usage);
}
