import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:no_se_que_hay_en_la_heladera/features/household/domain/entities/household.dart';
import 'package:no_se_que_hay_en_la_heladera/features/household/domain/entities/member.dart';
import 'package:no_se_que_hay_en_la_heladera/features/household/domain/repositories/household_repository.dart';
import 'package:no_se_que_hay_en_la_heladera/features/household/presentation/pages/household_page.dart';
import 'package:no_se_que_hay_en_la_heladera/features/household/presentation/providers/household_providers.dart';

class _HouseholdRepository implements HouseholdRepository {
  Household? household;
  String? joinedPayload;

  static final invitePayload = Uri(
    scheme: 'nsqhelh',
    host: 'household',
    queryParameters: {
      'v': '1',
      'id': 'home-id',
      'name': 'Casa',
      'secret': base64UrlEncode(List<int>.filled(32, 7)),
    },
  ).toString();

  @override
  Future<Household> createHousehold(String name, String myName) async {
    household = Household(id: 'home-id', name: name);
    return household!;
  }

  @override
  Future<Household?> current() async => household;

  @override
  Future<String> inviteQrPayload() async => invitePayload;

  @override
  Future<void> joinFromQr(String payload, String myName) async {
    joinedPayload = payload;
    household = const Household(id: 'home-id', name: 'Casa');
  }

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
    await tester.enterText(
        find.widgetWithText(TextField, 'Nombre del hogar'), 'Casa');
    await tester.enterText(
        find.widgetWithText(TextField, 'Tu nombre'), 'Juani');
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Casa'), findsOneWidget);
  });

  testWidgets('renders the invite URI in the household QR code',
      (tester) async {
    final repository = _HouseholdRepository()
      ..household = const Household(id: 'home-id', name: 'Casa');
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

    await tester.tap(find.text('Invitar a alguien'));
    await tester.pumpAndSettle();

    expect(find.byType(QrImageView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pasted invite requires household confirmation before joining',
      (tester) async {
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

    await tester.tap(find.text('Pegar código de invitación'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Código o enlace de invitación'),
      _HouseholdRepository.invitePayload,
    );
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Hogar: Casa'), findsOneWidget);
    expect(repository.joinedPayload, isNull);
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Nombre'), 'Juani');
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    expect(repository.joinedPayload, _HouseholdRepository.invitePayload);
  });

  testWidgets('opening an invite for the current household does nothing',
      (tester) async {
    final repository = _HouseholdRepository()
      ..household = const Household(id: 'home-id', name: 'Casa');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          householdRepositoryProvider.overrideWithValue(repository),
          currentHouseholdProvider.overrideWith((ref) => repository.current()),
        ],
        child: MaterialApp(
          home: HouseholdPage(
            invitePayload: _HouseholdRepository.invitePayload,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Unirte a este hogar'), findsNothing);
    expect(find.widgetWithText(TextField, 'Nombre'), findsNothing);
    expect(repository.joinedPayload, isNull);
  });
}
