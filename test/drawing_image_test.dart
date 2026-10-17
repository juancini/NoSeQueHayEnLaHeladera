import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_drawing_board/flutter_drawing_board.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_se_que_hay_en_la_heladera/features/groceries/data/drawing_png.dart';
import 'package:no_se_que_hay_en_la_heladera/features/groceries/presentation/pages/draw_product_image_page.dart';

void main() {
  test('blank exports contain only transparent alpha pixels', () {
    expect(
      DrawingPng.hasVisiblePixels(
        Uint8List.fromList([0, 0, 0, 0, 255, 255, 255, 0]),
      ),
      isFalse,
    );
    expect(
      DrawingPng.hasVisiblePixels(
        Uint8List.fromList([0, 0, 0, 0, 10, 20, 30, 255]),
      ),
      isTrue,
    );
    expect(
      () => DrawingPng.hasVisiblePixels(Uint8List.fromList([1, 2, 3])),
      throwsFormatException,
    );
  });

  testWidgets('an untouched drawing canvas is skipped', (tester) async {
    Uint8List? result = Uint8List(1);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await Navigator.of(context).push<Uint8List>(
                MaterialPageRoute(
                  builder: (_) => const DrawProductImagePage(),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Usar dibujo'));
    await tester.pumpAndSettle();

    expect(result, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('canvas dimensions stay fixed at device pixel ratio 3',
      (tester) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(1200, 2400);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const MaterialApp(home: DrawProductImagePage()));
    await tester.pumpAndSettle();
    final board = find.byType(DrawingBoard);
    expect(tester.getSize(board), const Size(300, 300));
    expect(tester.widget<DrawingBoard>(board).controller.currentIndex, 0);
    expect(tester.takeException(), isNull);
  });
}
