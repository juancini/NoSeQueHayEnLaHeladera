import 'dart:convert';

class HouseholdInvite {
  const HouseholdInvite({
    required this.householdId,
    required this.householdName,
    required this.secret,
  });

  static const scheme = 'nsqhelh';

  final String householdId;
  final String householdName;
  final String secret;

  String toPayload() => Uri(
        scheme: scheme,
        host: 'household',
        queryParameters: {
          'v': '1',
          'id': householdId,
          'name': householdName,
          'secret': secret,
        },
      ).toString();

  static bool supportsUri(Uri uri) =>
      (uri.scheme == scheme && uri.host == 'household') ||
      (uri.scheme == 'https' && uri.path == '/household');

  factory HouseholdInvite.fromPayload(String payload) {
    if (payload.trimLeft().startsWith('{')) {
      return _fromLegacyJson(payload);
    }

    final uri = Uri.tryParse(payload);
    if (uri == null || !supportsUri(uri) || uri.queryParameters['v'] != '1') {
      throw const FormatException('El código QR no es una invitación válida');
    }

    return _fromValues(
      uri.queryParameters['id'],
      uri.queryParameters['name'],
      uri.queryParameters['secret'],
    );
  }

  static HouseholdInvite _fromLegacyJson(String payload) {
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic> ||
          decoded['version'] != 1 ||
          decoded['household_id'] is! String ||
          decoded['household_name'] is! String ||
          decoded['secret'] is! String) {
        throw const FormatException();
      }

      return _fromValues(
        decoded['household_id'] as String,
        decoded['household_name'] as String,
        decoded['secret'] as String,
      );
    } on FormatException {
      throw const FormatException('El código QR no es una invitación válida');
    }
  }

  static HouseholdInvite _fromValues(
    String? householdId,
    String? householdName,
    String? secret,
  ) {
    if (householdId == null ||
        householdId.trim().isEmpty ||
        householdName == null ||
        householdName.trim().isEmpty ||
        secret == null) {
      throw const FormatException('El código QR no es una invitación válida');
    }

    try {
      if (base64Url.decode(secret).length != 32) {
        throw const FormatException();
      }
    } on FormatException {
      throw const FormatException('El código QR no es una invitación válida');
    }

    return HouseholdInvite(
      householdId: householdId,
      householdName: householdName,
      secret: secret,
    );
  }
}
