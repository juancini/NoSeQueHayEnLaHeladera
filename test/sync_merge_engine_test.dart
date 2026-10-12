import 'package:flutter_test/flutter_test.dart';
import 'package:no_se_que_hay_en_la_heladera/features/sync/domain/sync_merge_engine.dart';

Map<String, Object?> row({
  required String name,
  required int updatedAt,
  required String writer,
  int? boughtAt,
  int? emptiedAt,
  int? deletedAt,
  int lastsDays = 3,
}) =>
    {
      'id': 'milk',
      'household_id': 'home',
      'name': name,
      'lasts_days': lastsDays,
      'last_bought_at': boughtAt,
      'last_emptied_at': emptiedAt,
      'updated_at': updatedAt,
      'deleted_at': deletedAt,
      'last_writer_member_id': writer,
    };

void main() {
  group('SyncMergeEngine.mergeProduct', () {
    test('keeps the newest bought and emptied timestamps from either device', () {
      final merged = SyncMergeEngine.mergeProduct(
        local: row(name: 'Leche', updatedAt: 1, writer: 'a', boughtAt: 100),
        incoming: row(name: 'Leche', updatedAt: 1, writer: 'b', emptiedAt: 200),
      );

      expect(merged['last_bought_at'], 100);
      expect(merged['last_emptied_at'], 200);
    });

    test('chooses metadata by updated time then writer id', () {
      final merged = SyncMergeEngine.mergeProduct(
        local: row(name: 'Leche entera', updatedAt: 10, writer: 'a'),
        incoming: row(name: 'Leche', updatedAt: 10, writer: 'b', lastsDays: 5),
      );

      expect(merged['name'], 'Leche');
      expect(merged['lasts_days'], 5);
    });

    test('a newer edit wins over an older delete', () {
      final merged = SyncMergeEngine.mergeProduct(
        local: row(name: 'Leche', updatedAt: 11, writer: 'a'),
        incoming: row(name: 'Leche', updatedAt: 10, writer: 'b', deletedAt: 10),
      );

      expect(merged['deleted_at'], isNull);
    });

    test('is idempotent when the merged row is merged again', () {
      final local = row(name: 'Leche', updatedAt: 10, writer: 'a', boughtAt: 20);
      final incoming =
          row(name: 'Leche', updatedAt: 11, writer: 'b', emptiedAt: 25);
      final once = SyncMergeEngine.mergeProduct(local: local, incoming: incoming);
      final twice = SyncMergeEngine.mergeProduct(local: once, incoming: incoming);

      expect(twice, once);
    });
  });
}
