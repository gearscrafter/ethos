/// Test utilities for Ethos — matchers and helpers for use in
/// `dart test` or `flutter_test` suites.
///
/// Import this in test files only:
///
/// ```dart
/// // In your test file:
/// import 'package:ethos/ethos_test.dart';
/// import 'package:test/test.dart';
///
/// void main() {
///   group('Accessibility', () {
///     late CoverageReport report;
///
///     setUpAll(() async {
///       report = await EthosTestHelper.analyzeProject('lib/');
///     });
///
///     test('meets WCAG Level A', () {
///       expect(report, meetsAccessibilityLevel(WcagLevel.a));
///     });
///
///     test('semantic labels above 80%', () {
///       expect(report, hasRuleCoverage(
///         'wcag_1_3_1_semantics_label',
///         greaterThan(80),
///       ));
///     });
///
///     test('no critical failures', () {
///       expect(report, hasNoCriticalFailures());
///     });
///   });
/// }
/// ```
///
/// Do NOT import this in production code — use `package:ethos/ethos.dart`
/// for the main API.
library;

export 'src/testing/ethos_test_helper.dart';
export 'src/testing/matchers.dart';

export 'src/models/coverage_report.dart';
