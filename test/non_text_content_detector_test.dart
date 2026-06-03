import 'package:test/test.dart';
import 'package:ethos/ethos_test.dart';

void main() {
  group('NonTextContentDetector', () {
    group('Icon', () {
      test('with non-empty semanticLabel passes', () async {
        final r = await EthosTestHelper.analyzeSource(
          "Icon(Icons.search, semanticLabel: 'Search artifacts')",
        );
        final cov = r.coverage['wcag_1_1_1_non_text_content'];
        expect(cov?.matched, greaterThan(0));
        expect(cov?.findings, isEmpty);
      });

      test('without semanticLabel fails', () async {
        final r = await EthosTestHelper.analyzeSource(
          'Icon(Icons.close)',
        );
        final cov = r.coverage['wcag_1_1_1_non_text_content'];
        expect(cov?.findings, isNotEmpty);
      });

      test('with empty semanticLabel fails', () async {
        final r = await EthosTestHelper.analyzeSource(
          "Icon(Icons.close, semanticLabel: '')",
        );
        final cov = r.coverage['wcag_1_1_1_non_text_content'];
        expect(cov?.findings, isNotEmpty);
      });

      test('with runtime semanticLabel is indeterminate', () async {
        final r = await EthosTestHelper.analyzeSource(
          'Icon(Icons.close, semanticLabel: iconLabel)',
        );
        final cov = r.coverage['wcag_1_1_1_non_text_content'];
        expect(cov?.indeterminate, greaterThan(0));
      });
    });

    group('Image', () {
      test('with Semantics label passes', () async {
        final r = await EthosTestHelper.analyzeSource('''
          Semantics(
            label: 'Photo of the Colosseum',
            child: Image.network('https://example.com/img.jpg'),
          )
        ''');
        final cov = r.coverage['wcag_1_1_1_non_text_content'];
        expect(cov?.matched, greaterThan(0));
        expect(cov?.findings, isEmpty);
      });

      test('with excludeFromSemantics passes (decorative)', () async {
        final r = await EthosTestHelper.analyzeSource(
          "Image.asset('assets/bg.png', excludeFromSemantics: true)",
        );
        final cov = r.coverage['wcag_1_1_1_non_text_content'];
        expect(cov?.matched, greaterThan(0));
        expect(cov?.findings, isEmpty);
      });

      test('without label or excludeFromSemantics fails', () async {
        final r = await EthosTestHelper.analyzeSource(
          "Image.network('https://example.com/artifact.jpg')",
        );
        final cov = r.coverage['wcag_1_1_1_non_text_content'];
        expect(cov?.findings, isNotEmpty);
      });

      test('with empty Semantics label fails', () async {
        final r = await EthosTestHelper.analyzeSource('''
          Semantics(
            label: '',
            child: Image.network('https://example.com/img.jpg'),
          )
        ''');
        final cov = r.coverage['wcag_1_1_1_non_text_content'];
        expect(cov?.findings, isNotEmpty);
      });
    });
  });
}
