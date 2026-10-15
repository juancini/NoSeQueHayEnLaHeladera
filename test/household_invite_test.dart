import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_se_que_hay_en_la_heladera/features/household/domain/entities/household_invite.dart';

void main() {
  final secret = base64UrlEncode(List<int>.filled(32, 7));

  test('encodes and decodes household details as an app URI', () {
    final invite = HouseholdInvite(
      householdId: 'household-123',
      householdName: 'Casa & Cocina #1/ñ',
      secret: secret,
    );

    final payload = invite.toPayload();
    final decoded = HouseholdInvite.fromPayload(payload);

    expect(payload, startsWith('nsqhelh://household?'));
    expect(decoded.householdId, invite.householdId);
    expect(decoded.householdName, invite.householdName);
    expect(decoded.secret, invite.secret);
  });

  test('continues to read existing v1 JSON invitations', () {
    final payload = jsonEncode({
      'version': 1,
      'household_id': 'legacy-house',
      'household_name': 'Casa anterior',
      'secret': secret,
    });

    final invite = HouseholdInvite.fromPayload(payload);

    expect(invite.householdId, 'legacy-house');
    expect(invite.householdName, 'Casa anterior');
    expect(invite.secret, secret);
  });

  test('accepts HTTPS invite links for future associated domains', () {
    final uri = Uri.https('invites.example.test', '/household', {
      'v': '1',
      'id': 'household-123',
      'name': 'Casa',
      'secret': secret,
    });

    final invite = HouseholdInvite.fromPayload(uri.toString());

    expect(invite.householdId, 'household-123');
    expect(invite.householdName, 'Casa');
  });

  test('rejects invalid links and secrets', () {
    expect(
      () => HouseholdInvite.fromPayload('nsqhelh://household?v=1&id=x'),
      throwsFormatException,
    );
    expect(
      () => HouseholdInvite.fromPayload(
        HouseholdInvite(
          householdId: 'id',
          householdName: 'Casa',
          secret: base64UrlEncode(List<int>.filled(31, 7)),
        ).toPayload(),
      ),
      throwsFormatException,
    );
    expect(
      () => HouseholdInvite.fromPayload('https://example.test/not-an-invite'),
      throwsFormatException,
    );
  });
}
