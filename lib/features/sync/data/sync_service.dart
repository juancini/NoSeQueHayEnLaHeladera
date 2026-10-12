import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../../core/database/app_database.dart';
import 'sync_data_store.dart';

class SyncService {
  SyncService(this._appDatabase)
      : _store = SyncDataStore(_appDatabase);

  static const port = 47622;
  static const _maxBodyBytes = 1024 * 1024;
  static const _clockToleranceMs = 5 * 60 * 1000;

  final AppDatabase _appDatabase;
  final SyncDataStore _store;
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10);
  HttpServer? _server;

  Future<void> start() async {
    if (_server != null) return;
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _server!.listen(
      (request) => unawaited(_handleRequest(request)),
      onError: (Object error, StackTrace stackTrace) {
        stderr.writeln('Sync server error: $error');
      },
    );
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _client.close(force: true);
  }

  Future<void> syncWith(Uri peer) async {
    if (peer.scheme != 'http' || peer.host.isEmpty) {
      throw ArgumentError.value(peer, 'peer', 'Use an HTTP address on the local network');
    }
    final householdId = await _store.householdId;
    final secretValue = await _appDatabase.readLocalState('household_secret');
    final memberId = await _appDatabase.readLocalState('member_id');
    if (householdId == null || secretValue == null || memberId == null) {
      throw StateError('Creá o uníte a un hogar antes de sincronizar');
    }
    final secret = _decodeSecret(secretValue);
    final requestData = {
      ...await _store.requestFor(peer.host),
      'member_id': memberId,
      'household_hash': _householdHash(householdId),
    };
    final body = jsonEncode(requestData);
    final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch.toString();
    final requestUri = peer.replace(
      path: '/sync',
      query: null,
      fragment: null,
      port: peer.hasPort ? peer.port : port,
    );
    final request = await _client.postUrl(requestUri).timeout(
          const Duration(seconds: 15),
        );
    request.headers
      ..set(HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8')
      ..set('X-Household', _householdHash(householdId))
      ..set('X-Member', memberId)
      ..set('X-Time', timestamp)
      ..set('X-Signature', _signature(secret, timestamp, body));
    request.write(body);
    final response = await request.close().timeout(const Duration(seconds: 30));
    final responseBody = await _readBody(response).timeout(
      const Duration(seconds: 30),
    );
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'El otro dispositivo rechazó la sincronización (${response.statusCode})',
        uri: requestUri,
      );
    }
    final responseTime = response.headers.value('X-Time');
    final responseSignature = response.headers.value('X-Signature');
    if (responseTime == null ||
        responseSignature == null ||
        response.headers.value('X-Household') != _householdHash(householdId) ||
        !_verify(
          secret,
          responseTime,
          responseBody,
          responseSignature,
        )) {
      throw const FormatException('La respuesta del otro dispositivo no es válida');
    }
    final decoded = jsonDecode(responseBody);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('La respuesta de sincronización no es válida');
    }
    final responseData = Map<String, Object?>.from(decoded);
    if (responseData['household_hash'] != _householdHash(householdId)) {
      throw const FormatException('La respuesta pertenece a otro hogar');
    }
    final remoteMemberId = responseData['member_id'];
    if (remoteMemberId is! String || remoteMemberId.isEmpty) {
      throw const FormatException('La respuesta no identifica al otro dispositivo');
    }
    await _store.applyResponse(
      peerId: remoteMemberId,
      peerAddress: peer.host,
      response: responseData,
      sentThrough: requestData['cursor']! as int,
    );
  }

  Future<void> _handleRequest(HttpRequest request) async {
    if (request.method != 'POST' || request.uri.path != '/sync') {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    try {
      final body = await _readBody(request);
      final householdId = await _store.householdId;
      final secretValue = await _appDatabase.readLocalState('household_secret');
      final senderId = request.headers.value('X-Member');
      final timestamp = request.headers.value('X-Time');
      final signature = request.headers.value('X-Signature');
      final householdHash = request.headers.value('X-Household');
      if (householdId == null ||
          secretValue == null ||
          senderId == null ||
          senderId.isEmpty ||
          timestamp == null ||
          signature == null ||
          householdHash == null ||
          senderId.length > 128) {
        throw const SyncAuthenticationException();
      }
      final secret = _decodeSecret(secretValue);
      if (householdHash != _householdHash(householdId) ||
          !_verify(secret, timestamp, body, signature)) {
        throw const SyncAuthenticationException();
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Invalid sync request');
      }
      if (decoded['member_id'] != senderId ||
          decoded['household_hash'] != householdHash) {
        throw const SyncAuthenticationException();
      }
      final result = await _store.exchange(
        senderId,
        Map<String, Object?>.from(decoded),
      );
      final memberId = await _appDatabase.readLocalState('member_id');
      if (memberId == null) throw StateError('Missing local member identity');
      await _writeSignedResponse(
        request.response,
        secret,
        householdId,
        {
          ...result,
          'member_id': memberId,
          'household_hash': _householdHash(householdId),
        },
      );
    } on _BodyTooLargeException {
      request.response.statusCode = HttpStatus.requestEntityTooLarge;
      await request.response.close();
    } on SyncAuthenticationException {
      request.response.statusCode = HttpStatus.unauthorized;
      await request.response.close();
    } on FormatException catch (error) {
      request.response.statusCode = HttpStatus.badRequest;
      request.response.write(error.message);
      await request.response.close();
    } catch (error, stackTrace) {
      stderr.writeln('Sync request failed: $error\n$stackTrace');
      request.response.statusCode = HttpStatus.internalServerError;
      await request.response.close();
    }
  }

  Future<void> _writeSignedResponse(
    HttpResponse response,
    List<int> secret,
    String householdId,
    Map<String, Object?> bodyData,
  ) async {
    final body = jsonEncode(bodyData);
    final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch.toString();
    response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..headers.set('X-Household', _householdHash(householdId))
      ..headers.set('X-Time', timestamp)
      ..headers.set('X-Signature', _signature(secret, timestamp, body));
    response.write(body);
    await response.close();
  }

  Future<String> _readBody(Stream<List<int>> stream) async {
    final builder = BytesBuilder(copy: false);
    var length = 0;
    await for (final chunk in stream) {
      length += chunk.length;
      if (length > _maxBodyBytes) throw const _BodyTooLargeException();
      builder.add(chunk);
    }
    return utf8.decode(builder.takeBytes());
  }

  bool _verify(
    List<int> secret,
    String timestampText,
    String body,
    String signature,
  ) {
    final timestamp = int.tryParse(timestampText);
    if (timestamp == null ||
        (DateTime.now().toUtc().millisecondsSinceEpoch - timestamp).abs() >
            _clockToleranceMs) {
      return false;
    }
    if (signature.length != 64 ||
        signature.toLowerCase() != signature ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(signature)) {
      return false;
    }
    return _constantTimeEquals(
      _signature(secret, timestampText, body),
      signature,
    );
  }

  List<int> _decodeSecret(String value) {
    final secret = base64Url.decode(value);
    if (secret.length != 32) throw const SyncAuthenticationException();
    return secret;
  }

  String _householdHash(String householdId) =>
      sha256.convert(utf8.encode(householdId)).toString();

  String _signature(List<int> secret, String timestamp, String body) =>
      Hmac(sha256, secret).convert(utf8.encode('$timestamp\n$body')).toString();

  bool _constantTimeEquals(String expected, String actual) {
    if (expected.length != actual.length) return false;
    var difference = 0;
    for (var i = 0; i < expected.length; i++) {
      difference |= expected.codeUnitAt(i) ^ actual.codeUnitAt(i);
    }
    return difference == 0;
  }
}

class SyncAuthenticationException implements Exception {
  const SyncAuthenticationException();
}

class _BodyTooLargeException implements Exception {
  const _BodyTooLargeException();
}
