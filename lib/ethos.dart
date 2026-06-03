/// Ethos — Measure accessibility coverage in Flutter apps using WCAG 2.2
/// specifications with Spec-Driven Development.
///
/// ## Usage
///
/// ```dart
/// import 'package:ethos/ethos.dart';
///
/// void main() async {
///   // Built-in WCAG 2.2 spec + optional ethos.yaml auto-merge.
///   final analyzer = await CoverageAnalyzer.forProject('./my_flutter_app');
///   final report = await analyzer.analyze();
///   print('Overall coverage: ${report.overallCoverage}%');
///   print('Compliance level: ${report.complianceLevel}');
/// }
/// ```
library;

// Models
export 'src/models/spec.dart';
export 'src/models/coverage_report.dart';
export 'src/models/ethos_config.dart';

// Analyzer
export 'src/analyzer/coverage_analyzer.dart';
export 'src/analyzer/spec_loader.dart';
export 'src/analyzer/detector_registry.dart';
export 'src/analyzer/rule_detector.dart';
export 'src/analyzer/ast/widget_visitor.dart';

// Detectors
export 'src/analyzer/detectors/semantic_labels_detector.dart';
export 'src/analyzer/detectors/contrast_detector.dart';
export 'src/analyzer/detectors/touch_target_detector.dart';
export 'src/analyzer/detectors/keyboard_detector.dart';
export 'src/analyzer/detectors/focus_order_detector.dart';
export 'src/analyzer/utils/color_resolver.dart';
export 'src/analyzer/utils/theme_extractor.dart';

// Deep analysis
export 'src/analyzer/deep/deep_analyzer.dart';
export 'src/analyzer/deep/deep_detector.dart';
export 'src/analyzer/deep/analysis_progress.dart';
export 'src/analyzer/deep/resolved_file.dart';
export 'src/analyzer/deep/detectors/cross_file_semantic_labels_detector.dart';
export 'src/analyzer/deep/detectors/resolved_contrast_detector.dart';

// Watch mode
export 'src/analyzer/watch/watch_engine.dart';

// Init
export 'src/analyzer/init/widget_discovery.dart';
export 'src/analyzer/init/ethos_yaml_generator.dart';
