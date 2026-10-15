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

  @override
  Stream<List<Product>> watchProducts() => Stream.value(const []);

  @override
  Stream<List<Product>> watchShoppingList() => Stream.value(const []);

  @override
  Future<Product> addProduct(String name, int lastsDays) =>
      throw UnimplementedError();

  @override
  Future<void> updateProduct(String id, {String? name, int? lastsDays}) async {
    updatedProductId = id;
    updatedName = name;
  }

  @override
  Future<void> markBought(String id) => throw UnimplementedError();

  @override
  Future<void> markEmpty(String id) => throw UnimplementedError();

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
          home: Scaffold(body: ProductTile(product: product)),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Acciones'));
    await tester.pumpAndSettle();
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
}
