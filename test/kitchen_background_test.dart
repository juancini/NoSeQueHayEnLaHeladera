import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:no_se_que_hay_en_la_heladera/features/groceries/presentation/widgets/kitchen_background.dart';

void main() {
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
