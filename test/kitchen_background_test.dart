import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:no_se_que_hay_en_la_heladera/features/groceries/presentation/widgets/kitchen_background.dart';

void main() {
  test('kitchen SVGs use the exact icon color and preserve highlights',
      () async {
    const assets = [
      'assets/icons/background/spoon.svg',
      'assets/icons/background/fork.svg',
      'assets/icons/background/mug.svg',
      'assets/icons/background/heart.svg',
      'assets/icons/background/star.svg',
    ];

    for (final asset in assets) {
      final svg = await rootBundle.loadString(asset);
      expect(svg, contains('#F1D9A1'));
      expect(svg, isNot(contains('#eec364')));
    }

    final spoon = await rootBundle.loadString(assets[0]);
    final mug = await rootBundle.loadString(assets[2]);
    expect(spoon, contains('stroke-opacity=".4"'));
    expect(mug, contains('fill-opacity=".4"'));
  });

  testWidgets('paper texture stays behind content and does not block taps',
      (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: KitchenBackground(
          child: Center(
            child: TextButton(
              onPressed: () => tapped = true,
              child: const Text('Tap me'),
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('kitchen-paper-texture')), findsOneWidget);
    await tester.tap(find.text('Tap me'));
    expect(tapped, isTrue);
  });

  test('layout is deterministic and keeps the required gap between icons', () {
    const size = Size(390, 844);
    final firstLayout = buildKitchenIconLayout(size);
    final secondLayout = buildKitchenIconLayout(size);

    expect(
      secondLayout
          .map((icon) =>
              (icon.asset, icon.center, icon.size, icon.radius, icon.rotation))
          .toList(),
      firstLayout
          .map((icon) =>
              (icon.asset, icon.center, icon.size, icon.radius, icon.rotation))
          .toList(),
    );
    expect(firstLayout, isNotEmpty);

    const gap = kitchenBackgroundCell * kitchenBackgroundGapFactor;
    for (var first = 0; first < firstLayout.length; first++) {
      for (var second = first + 1; second < firstLayout.length; second++) {
        final a = firstLayout[first];
        final b = firstLayout[second];
        expect(
          (a.center - b.center).distance,
          greaterThanOrEqualTo(a.radius + b.radius + gap),
        );
      }
    }
  });
}
