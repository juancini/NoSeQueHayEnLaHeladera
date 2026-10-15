import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_se_que_hay_en_la_heladera/app/app.dart';
import 'package:no_se_que_hay_en_la_heladera/features/groceries/domain/entities/product.dart';
import 'package:no_se_que_hay_en_la_heladera/features/groceries/presentation/providers/grocery_providers.dart';
import 'package:no_se_que_hay_en_la_heladera/features/household/presentation/providers/household_providers.dart';

void main() {
  testWidgets('renders the grocery screen', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          productsProvider
              .overrideWith((ref) => Stream.value(const <Product>[])),
          currentHouseholdProvider.overrideWith((ref) async => null),
        ],
        child: const HeladeraApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No se que hay en la heladerApp'), findsOneWidget);
    expect(find.text('Creá o unite a un hogar para agregar productos.'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
