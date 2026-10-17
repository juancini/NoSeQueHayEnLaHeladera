import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_se_que_hay_en_la_heladera/features/groceries/data/drawing_image_storage.dart';

void main() {
  late Directory documents;
  late DrawingImageStorage storage;

  setUp(() async {
    documents = await Directory.systemTemp.createTemp('heladera-drawings-');
    storage = DrawingImageStorage(documentsDirectory: () async => documents);
  });

  tearDown(() async {
    if (await documents.exists()) await documents.delete(recursive: true);
  });

  test('stores PNG bytes under their content hash and reads verified files', () async {
    final bytes = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10, 1, 2]);

    final imageSrc = await storage.savePng(bytes);

    expect(imageSrc, matches(RegExp(r'^drawings/[0-9a-f]{64}\.png$')));
    expect(await storage.availableHashes(), {imageSrc!.split('/').last.split('.').first});
    expect(await storage.readHash(imageSrc.split('/').last.split('.').first), bytes);
    expect(await storage.resolve(imageSrc), isNotNull);
    expect(await storage.resolve('drawings/../not-an-image.png'), isNull);
  });

  test('rejects a mismatched hash and keeps valid re-uploads idempotent', () async {
    final bytes = Uint8List.fromList([1, 2, 3, 4]);
    final imageSrc = await storage.savePng(bytes);
    final hash = storage.hashFromSource(imageSrc)!;
    final file = File('${documents.path}/drawings/$hash.png');
    final before = await file.readAsBytes();

    await storage.storeDownloaded(hash, bytes);
    expect(await file.readAsBytes(), before);
    await expectLater(
      storage.storeDownloaded(hash, Uint8List.fromList([4, 3, 2, 1])),
      throwsFormatException,
    );
    expect(await file.readAsBytes(), before);
  });
}
