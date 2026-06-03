import 'package:test/test.dart';
import 'package:ethos/ethos_test.dart';

void main() {
  group('ResizeTextDetector', () {
    group('Text without scale override', () {
      test('has no data — correct by default', () async {
        final r = await EthosTestHelper.analyzeSource("Text('Hello')");
        final cov = r.coverage['wcag_1_4_4_resize_text'];
        expect(cov?.total, equals(0));
      });

      test('with fontSize but no scale override has no data', () async {
        final r = await EthosTestHelper.analyzeSource(
          "Text('Hello', style: TextStyle(fontSize: 16))",
        );
        final cov = r.coverage['wcag_1_4_4_resize_text'];
        expect(cov?.total, equals(0));
      });
    });

    group('hardcoded textScaleFactor', () {
      test('literal 1.0 fails', () async {
        final r = await EthosTestHelper.analyzeSource(
          "Text('Hello', textScaleFactor: 1.0)",
        );
        final cov = r.coverage['wcag_1_4_4_resize_text'];
        expect(cov?.findings, isNotEmpty);
      });

      test('null is pass (explicit default)', () async {
        final r = await EthosTestHelper.analyzeSource(
          "Text('Hello', textScaleFactor: null)",
        );
        expect(r, passesRule('wcag_1_4_4_resize_text'));
      });

      test('variable is indeterminate', () async {
        final r = await EthosTestHelper.analyzeSource(
          "Text('Hello', textScaleFactor: scaleFactor)",
        );
        final cov = r.coverage['wcag_1_4_4_resize_text'];
        expect(cov?.indeterminate, greaterThan(0));
      });
    });

    group('TextScaler', () {
      test('TextScaler.noScaling fails', () async {
        final r = await EthosTestHelper.analyzeSource(
          "Text('Hello', textScaler: TextScaler.noScaling)",
        );
        final cov = r.coverage['wcag_1_4_4_resize_text'];
        expect(cov?.findings, isNotEmpty);
      });

      test('TextScaler.linear with literal fails', () async {
        final r = await EthosTestHelper.analyzeSource(
          "Text('Hello', textScaler: TextScaler.linear(1.0))",
        );
        final cov = r.coverage['wcag_1_4_4_resize_text'];
        expect(cov?.findings, isNotEmpty);
      });
    });
  });
}
