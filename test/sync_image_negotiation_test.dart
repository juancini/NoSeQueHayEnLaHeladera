import 'package:flutter_test/flutter_test.dart';
import 'package:no_se_que_hay_en_la_heladera/features/sync/domain/sync_image_negotiation.dart';

void main() {
  test('manifest requests only image hashes the other device lacks', () {
    final upload = SyncImageNegotiation.missingHashes(
      referenced: [
        'b' * 64,
        'a' * 64,
        'b' * 64,
      ],
      available: ['a' * 64],
    );

    expect(upload, ['b' * 64]);
  });

  test('unchanged available images require no binary transfers', () {
    final hashes = {'a' * 64, 'b' * 64};

    expect(
      SyncImageNegotiation.missingHashes(
        referenced: hashes,
        available: hashes,
      ),
      isEmpty,
    );
  });
}
