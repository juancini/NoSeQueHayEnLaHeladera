import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nsd/nsd.dart';
import 'package:no_se_que_hay_en_la_heladera/features/sync/data/discovered_sync_peer.dart';

void main() {
  const householdHash = 'household-hash';
  const localMemberId = 'local-member';

  Service service({
    String? version = '1',
    String? advertisedHousehold = householdHash,
    String? memberId = 'remote-member',
    int? port = 47622,
    String? host = 'remote.local',
    List<InternetAddress>? addresses,
  }) =>
      Service(
        name: 'helh-remote01',
        type: DiscoveredSyncPeer.serviceType,
        port: port,
        host: host,
        addresses: addresses,
        txt: {
          if (version != null) 'v': Uint8List.fromList(utf8.encode(version)),
          if (advertisedHousehold != null)
            'hh': Uint8List.fromList(utf8.encode(advertisedHousehold)),
          if (memberId != null)
            'mid': Uint8List.fromList(utf8.encode(memberId)),
        },
      );

  test('accepts a same-household peer and uses resolved LAN addresses', () {
    final peer = DiscoveredSyncPeer.parse(
      service(
        addresses: [InternetAddress('192.168.1.87')],
      ),
      householdHash: householdHash,
      localMemberId: localMemberId,
    );

    expect(peer?.memberId, 'remote-member');
    expect(
      peer?.endpoints,
      [Uri(scheme: 'http', host: '192.168.1.87', port: 47622)],
    );
  });

  test('falls back to the resolved service hostname when no IPv4 is present',
      () {
    final peer = DiscoveredSyncPeer.parse(
      service(),
      householdHash: householdHash,
      localMemberId: localMemberId,
    );

    expect(
      peer?.endpoints,
      [Uri(scheme: 'http', host: 'remote.local', port: 47622)],
    );
  });

  test('rejects services from a different household or protocol version', () {
    expect(
      DiscoveredSyncPeer.parse(
        service(advertisedHousehold: 'other-household'),
        householdHash: householdHash,
        localMemberId: localMemberId,
      ),
      isNull,
    );
    expect(
      DiscoveredSyncPeer.parse(
        service(version: '2'),
        householdHash: householdHash,
        localMemberId: localMemberId,
      ),
      isNull,
    );
  });

  test('rejects this device, invalid identities, endpoints, and service types',
      () {
    expect(
      DiscoveredSyncPeer.parse(
        service(memberId: localMemberId),
        householdHash: householdHash,
        localMemberId: localMemberId,
      ),
      isNull,
    );
    expect(
      DiscoveredSyncPeer.parse(
        service(memberId: ''),
        householdHash: householdHash,
        localMemberId: localMemberId,
      ),
      isNull,
    );
    expect(
      DiscoveredSyncPeer.parse(
        service(port: 0),
        householdHash: householdHash,
        localMemberId: localMemberId,
      ),
      isNull,
    );
    expect(
      DiscoveredSyncPeer.parse(
        service(host: null, addresses: [InternetAddress('127.0.0.1')]),
        householdHash: householdHash,
        localMemberId: localMemberId,
      ),
      isNull,
    );
    expect(
      DiscoveredSyncPeer.parse(
        const Service(
          name: 'other',
          type: '_http._tcp',
          port: 80,
          host: 'other.local',
        ),
        householdHash: householdHash,
        localMemberId: localMemberId,
      ),
      isNull,
    );
  });
}
