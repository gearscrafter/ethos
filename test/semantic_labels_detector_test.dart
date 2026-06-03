import 'package:test/test.dart';
import 'package:ethos/ethos_test.dart';

void main() {
  group('SemanticLabelsDetector', () {
    group('GestureDetector', () {
      test('with Semantics ancestor passes', () async {
        final r = await EthosTestHelper.analyzeSource('''
          Semantics(
            label: 'Open profile',
            child: GestureDetector(
              onTap: () => navigate(),
              child: Icon(Icons.person),
            ),
          )
        ''');
        expect(r, passesRule('wcag_1_3_1_semantics_label'));
      });

      test('with Semantics descendant passes', () async {
        final r = await EthosTestHelper.analyzeSource('''
          GestureDetector(
            onTap: () => navigate(),
            child: Semantics(label: 'Go to settings', child: Icon(Icons.settings)),
          )
        ''');
        expect(r, passesRule('wcag_1_3_1_semantics_label'));
      });

      test('without Semantics fails', () async {
        final r = await EthosTestHelper.analyzeSource('''
          GestureDetector(onTap: () => navigate(), child: Icon(Icons.settings))
        ''');
        final cov = r.coverage['wcag_1_3_1_semantics_label'];
        expect(cov?.findings, isNotEmpty);
      });

      test('with empty onTap block is excluded (non-interactive)', () async {
        final r = await EthosTestHelper.analyzeSource('''
          GestureDetector(onTap: () {}, child: Icon(Icons.close))
        ''');
        final cov = r.coverage['wcag_1_3_1_semantics_label'];
        expect(cov?.total, equals(0));
      });

      test('without onTap is excluded', () async {
        final r = await EthosTestHelper.analyzeSource('''
          GestureDetector(onPanUpdate: (d) {}, child: Container())
        ''');
        final cov = r.coverage['wcag_1_3_1_semantics_label'];
        expect(cov?.total, equals(0));
      });

      test('with runtime label is indeterminate', () async {
        final r = await EthosTestHelper.analyzeSource('''
          Semantics(
            label: myLabel,
            child: GestureDetector(onTap: () => go(), child: Icon(Icons.person)),
          )
        ''');
        final cov = r.coverage['wcag_1_3_1_semantics_label'];
        expect(cov?.indeterminate, greaterThan(0));
      });

      test('with empty Semantics label fails', () async {
        final r = await EthosTestHelper.analyzeSource('''
          Semantics(
            label: '',
            child: GestureDetector(onTap: () => go(), child: Text('tap me')),
          )
        ''');
        final cov = r.coverage['wcag_1_3_1_semantics_label'];
        expect(cov?.findings, isNotEmpty);
      });
    });

    group('InkWell', () {
      test('with Semantics passes', () async {
        final r = await EthosTestHelper.analyzeSource('''
          Semantics(
            label: 'Submit form',
            child: InkWell(onTap: () => submit(), child: Text('Submit')),
          )
        ''');
        expect(r, passesRule('wcag_1_3_1_semantics_label'));
      });

      test('without Semantics fails', () async {
        final r = await EthosTestHelper.analyzeSource('''
          InkWell(onTap: () => submit(), child: Text('Submit'))
        ''');
        final cov = r.coverage['wcag_1_3_1_semantics_label'];
        expect(cov?.findings, isNotEmpty);
      });
    });

    group('excludeFromSemantics', () {
      test('GestureDetector with excludeFromSemantics is skipped', () async {
        final r = await EthosTestHelper.analyzeSource('''
          GestureDetector(
            excludeFromSemantics: true,
            onTap: () => dismiss(),
            child: Container(),
          )
        ''');
        final cov = r.coverage['wcag_1_3_1_semantics_label'];
        expect(cov?.total, equals(0));
      });
    });
  });
}
