import 'package:flutter_test/flutter_test.dart';
import 'package:no_se_que_hay_en_la_heladera/features/groceries/domain/entities/product.dart';

Product product({
  int? bought,
  int? emptied,
  int lastsDays = 5,
}) =>
    Product(
      id: 'product-id',
      name: 'Leche',
      lastsDays: lastsDays,
      lastBoughtAt: bought,
      lastEmptiedAt: emptied,
      updatedAt: 0,
      sequence: 0,
      lastWriterMemberId: '',
    );

void main() {
  group('Product.needsBuying', () {
    test('marks a product never bought as missing', () {
      expect(product().needsBuying, isTrue);
    });

    test('marks a product emptied after purchase as missing', () {
      expect(product(bought: 100, emptied: 101).needsBuying, isTrue);
    });

    test('a purchase after emptying makes it available again', () {
      expect(product(bought: 101, emptied: 100).needsBuying, isFalse);
    });

    test('marks an expired product as missing', () {
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      expect(product(bought: now - const Duration(days: 6).inMilliseconds).needsBuying, isTrue);
    });
  });
}
