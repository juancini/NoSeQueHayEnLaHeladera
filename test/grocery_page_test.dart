import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_se_que_hay_en_la_heladera/features/groceries/domain/entities/product.dart';
import 'package:no_se_que_hay_en_la_heladera/features/groceries/domain/repositories/grocery_repository.dart';
import 'package:no_se_que_hay_en_la_heladera/features/groceries/presentation/pages/grocery_page.dart';
import 'package:no_se_que_hay_en_la_heladera/features/groceries/presentation/providers/grocery_providers.dart';
import 'package:no_se_que_hay_en_la_heladera/features/groceries/presentation/widgets/product_tile.dart';
import 'package:no_se_que_hay_en_la_heladera/features/household/domain/entities/household.dart';
import 'package:no_se_que_hay_en_la_heladera/features/household/domain/entities/member.dart';
import 'package:no_se_que_hay_en_la_heladera/features/household/domain/repositories/household_repository.dart';
import 'package:no_se_que_hay_en_la_heladera/features/household/presentation/providers/household_providers.dart';

class _GroceryRepository implements GroceryRepository {
  String? updatedProductId;
  String? updatedName;
  String? boughtProductId;
  String? emptiedProductId;

  @override
  Stream<List<Product>> watchProducts() => Stream.value(const []);

  @override
  Stream<List<Product>> watchShoppingList() => Stream.value(const []);

  @override
  Future<Product> addProduct(String name, int lastsDays,
          {Uint8List? imagePng}) =>
      throw UnimplementedError();

  @override
  Future<void> updateProduct(String id, {String? name, int? lastsDays}) async {
    updatedProductId = id;
    updatedName = name;
  }

  @override
  Future<void> markBought(String id) async {
    boughtProductId = id;
  }

  @override
  Future<void> markEmpty(String id) async {
    emptiedProductId = id;
  }

  @override
  Future<void> deleteProduct(String id) => throw UnimplementedError();
}

class _HouseholdRepository implements HouseholdRepository {
  @override
  Future<Household> createHousehold(String name, String myName) =>
      throw UnimplementedError();

  @override
  Future<Household?> current() async => null;

  @override
  Future<String> inviteQrPayload() => throw UnimplementedError();

  @override
  Future<void> joinFromQr(String payload, String myName) =>
      throw UnimplementedError();

  @override
  Stream<List<Member>> watchMembers() => const Stream.empty();
}

void main() {
  testWidgets('requires a household before opening the add-product form',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          groceryRepositoryProvider.overrideWithValue(_GroceryRepository()),
          householdRepositoryProvider.overrideWithValue(_HouseholdRepository()),
        ],
        child: const MaterialApp(home: GroceryPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Agregar'));
    await tester.pumpAndSettle();

    expect(find.text('Tu hogar'), findsOneWidget);
    expect(find.text('Crear un hogar'), findsOneWidget);
    expect(find.text('Agregar producto'), findsNothing);
  });

  testWidgets('renames a product and rejects an empty name', (tester) async {
    final repository = _GroceryRepository();
    const product = Product(
      id: 'milk-id',
      name: 'Leche',
      lastsDays: 5,
      updatedAt: 0,
      sequence: 0,
      lastWriterMemberId: '',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          groceryRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 90,
                height: 90,
                child: ProductTile(product: product),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.longPress(find.byType(ProductTile));
    await tester.pumpAndSettle();
    expect(find.text('Cambiar duración'), findsOneWidget);
    expect(find.text('Eliminar'), findsOneWidget);
    await tester.tap(find.text('Cambiar nombre'));
    await tester.pumpAndSettle();

    expect(find.text('Leche'), findsNWidgets(2));
    await tester.enterText(find.byType(TextFormField), '   ');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(find.text('Escribí un nombre'), findsOneWidget);
    expect(repository.updatedProductId, isNull);

    await tester.enterText(find.byType(TextFormField), '  Leche entera  ');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(repository.updatedProductId, 'milk-id');
    expect(repository.updatedName, 'Leche entera');
    expect(find.text('Cambiar nombre'), findsNothing);
  });

  testWidgets('a short tap marks a product as bought', (tester) async {
    final repository = _GroceryRepository();
    const product = Product(
      id: 'milk-id',
      name: 'Leche',
      lastsDays: 5,
      updatedAt: 0,
      sequence: 0,
      lastWriterMemberId: '',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          groceryRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 90,
                height: 90,
                child: ProductTile(product: product),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(ProductTile));
    await tester.pump();

    expect(
        find.descendant(
          of: find.byType(ProductTile),
          matching: find.byType(Card),
        ),
        findsNothing);
    expect(repository.boughtProductId, 'milk-id');
    expect(repository.emptiedProductId, isNull);
  });

  testWidgets('products are shown in a scrollable four-column grid',
      (tester) async {
    final products = List.generate(
      32,
      (index) => Product(
        id: 'product-$index',
        name: 'Producto $index',
        lastsDays: 5,
        updatedAt: 0,
        sequence: index,
        lastWriterMemberId: '',
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          groceryRepositoryProvider.overrideWithValue(_GroceryRepository()),
          householdRepositoryProvider.overrideWithValue(_HouseholdRepository()),
          productsProvider.overrideWith((ref) => Stream.value(products)),
        ],
        child: const MaterialApp(home: GroceryPage()),
      ),
    );
    await tester.pumpAndSettle();

    final grid = tester.widget<GridView>(find.byType(GridView));
    expect(
      (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
          .crossAxisCount,
      4,
    );
    expect(find.text('Producto 31'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('Producto 31'),
      300,
      scrollable: find.byType(Scrollable),
    );
    await tester.pumpAndSettle();

    expect(find.text('Producto 31'), findsOneWidget);
  });
}
