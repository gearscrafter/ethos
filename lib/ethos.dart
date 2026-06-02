/// Ethos — Measure accessibility coverage in Flutter apps using WCAG 2.2
/// specifications with Spec-Driven Development.
///
/// ## Usage
///
/// ```dart
/// import 'package:ethos/ethos.dart';
///
/// void main() async {
///   final analyzer = await CoverageAnalyzer.loadFromFile(
///     'specs/v1.0.0/wcag_2_2.yaml',
///   );
///   final report = await analyzer.analyze(projectPath: './my_flutter_app');
///   print('Overall coverage: ${report.overallCoverage}%');
///   print('Compliance level: ${report.complianceLevel}');
/// }
/// ```
library ethos;

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
