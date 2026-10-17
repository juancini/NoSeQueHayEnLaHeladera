import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:nsd/nsd.dart';

import '../../../core/database/app_database.dart';
import '../../groceries/data/drawing_image_storage.dart';
import '../domain/sync_image_negotiation.dart';
import 'discovered_sync_peer.dart';
import 'sync_data_store.dart';

enum SyncPhase {
  idle,
  starting,
  searching,
  syncing,
  synced,
  discoveryUnavailable,
  error,
}

class SyncState {
  const SyncState({
    required this.phase,
    this.message,
    this.lastSyncedAt,
  });

  static const idle = SyncState(phase: SyncPhase.idle);

  final SyncPhase phase;
  final String? message;
  final DateTime? lastSyncedAt;
}

class SyncService extends WidgetsBindingObserver {
  SyncService(this._appDatabase) : _store = SyncDataStore(_appDatabase);

  static const port = 47622;
  static const _maxBodyBytes = 1024 * 1024;
  static const _maxImageBytes = 10 * 1024 * 1024;
  static const _protocolVersion = 2;
  static const _clockToleranceMs = 5 * 60 * 1000;
  static const _serviceType = DiscoveredSyncPeer.serviceType;

  final AppDatabase _appDatabase;
  final SyncDataStore _store;
  final DrawingImageStorage _imageStorage = DrawingImageStorage();
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10);
  final _states = StreamController<SyncState>.broadcast();
  final Map<String, DiscoveredSyncPeer> _peers = {};
  final Map<String, Future<void>> _inFlight = {};
  final Map<String, Future<void>> _manualInFlight = {};
  final Map<String, _ServerSnapshot> _serverSnapshots = {};

  HttpServer? _server;
  Registration? _registration;
  Discovery? _discovery;
  StreamSubscription<void>? _localChangesSubscription;
  Timer? _localChangeTimer;
  Future<void>? _startOperation;
  Future<void>? _discoveryStartOperation;
  int _generation = 0;
  int _discoveryGeneration = 0;
  String? _householdHash;
  String? _memberId;
  DateTime? _lastSyncedAt;
  SyncState _state = SyncState.idle;

  Stream<SyncState> get states => _states.stream;
  SyncState get state => _state;
  bool get isRunning => _server != null;

  Future<void> start() {
    if (_startOperation != null) return _startOperation!;
    final operation =
        _start().catchError((Object error, StackTrace stackTrace) {
      _publish(SyncPhase.error, 'No se pudo activar la sincronización: $error');
      Error.throwWithStackTrace(error, stackTrace);
    });
    _startOperation = operation;
    return operation.whenComplete(() => _startOperation = null);
  }

  Future<void> _start() async {
    if (_server != null) {
      await refreshDiscovery();
      return;
    }
    final generation = ++_generation;
    _publish(SyncPhase.starting);
    final householdId = await _store.householdId;
    final memberId = await _appDatabase.readLocalState('member_id');
    if (householdId == null || memberId == null) {
      throw StateError(
          'Creá o uníte a un hogar antes de activar la sincronización');
    }
    if (generation != _generation) return;
    _householdHash = _householdHashFor(householdId);
    _memberId = memberId;
    final lastSyncedAt =
        int.tryParse(await _appDatabase.readLocalState('last_sync_at') ?? '');
    _lastSyncedAt = lastSyncedAt == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(lastSyncedAt, isUtc: true)
            .toLocal();
    final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    if (generation != _generation) {
      await server.close(force: true);
      return;
    }
    _server = server;
    server.listen(
      (request) => unawaited(_handleRequest(request)),
      onError: (Object error, StackTrace stackTrace) {
        stderr.writeln('Sync server error: $error\n$stackTrace');
        _publish(SyncPhase.error, 'Error en el servidor local: $error');
      },
    );
    WidgetsBinding.instance.addObserver(this);
    _localChangesSubscription = _appDatabase.localChanges.listen((_) {
      _localChangeTimer?.cancel();
      _localChangeTimer = Timer(
        const Duration(milliseconds: 700),
        () => unawaited(_syncKnownPeers()),
      );
    });
    await _startDiscovery();
  }

  Future<void> stop() async {
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    _localChangeTimer?.cancel();
    _localChangeTimer = null;
    await _localChangesSubscription?.cancel();
    _localChangesSubscription = null;
    Object? cleanupError;
    try {
      await _stopDiscovery();
    } catch (error) {
      cleanupError = error;
    }
    final registration = _registration;
    _registration = null;
    if (registration != null) {
      try {
        await unregister(registration);
      } catch (error) {
        cleanupError ??= error;
      }
    }
    try {
      await _server?.close(force: true);
    } catch (error) {
      cleanupError ??= error;
    }
    _server = null;
    _householdHash = null;
    _memberId = null;
    _peers.clear();
    _inFlight.clear();
    _manualInFlight.clear();
    _serverSnapshots.clear();
    _publish(SyncPhase.idle);
    if (cleanupError != null) {
      throw StateError(
        'No se pudo cerrar toda la sincronización: $cleanupError',
      );
    }
  }

  Future<void> dispose() async {
    Object? cleanupError;
    try {
      await stop();
    } catch (error) {
      cleanupError = error;
    }
    _client.close(force: true);
    await _states.close();
    if (cleanupError != null) {
      throw StateError(
          'No se pudo cerrar el servicio de sincronización: $cleanupError');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(refreshDiscovery());
    } else if (state == AppLifecycleState.paused) {
      unawaited(_pauseDiscovery());
    }
  }

  Future<void> refreshDiscovery() async {
    if (_server == null) return;
    if (_discovery == null) {
      await _startDiscovery();
    } else {
      _publish(SyncPhase.searching, 'Buscando teléfonos del hogar…');
      await _syncKnownPeers();
    }
  }

  Future<void> syncNow() async {
    if (_server == null) {
      throw StateError('Primero activá la sincronización en este teléfono');
    }
    if (_discovery == null) await refreshDiscovery();
    if (_peers.isEmpty) {
      if (_state.phase != SyncPhase.discoveryUnavailable) {
        _publish(
          SyncPhase.searching,
          'Todavía no se encontraron otros teléfonos del hogar.',
        );
      }
      return;
    }
    await _syncKnownPeers();
  }

  Future<void> _startDiscovery() {
    if (_server == null || _discovery != null) return Future.value();
    if (_discoveryStartOperation != null) return _discoveryStartOperation!;
    final operation = _startDiscoveryInternal();
    _discoveryStartOperation = operation;
    return operation.whenComplete(() => _discoveryStartOperation = null);
  }

  Future<void> _startDiscoveryInternal() async {
    if (_server == null || _discovery != null) return;
    final generation = _discoveryGeneration;
    _publish(SyncPhase.searching, 'Buscando teléfonos del hogar…');
    String? registrationError;
    try {
      final memberId = _memberId!;
      if (_registration == null) {
        final registration = await register(
          Service(
            name: 'helh-${memberId.replaceAll('-', '').substring(0, 8)}',
            type: _serviceType,
            port: port,
            txt: {
              'v': Uint8List.fromList(utf8.encode('$_protocolVersion')),
              'hh': Uint8List.fromList(utf8.encode(_householdHash!)),
              'mid': Uint8List.fromList(utf8.encode(memberId)),
            },
          ),
        );
        if (generation != _discoveryGeneration) {
          await unregister(registration);
          return;
        }
        _registration = registration;
      }
    } catch (error) {
      registrationError = error.toString();
    }

    if (generation != _discoveryGeneration || _server == null) return;

    try {
      final discovery = await startDiscovery(
        _serviceType,
        ipLookupType: IpLookupType.any,
      );
      if (generation != _discoveryGeneration) {
        await stopDiscovery(discovery);
        return;
      }
      _discovery = discovery;
      discovery.addServiceListener(_handleDiscoveredService);
      for (final service in discovery.services) {
        _handleDiscoveredService(service, ServiceStatus.found);
      }
      if (registrationError != null) {
        _publish(
          SyncPhase.discoveryUnavailable,
          'No se pudo anunciar este teléfono para la búsqueda automática: '
          '$registrationError. Podés sincronizar desde las opciones manuales.',
        );
      } else {
        _publish(SyncPhase.searching, 'Buscando teléfonos del hogar…');
      }
    } catch (error) {
      _publish(
        SyncPhase.discoveryUnavailable,
        'No se pudo iniciar la búsqueda automática: $error. '
        'Podés sincronizar desde las opciones manuales.',
      );
    }
  }

  Future<void> _stopDiscovery() async {
    _discoveryGeneration++;
    final discovery = _discovery;
    _discovery = null;
    try {
      if (discovery != null) {
        discovery.removeServiceListener(_handleDiscoveredService);
        await stopDiscovery(discovery);
      }
    } finally {
      _peers.clear();
    }
  }

  Future<void> _pauseDiscovery() async {
    try {
      await _stopDiscovery();
      if (_server != null) {
        _publish(
          SyncPhase.searching,
          'La búsqueda se reanudará al volver a la app.',
        );
      }
    } catch (error) {
      _publish(
        SyncPhase.discoveryUnavailable,
        'No se pudo pausar la búsqueda local: $error',
      );
    }
  }

  void _handleDiscoveredService(Service service, ServiceStatus status) {
    final householdHash = _householdHash;
    final localMemberId = _memberId;
    if (householdHash == null || localMemberId == null) return;
    final peer = DiscoveredSyncPeer.parse(
      service,
      householdHash: householdHash,
      localMemberId: localMemberId,
    );
    if (peer == null) return;
    if (status == ServiceStatus.lost) {
      _peers.remove(peer.memberId);
      return;
    }
    _peers[peer.memberId] = peer;
    unawaited(_syncPeer(peer));
  }

  Future<void> _syncKnownPeers() async {
    await Future.wait(_peers.values.map(_syncPeer));
  }

  Future<void> _syncPeer(DiscoveredSyncPeer peer) async {
    final existing = _inFlight[peer.memberId];
    if (existing != null) return existing;
    final operation = _syncPeerWithRetry(peer);
    _inFlight[peer.memberId] = operation;
    try {
      await operation;
    } finally {
      if (identical(_inFlight[peer.memberId], operation)) {
        _inFlight.remove(peer.memberId);
      }
    }
  }

  Future<void> _syncPeerWithRetry(DiscoveredSyncPeer peer) async {
    Object? lastError;
    final generation = _generation;
    for (var attempt = 0; attempt < 4; attempt++) {
      final currentPeer = _peers[peer.memberId] ?? peer;
      var hasTransientFailure = false;
      for (var endpointIndex = 0;
          endpointIndex < currentPeer.endpoints.length;
          endpointIndex++) {
        if (generation != _generation || !_peers.containsKey(peer.memberId)) {
          return;
        }
        try {
          await _performSync(
            currentPeer.endpoints[endpointIndex],
            expectedPeerId: peer.memberId,
            generation: generation,
          );
          return;
        } catch (error) {
          lastError = error;
          if (_isRetryable(error)) {
            hasTransientFailure = true;
          } else if (endpointIndex == currentPeer.endpoints.length - 1) {
            _publish(SyncPhase.error, 'No se pudo sincronizar: $error');
            return;
          }
        }
      }
      if (!hasTransientFailure) {
        _publish(SyncPhase.error, 'No se pudo sincronizar: $lastError');
        return;
      }
      if (attempt < 3 && _peers.containsKey(peer.memberId)) {
        await Future<void>.delayed(Duration(seconds: 1 << attempt));
      } else {
        break;
      }
    }
    _publish(
      SyncPhase.error,
      'No se pudo conectar con un teléfono del hogar: $lastError',
    );
  }

  bool _isRetryable(Object error) =>
      error is SocketException ||
      error is TimeoutException ||
      (error is HttpException &&
          RegExp(r'\(5\d{2}\)$').hasMatch(error.message));

  Future<T> _retryTransfer<T>(Future<T> Function() transfer) async {
    var attempt = 0;
    while (true) {
      try {
        return await transfer();
      } catch (error) {
        if (!_isRetryable(error) || attempt >= 3) rethrow;
        await Future<void>.delayed(Duration(seconds: 1 << attempt));
        attempt++;
      }
    }
  }

  Future<void> syncWith(Uri peer) async {
    for (final discoveredPeer in _peers.values) {
      if (discoveredPeer.endpoints.any(
        (endpoint) => endpoint.host == peer.host && endpoint.port == peer.port,
      )) {
        return _syncPeer(discoveredPeer);
      }
    }
    final key = '${peer.host}:${peer.port}';
    final existing = _manualInFlight[key];
    if (existing != null) return existing;
    final operation = _performSync(peer);
    _manualInFlight[key] = operation;
    try {
      await operation;
    } finally {
      if (identical(_manualInFlight[key], operation)) {
        _manualInFlight.remove(key);
      }
    }
  }

  Future<void> _performSync(
    Uri peer, {
    String? expectedPeerId,
    int? generation,
  }) async {
    final syncGeneration = generation ?? _generation;
    if (peer.scheme != 'http' || peer.host.isEmpty) {
      throw ArgumentError.value(
        peer,
        'peer',
        'Use an HTTP address on the local network',
      );
    }
    _publish(SyncPhase.syncing, 'Sincronizando…');
    try {
      await _exchangeWith(
        peer,
        expectedPeerId: expectedPeerId,
        generation: syncGeneration,
      );
      if (syncGeneration != _generation) return;
      _lastSyncedAt = DateTime.now();
      _publish(SyncPhase.synced, 'Lista sincronizada');
    } catch (error) {
      if (syncGeneration != _generation) return;
      _publish(SyncPhase.error, 'No se pudo sincronizar: $error');
      rethrow;
    }
  }

  Future<void> _exchangeWith(
    Uri peer, {
    String? expectedPeerId,
    required int generation,
  }) async {
    final householdId = await _store.householdId;
    final secretValue = await _appDatabase.readLocalState('household_secret');
    final memberId = await _appDatabase.readLocalState('member_id');
    if (householdId == null || secretValue == null || memberId == null) {
      throw StateError('Creá o uníte a un hogar antes de sincronizar');
    }
    final householdHash = _householdHashFor(householdId);
    final secret = _decodeSecret(secretValue);
    final random = Random.secure();
    final nonce =
        base64UrlEncode(List<int>.generate(32, (_) => random.nextInt(256)));
    final verification = await _postSigned(
      peer,
      path: '/sync/verify',
      householdHash: householdHash,
      memberId: memberId,
      secret: secret,
      bodyData: {
        'member_id': memberId,
        'household_hash': householdHash,
        'nonce': nonce,
      },
    );
    final authenticatedPeerId = verification['member_id'];
    if (authenticatedPeerId is! String ||
        authenticatedPeerId.isEmpty ||
        authenticatedPeerId == memberId ||
        verification['nonce'] != nonce ||
        verification['protocol_version'] != _protocolVersion ||
        (expectedPeerId != null && authenticatedPeerId != expectedPeerId)) {
      if (verification['protocol_version'] != _protocolVersion) {
        throw const FormatException(
          'El otro dispositivo usa una versión de sincronización incompatible. '
          'Actualizá ambos dispositivos.',
        );
      }
      throw const SyncAuthenticationException();
    }
    if (generation != _generation) return;
    final requestData = <String, Object?>{
      ...await _store.requestFor(peer.host, peerId: authenticatedPeerId),
      'member_id': memberId,
      'household_hash': householdHash,
    };
    final locallyAvailable = await _imageStorage.availableHashes();
    requestData['changes'] =
        _sanitizeChanges(requestData['changes'], locallyAvailable);
    requestData['image_hashes'] = locallyAvailable.toList()..sort();
    final manifest = await _postSigned(
      peer,
      path: '/sync/manifest',
      householdHash: householdHash,
      memberId: memberId,
      secret: secret,
      bodyData: requestData,
    );
    if (manifest['member_id'] != authenticatedPeerId) {
      throw const SyncAuthenticationException();
    }
    final snapshotId = manifest['snapshot_id'];
    final uploadToServer = _readHashList(manifest['upload_to_server']);
    final uploadToClient = _readHashList(manifest['upload_to_client']);
    final outgoingReferences = _referencedHashes(
      requestData['changes']! as List<Map<String, Object?>>,
    );
    final remoteChanges = _sanitizeChanges(
      manifest['changes'],
      {...locallyAvailable, ...uploadToClient},
    );
    final remoteReferences = _referencedHashes(remoteChanges);
    if (snapshotId is! String || snapshotId.isEmpty) {
      throw const FormatException('La negociación de imágenes no es válida');
    }
    if (!outgoingReferences.containsAll(uploadToServer) ||
        !remoteReferences.containsAll(uploadToClient)) {
      throw const FormatException(
        'La negociación solicita imágenes fuera de los cambios sincronizados',
      );
    }
    for (final hash in uploadToServer) {
      final bytes = await _imageStorage.readHash(hash);
      if (bytes == null) {
        throw HttpException('Falta el dibujo $hash en este dispositivo');
      }
      await _retryTransfer(
        () => _sendImage(
          peer,
          hash: hash,
          bytes: bytes,
          householdHash: householdHash,
          memberId: memberId,
          secret: secret,
        ),
      );
    }
    for (final hash in uploadToClient) {
      final bytes = await _retryTransfer(
        () => _getImage(
          peer,
          hash: hash,
          householdHash: householdHash,
          memberId: memberId,
          secret: secret,
        ),
      );
      await _imageStorage.storeDownloaded(hash, bytes);
    }
    requestData['snapshot_id'] = snapshotId;
    final responseData = await _postSigned(
      peer,
      path: '/sync',
      householdHash: householdHash,
      memberId: memberId,
      secret: secret,
      bodyData: requestData,
    );
    if (responseData['member_id'] != authenticatedPeerId) {
      throw const SyncAuthenticationException();
    }
    if (responseData['cursor'] != manifest['cursor'] ||
        jsonEncode(responseData['changes']) != jsonEncode(manifest['changes'])) {
      throw const FormatException(
        'Las filas sincronizadas no coinciden con la negociación de imágenes',
      );
    }
    if (generation != _generation) return;
    await _store.applyResponse(
      peerId: authenticatedPeerId,
      peerAddress: peer.host,
      response: responseData,
      sentThrough: requestData['cursor']! as int,
    );
  }

  Future<Map<String, Object?>> _postSigned(
    Uri peer, {
    required String path,
    required String householdHash,
    required String memberId,
    required List<int> secret,
    required Map<String, Object?> bodyData,
  }) async {
    final body = jsonEncode(bodyData);
    final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch.toString();
    final requestUri = peer.replace(
      path: path,
      query: null,
      fragment: null,
      port: peer.hasPort ? peer.port : port,
    );
    final request = await _client.postUrl(requestUri).timeout(
          const Duration(seconds: 15),
        );
    request.headers
      ..set(HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8')
      ..set('X-Household', householdHash)
      ..set('X-Member', memberId)
      ..set('X-Time', timestamp)
      ..set('X-Signature', _signature(secret, timestamp, body));
    request.write(body);
    final response = await request.close().timeout(const Duration(seconds: 30));
    final responseBody = await _readBody(response).timeout(
      const Duration(seconds: 30),
    );
    if (response.statusCode != HttpStatus.ok) {
      if (response.statusCode == HttpStatus.unauthorized) {
        throw const SyncAuthenticationException();
      }
      if (response.statusCode >= 400 && response.statusCode < 500) {
        throw FormatException(
          'El otro dispositivo rechazó la solicitud '
          '(${response.statusCode})',
        );
      }
      throw HttpException(
        'El otro dispositivo respondió con un error (${response.statusCode})',
        uri: requestUri,
      );
    }
    final responseTime = response.headers.value('X-Time');
    final responseSignature = response.headers.value('X-Signature');
    if (responseTime == null ||
        responseSignature == null ||
        response.headers.value('X-Household') != householdHash ||
        !_verify(
          secret,
          responseTime,
          responseBody,
          responseSignature,
        )) {
      throw const FormatException(
          'La respuesta del otro dispositivo no es válida');
    }
    final decoded = jsonDecode(responseBody);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
          'La respuesta de sincronización no es válida');
    }
    final responseData = Map<String, Object?>.from(decoded);
    if (responseData['household_hash'] != householdHash) {
      throw const FormatException('La respuesta pertenece a otro hogar');
    }
    return responseData;
  }

  List<String> _readHashList(Object? value) {
    if (value is! List || value.any((entry) => entry is! String)) {
      throw const FormatException('La lista de imágenes no es válida');
    }
    final hashes = value.cast<String>();
    if (hashes.any((hash) => !RegExp(r'^[0-9a-f]{64}$').hasMatch(hash))) {
      throw const FormatException('La lista contiene un hash inválido');
    }
    return hashes;
  }

  Future<void> _sendImage(
    Uri peer, {
    required String hash,
    required Uint8List bytes,
    required String householdHash,
    required String memberId,
    required List<int> secret,
  }) async {
    await _sendSignedBinary(
      peer,
      method: 'POST',
      path: '/sync/images/$hash',
      bytes: bytes,
      householdHash: householdHash,
      memberId: memberId,
      secret: secret,
    );
  }

  Future<Uint8List> _getImage(
    Uri peer, {
    required String hash,
    required String householdHash,
    required String memberId,
    required List<int> secret,
  }) async {
    final requestUri = peer.replace(
      path: '/sync/images/$hash',
      query: null,
      fragment: null,
      port: peer.hasPort ? peer.port : port,
    );
    final request = await _client.getUrl(requestUri).timeout(
          const Duration(seconds: 15),
        );
    final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch.toString();
    request.headers
      ..set('X-Household', householdHash)
      ..set('X-Member', memberId)
      ..set('X-Time', timestamp)
      ..set('X-Signature', _signature(secret, timestamp, ''));
    final response = await request.close().timeout(const Duration(seconds: 30));
    final bytes = await _readBytes(response, _maxImageBytes).timeout(
      const Duration(seconds: 30),
    );
    if (response.statusCode != HttpStatus.ok) {
      _throwHttpStatus(response.statusCode, requestUri);
    }
    final responseTime = response.headers.value('X-Time');
    final responseSignature = response.headers.value('X-Signature');
    if (responseTime == null ||
        responseSignature == null ||
        response.headers.value('X-Household') != householdHash ||
        !_verify(secret, responseTime, bytes, responseSignature)) {
      throw const FormatException('La imagen recibida no está autenticada');
    }
    if (sha256.convert(bytes).toString() != hash) {
      throw const FormatException('El hash de la imagen descargada no coincide');
    }
    return bytes;
  }

  Future<void> _sendSignedBinary(
    Uri peer, {
    required String method,
    required String path,
    required Uint8List bytes,
    required String householdHash,
    required String memberId,
    required List<int> secret,
  }) async {
    final requestUri = peer.replace(
      path: path,
      query: null,
      fragment: null,
      port: peer.hasPort ? peer.port : port,
    );
    final request = await _client.openUrl(method, requestUri).timeout(
          const Duration(seconds: 15),
        );
    final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch.toString();
    request.headers
      ..set(HttpHeaders.contentTypeHeader, 'image/png')
      ..set('X-Household', householdHash)
      ..set('X-Member', memberId)
      ..set('X-Time', timestamp)
      ..set('X-Signature', _signature(secret, timestamp, bytes));
    request.add(bytes);
    final response = await request.close().timeout(const Duration(seconds: 30));
    final responseBytes = await _readBytes(response, _maxBodyBytes).timeout(
      const Duration(seconds: 30),
    );
    if (response.statusCode != HttpStatus.ok) {
      _throwHttpStatus(response.statusCode, requestUri);
    }
    final responseTime = response.headers.value('X-Time');
    final responseSignature = response.headers.value('X-Signature');
    if (responseTime == null ||
        responseSignature == null ||
        response.headers.value('X-Household') != householdHash ||
        !_verify(secret, responseTime, responseBytes, responseSignature)) {
      throw const FormatException('La respuesta de imagen no está autenticada');
    }
  }

  void _throwHttpStatus(int statusCode, Uri uri) {
    if (statusCode == HttpStatus.unauthorized) {
      throw const SyncAuthenticationException();
    }
    if (statusCode >= 400 && statusCode < 500) {
      throw FormatException('El otro dispositivo rechazó la solicitud ($statusCode)');
    }
    throw HttpException('El otro dispositivo respondió con un error ($statusCode)', uri: uri);
  }

  Future<Uint8List> _readBytes(
    Stream<List<int>> stream,
    int maxBytes,
  ) async {
    final builder = BytesBuilder(copy: false);
    var length = 0;
    await for (final chunk in stream) {
      length += chunk.length;
      if (length > maxBytes) throw const _BodyTooLargeException();
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  Future<void> _handleVerification(HttpRequest request) async {
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
          senderId.length > 128 ||
          timestamp == null ||
          signature == null ||
          householdHash != _householdHashFor(householdId) ||
          !_verify(_decodeSecret(secretValue), timestamp, body, signature)) {
        throw const SyncAuthenticationException();
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic> ||
          decoded['member_id'] != senderId ||
          decoded['household_hash'] != householdHash ||
          decoded['nonce'] is! String ||
          (decoded['nonce'] as String).length < 32 ||
          (decoded['nonce'] as String).length > 128) {
        throw const FormatException('Invalid sync verification request');
      }
      final memberId = await _appDatabase.readLocalState('member_id');
      if (memberId == null) throw StateError('Missing local member identity');
      await _writeSignedResponse(
        request.response,
        _decodeSecret(secretValue),
        householdId,
        {
          'member_id': memberId,
          'household_hash': householdHash,
          'nonce': decoded['nonce'],
          'protocol_version': _protocolVersion,
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
      stderr.writeln('Sync verification failed: $error\n$stackTrace');
      request.response.statusCode = HttpStatus.internalServerError;
      await request.response.close();
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    if (request.method == 'POST' && request.uri.path == '/sync/verify') {
      await _handleVerification(request);
      return;
    }
    if (request.method == 'POST' && request.uri.path == '/sync/manifest') {
      await _handleManifest(request);
      return;
    }
    final imagePath =
        RegExp(r'^/sync/images/([0-9a-f]{64})$').firstMatch(request.uri.path);
    if (imagePath != null &&
        (request.method == 'POST' || request.method == 'GET')) {
      if (request.method == 'POST') {
        await _handleImageUpload(request, imagePath.group(1)!);
      } else {
        await _handleImageDownload(request, imagePath.group(1)!);
      }
      return;
    }
    if (request.method != 'POST' || request.uri.path != '/sync') {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    final generation = _generation;
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
      if (householdHash != _householdHashFor(householdId) ||
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
      final snapshotId = decoded['snapshot_id'];
      if (snapshotId is! String) {
        throw const FormatException(
          'An image manifest is required before sync',
        );
      }
      final snapshot = _serverSnapshots[snapshotId];
      if (snapshot == null ||
          snapshot.senderId != senderId ||
          DateTime.now().difference(snapshot.createdAt) >
              const Duration(minutes: 5)) {
        throw const FormatException('The image manifest expired');
      }
      final requestData = Map<String, Object?>.from(decoded)
        ..remove('snapshot_id');
      if (jsonEncode(requestData) != jsonEncode(snapshot.requestData)) {
        throw const FormatException('Sync rows differ from image manifest');
      }
      for (final hash in snapshot.uploadToServer) {
        if (await _imageStorage.readHash(hash) == null) {
          throw const FormatException('A negotiated image is missing');
        }
      }
      if (generation != _generation || _server == null) {
        request.response.statusCode = HttpStatus.serviceUnavailable;
        await request.response.close();
        return;
      }
      final result = await _store.exchange(
        senderId,
        requestData,
        responseChanges: snapshot.responseChanges,
        responseCursor: snapshot.responseCursor,
      );
      _serverSnapshots.remove(snapshotId);
      final memberId = await _appDatabase.readLocalState('member_id');
      if (memberId == null) throw StateError('Missing local member identity');
      await _writeSignedResponse(
        request.response,
        secret,
        householdId,
        {
          ...result,
          'member_id': memberId,
          'household_hash': _householdHashFor(householdId),
        },
      );
      _lastSyncedAt = DateTime.now();
      _publish(SyncPhase.synced, 'Lista sincronizada');
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

  Future<void> _handleManifest(HttpRequest request) async {
    try {
      final body = await _readBody(request);
      final identity = await _authenticatedIdentity(request, utf8.encode(body));
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic> ||
          decoded['member_id'] != identity.memberId ||
          decoded['household_hash'] != identity.householdHash) {
        throw const SyncAuthenticationException();
      }
      final requestData = Map<String, Object?>.from(decoded);
      final since = requestData['since'];
      if (since is! int || since < 0) {
        throw const FormatException('Invalid manifest cursor');
      }
      final clientHashes = _readHashList(requestData['image_hashes']).toSet();
      final clientChanges =
          _sanitizeChanges(requestData['changes'], clientHashes);
      requestData['changes'] = clientChanges;

      final snapshot = await _store.snapshotAfter(since);
      final serverHashes = await _imageStorage.availableHashes();
      final serverChanges =
          _sanitizeChanges(snapshot.changes, serverHashes);
      final clientReferences = _referencedHashes(clientChanges);
      final serverReferences = _referencedHashes(serverChanges);
      final uploadToServer = SyncImageNegotiation.missingHashes(
        referenced: clientReferences,
        available: serverHashes,
      );
      final uploadToClient = SyncImageNegotiation.missingHashes(
        referenced: serverReferences,
        available: clientHashes,
      );
      final snapshotId = base64UrlEncode(
        List<int>.generate(24, (_) => Random.secure().nextInt(256)),
      );
      _serverSnapshots[snapshotId] = _ServerSnapshot(
        senderId: identity.memberId,
        createdAt: DateTime.now(),
        requestData: requestData,
        responseChanges: serverChanges,
        responseCursor: snapshot.cursor,
        uploadToServer: uploadToServer,
        uploadToClient: uploadToClient,
      );
      _pruneSnapshots();
      final memberId = await _appDatabase.readLocalState('member_id');
      if (memberId == null) throw StateError('Missing local member identity');
      await _writeSignedResponse(
        request.response,
        identity.secret,
        identity.householdId,
        {
          'member_id': memberId,
          'household_hash': identity.householdHash,
          'snapshot_id': snapshotId,
          'changes': serverChanges,
          'cursor': snapshot.cursor,
          'upload_to_server': uploadToServer,
          'upload_to_client': uploadToClient,
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
      stderr.writeln('Sync manifest failed: $error\n$stackTrace');
      request.response.statusCode = HttpStatus.internalServerError;
      await request.response.close();
    }
  }

  Future<void> _handleImageUpload(HttpRequest request, String hash) async {
    try {
      final bytes = await _readBytes(request, _maxImageBytes);
      final identity = await _authenticatedIdentity(request, bytes);
      if (sha256.convert(bytes).toString() != hash) {
        throw const FormatException('Image hash does not match its contents');
      }
      if (!_serverSnapshots.values.any(
        (snapshot) =>
            snapshot.senderId == identity.memberId &&
            snapshot.uploadToServer.contains(hash) &&
            DateTime.now().difference(snapshot.createdAt) <=
                const Duration(minutes: 5),
      )) {
        throw const FormatException('Image was not requested by a manifest');
      }
      await _imageStorage.storeDownloaded(hash, bytes);
      await _writeSignedBinaryResponse(
        request.response,
        identity.secret,
        identity.householdId,
        Uint8List(0),
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
      stderr.writeln('Sync image upload failed: $error\n$stackTrace');
      request.response.statusCode = HttpStatus.internalServerError;
      await request.response.close();
    }
  }

  Future<void> _handleImageDownload(HttpRequest request, String hash) async {
    try {
      final identity = await _authenticatedIdentity(request, const []);
      final isRequested = _serverSnapshots.values.any(
        (snapshot) =>
            snapshot.senderId == identity.memberId &&
            snapshot.uploadToClient.contains(hash) &&
            DateTime.now().difference(snapshot.createdAt) <=
                const Duration(minutes: 5),
      );
      if (!isRequested) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      final bytes = await _imageStorage.readHash(hash);
      if (bytes == null) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      await _writeSignedBinaryResponse(
        request.response,
        identity.secret,
        identity.householdId,
        bytes,
      );
    } on SyncAuthenticationException {
      request.response.statusCode = HttpStatus.unauthorized;
      await request.response.close();
    } on FormatException catch (error) {
      request.response.statusCode = HttpStatus.badRequest;
      request.response.write(error.message);
      await request.response.close();
    } catch (error, stackTrace) {
      stderr.writeln('Sync image download failed: $error\n$stackTrace');
      request.response.statusCode = HttpStatus.internalServerError;
      await request.response.close();
    }
  }

  Future<_AuthenticatedRequest> _authenticatedIdentity(
    HttpRequest request,
    List<int> body,
  ) async {
    final householdId = await _store.householdId;
    final secretValue = await _appDatabase.readLocalState('household_secret');
    final memberId = request.headers.value('X-Member');
    final timestamp = request.headers.value('X-Time');
    final signature = request.headers.value('X-Signature');
    final householdHash = request.headers.value('X-Household');
    if (householdId == null ||
        secretValue == null ||
        memberId == null ||
        memberId.isEmpty ||
        memberId.length > 128 ||
        timestamp == null ||
        signature == null ||
        householdHash != _householdHashFor(householdId) ||
        !_verifyBytes(_decodeSecret(secretValue), timestamp, body, signature)) {
      throw const SyncAuthenticationException();
    }
    return _AuthenticatedRequest(
      householdId: householdId,
      householdHash: householdHash!,
      memberId: memberId,
      secret: _decodeSecret(secretValue),
    );
  }

  List<Map<String, Object?>> _sanitizeChanges(
    Object? value,
    Set<String> availableHashes,
  ) {
    if (value is! List) throw const FormatException('changes must be a list');
    return value.map((change) {
      if (change is! Map ||
          change['table'] is! String ||
          change['row'] is! Map) {
        throw const FormatException('Invalid change record');
      }
      final table = change['table'] as String;
      final row = Map<String, Object?>.from(change['row'] as Map);
      if (table == 'product' && row['image_src'] != null) {
        if (row['image_src'] is! String) {
          throw const FormatException('Invalid product image');
        }
        final hash = _imageStorage.hashFromSource(row['image_src'] as String?);
        if (hash == null) throw const FormatException('Invalid product image');
        if (!availableHashes.contains(hash)) row['image_src'] = null;
      }
      return {'table': table, 'row': row};
    }).toList();
  }

  Set<String> _referencedHashes(List<Map<String, Object?>> changes) {
    final hashes = <String>{};
    for (final change in changes) {
      if (change['table'] != 'product') continue;
      final row = change['row']! as Map<String, Object?>;
      final hash = _imageStorage.hashFromSource(row['image_src'] as String?);
      if (hash != null) hashes.add(hash);
    }
    return hashes;
  }

  void _pruneSnapshots() {
    final now = DateTime.now();
    _serverSnapshots.removeWhere(
      (_, snapshot) =>
          now.difference(snapshot.createdAt) > const Duration(minutes: 5),
    );
    while (_serverSnapshots.length > 8) {
      final oldest = _serverSnapshots.entries.reduce(
        (a, b) => a.value.createdAt.isBefore(b.value.createdAt) ? a : b,
      );
      _serverSnapshots.remove(oldest.key);
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
      ..headers.set('X-Household', _householdHashFor(householdId))
      ..headers.set('X-Time', timestamp)
      ..headers.set('X-Signature', _signature(secret, timestamp, body));
    response.write(body);
    await response.close();
  }

  Future<void> _writeSignedBinaryResponse(
    HttpResponse response,
    List<int> secret,
    String householdId,
    Uint8List bytes,
  ) async {
    final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch.toString();
    response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType('image', 'png')
      ..headers.set('X-Household', _householdHashFor(householdId))
      ..headers.set('X-Time', timestamp)
      ..headers.set('X-Signature', _signature(secret, timestamp, bytes));
    response.add(bytes);
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
    Object body,
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
    return _verifyBytes(
      secret,
      timestampText,
      body is String ? utf8.encode(body) : body as List<int>,
      signature,
    );
  }

  bool _verifyBytes(
    List<int> secret,
    String timestampText,
    List<int> body,
    String signature,
  ) {
    final timestamp = int.tryParse(timestampText);
    if (timestamp == null ||
        (DateTime.now().toUtc().millisecondsSinceEpoch - timestamp).abs() >
            _clockToleranceMs ||
        signature.length != 64 ||
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

  String _householdHashFor(String householdId) =>
      sha256.convert(utf8.encode(householdId)).toString();

  String _signature(List<int> secret, String timestamp, Object body) {
    final bodyBytes = body is String ? utf8.encode(body) : body as List<int>;
    return Hmac(sha256, secret)
        .convert([...utf8.encode('$timestamp\n'), ...bodyBytes])
        .toString();
  }

  bool _constantTimeEquals(String expected, String actual) {
    if (expected.length != actual.length) return false;
    var difference = 0;
    for (var i = 0; i < expected.length; i++) {
      difference |= expected.codeUnitAt(i) ^ actual.codeUnitAt(i);
    }
    return difference == 0;
  }

  void _publish(SyncPhase phase, [String? message]) {
    _state = SyncState(
      phase: phase,
      message: message,
      lastSyncedAt: _lastSyncedAt,
    );
    if (!_states.isClosed) _states.add(_state);
  }
}

class SyncAuthenticationException implements Exception {
  const SyncAuthenticationException();

  @override
  String toString() => 'El otro dispositivo no pudo autenticarse';
}

class _BodyTooLargeException implements Exception {
  const _BodyTooLargeException();
}

class _AuthenticatedRequest {
  const _AuthenticatedRequest({
    required this.householdId,
    required this.householdHash,
    required this.memberId,
    required this.secret,
  });

  final String householdId;
  final String householdHash;
  final String memberId;
  final List<int> secret;
}

class _ServerSnapshot {
  const _ServerSnapshot({
    required this.senderId,
    required this.createdAt,
    required this.requestData,
    required this.responseChanges,
    required this.responseCursor,
    required this.uploadToServer,
    required this.uploadToClient,
  });

  final String senderId;
  final DateTime createdAt;
  final Map<String, Object?> requestData;
  final List<Map<String, Object?>> responseChanges;
  final int responseCursor;
  final List<String> uploadToServer;
  final List<String> uploadToClient;
}
