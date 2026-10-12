import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_se_que_hay_en_la_heladera/features/household/domain/entities/household.dart';
import 'package:no_se_que_hay_en_la_heladera/features/household/domain/entities/member.dart';
import 'package:no_se_que_hay_en_la_heladera/features/household/domain/repositories/household_repository.dart';
import 'package:no_se_que_hay_en_la_heladera/features/household/presentation/pages/household_page.dart';
import 'package:no_se_que_hay_en_la_heladera/features/household/presentation/providers/household_providers.dart';

class _HouseholdRepository implements HouseholdRepository {
  Household? household;

  @override
  Future<Household> createHousehold(String name, String myName) async {
    household = Household(id: 'home-id', name: name);
    return household!;
  }

  @override
  Future<Household?> current() async => household;

  @override
  Future<String> inviteQrPayload() async => '';

  @override
  Future<void> joinFromQr(String payload, String myName) async {}

  @override
  Stream<List<Member>> watchMembers() => const Stream.empty();
}

void main() {
  testWidgets('creates a household from the names dialog', (tester) async {
    final repository = _HouseholdRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          householdRepositoryProvider.overrideWithValue(repository),
          currentHouseholdProvider.overrideWith((ref) => repository.current()),
        ],
        child: const MaterialApp(home: HouseholdPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Crear un hogar'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Nombre del hogar'), 'Casa');
    await tester.enterText(find.widgetWithText(TextField, 'Tu nombre'), 'Juani');
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Casa'), findsOneWidget);
  });
}
