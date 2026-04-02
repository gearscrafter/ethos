/// Accessibility Coverage
///
/// Measure accessibility coverage in Flutter apps using WCAG 2.2 specifications
/// with Spec-Driven Development.
///
/// ## Usage
///
/// ```dart
/// import 'package:accessibility_coverage/accessibility_coverage.dart';
///
/// void main() async {
///   // Load analyzer with specs
///   final analyzer = await CoverageAnalyzer.loadFromFile(
///     'specs/v1.0.0/wcag_2_2.yaml'
///   );
///
///   // Analyze a project
///   final report = await analyzer.analyze(
///     projectPath: './my_flutter_app'
///   );
///
///   // Use results
///   print('Overall coverage: ${report.overallCoverage}%');
///   print('Compliance level: ${report.complianceLevel}');
/// }
/// ```
library ethos;

// Models
export 'src/models/spec.dart';
export 'src/models/coverage_report.dart';

// Analyzer
export 'src/analyzer/coverage_analyzer.dart';
export 'src/analyzer/spec_loader.dart';
