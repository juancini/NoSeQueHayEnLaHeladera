import 'dart:convert';
import 'dart:io';

import 'package:nsd/nsd.dart';

class DiscoveredSyncPeer {
  const DiscoveredSyncPeer({
    required this.memberId,
    required this.endpoints,
  });

  static const serviceType = '_groceries._tcp';

  final String memberId;
  final List<Uri> endpoints;

  static DiscoveredSyncPeer? parse(
    Service service, {
    required String householdHash,
    required String localMemberId,
  }) {
    if (service.type != serviceType ||
        service.port == null ||
        service.port! < 1 ||
        service.port! > 65535) {
      return null;
    }

    final txt = service.txt;
    final version = _txtValue(txt, 'v');
    final advertisedHousehold = _txtValue(txt, 'hh');
    final memberId = _txtValue(txt, 'mid');
    if (version != '1' ||
        advertisedHousehold != householdHash ||
        memberId == null ||
        memberId.isEmpty ||
        memberId.length > 128 ||
        memberId == localMemberId) {
      return null;
    }

    final endpoints = <Uri>[];
    for (final address in service.addresses ?? const <InternetAddress>[]) {
      if (address.type == InternetAddressType.IPv4 &&
          !address.isLoopback &&
          !address.isLinkLocal) {
        endpoints.add(
          Uri(
            scheme: 'http',
            host: address.address,
            port: service.port!,
          ),
        );
      }
    }

    if (endpoints.isEmpty) {
      final host = service.host;
      if (host != null && host.isNotEmpty) {
        endpoints.add(
          Uri(scheme: 'http', host: host, port: service.port!),
        );
      }
    }
    if (endpoints.isEmpty) return null;

    return DiscoveredSyncPeer(
      memberId: memberId,
      endpoints: List.unmodifiable(endpoints.toSet()),
    );
  }

  static String? _txtValue(Map<String, List<int>?>? txt, String key) {
    final bytes = txt?[key];
    if (bytes == null) return null;
    try {
      return utf8.decode(bytes, allowMalformed: false);
    } on FormatException {
      return null;
    }
  }
}
