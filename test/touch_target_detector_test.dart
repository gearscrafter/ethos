import 'package:test/test.dart';
import 'package:ethos/ethos_test.dart';

void main() {
  group('TouchTargetDetector', () {
    group('auto-pass widgets', () {
      test('IconButton passes automatically', () async {
        final r = await EthosTestHelper.analyzeSource(
          'IconButton(onPressed: () {}, icon: Icon(Icons.add))',
        );
        expect(r, passesRule('wcag_2_5_5_target_size_enhanced'));
      });

      test('FloatingActionButton passes automatically', () async {
        final r = await EthosTestHelper.analyzeSource(
          'FloatingActionButton(onPressed: () {}, child: Icon(Icons.add))',
        );
        expect(r, passesRule('wcag_2_5_5_target_size_enhanced'));
      });
    });

    group('GestureDetector with SizedBox', () {
      test('48x48 SizedBox passes', () async {
        final r = await EthosTestHelper.analyzeSource('''
          SizedBox(
            width: 48,
            height: 48,
            child: GestureDetector(onTap: () => go(), child: Icon(Icons.add)),
          )
        ''');
        expect(r, passesRule('wcag_2_5_5_target_size_enhanced'));
      });

      test('32x32 SizedBox fails', () async {
        final r = await EthosTestHelper.analyzeSource('''
          SizedBox(
            width: 32,
            height: 32,
            child: GestureDetector(onTap: () => go(), child: Icon(Icons.remove)),
          )
        ''');
        final cov = r.coverage['wcag_2_5_5_target_size_enhanced'];
        expect(cov?.findings, isNotEmpty);
      });

      test('GestureDetector without sizer is indeterminate', () async {
        final r = await EthosTestHelper.analyzeSource(
          "GestureDetector(onTap: () => go(), child: Text('tap'))",
        );
        final cov = r.coverage['wcag_2_5_5_target_size_enhanced'];
        expect(cov?.indeterminate, greaterThan(0));
      });
    });
  });
}
