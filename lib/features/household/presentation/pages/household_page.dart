import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../sync/data/sync_service.dart';
import '../../../sync/presentation/providers/sync_providers.dart';
import '../../domain/entities/household_invite.dart';
import '../providers/household_providers.dart';
import '../widgets/qr_scanner_page.dart';

class HouseholdPage extends ConsumerStatefulWidget {
  const HouseholdPage({super.key, this.invitePayload});

  final String? invitePayload;

  @override
  ConsumerState<HouseholdPage> createState() => _HouseholdPageState();
}

class _HouseholdPageState extends ConsumerState<HouseholdPage> {
  final _addressController = TextEditingController();
  bool _serverRunning = false;
  bool _syncing = false;
  SyncState _syncState = SyncState.idle;
  StreamSubscription<SyncState>? _syncStateSubscription;

  @override
  void initState() {
    super.initState();
    final invitePayload = widget.invitePayload;
    if (invitePayload != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _reviewInvite(context, ref, invitePayload);
      });
    }
  }

  @override
  void dispose() {
    _addressController.dispose();
    unawaited(_syncStateSubscription?.cancel());
    super.dispose();
  }

  Future<void> _createHousehold(BuildContext context, WidgetRef ref) async {
    final result = await _askForNames(context, title: 'Crear un hogar');
    if (result == null || !context.mounted) return;
    try {
      await ref
          .read(householdRepositoryProvider)
          .createHousehold(result.$1, result.$2);
      if (context.mounted) ref.invalidate(currentHouseholdProvider);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo crear el hogar: $error')),
        );
      }
    }
  }

  Future<void> _joinHousehold(BuildContext context, WidgetRef ref) async {
    final payload = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const QrScannerPage()),
    );
    if (payload == null || !context.mounted) return;
    await _reviewInvite(context, ref, payload);
  }

  Future<void> _pasteInvite(BuildContext context, WidgetRef ref) async {
    final payload = await showDialog<String>(
      context: context,
      builder: (_) => const _PasteInviteDialog(),
    );
    if (payload == null || !context.mounted) return;
    await _reviewInvite(context, ref, payload);
  }

  Future<void> _reviewInvite(
    BuildContext context,
    WidgetRef ref,
    String payload,
  ) async {
    late final HouseholdInvite invite;
    try {
      invite = HouseholdInvite.fromPayload(payload);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('La invitación no es válida: $error')),
        );
      }
      return;
    }
    try {
      final currentHousehold =
          await ref.read(householdRepositoryProvider).current();
      if (!context.mounted) return;
      if (currentHousehold?.id == invite.householdId) return;
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('No se pudo comprobar el hogar actual: $error')),
        );
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Unirte a este hogar'),
        content: Text(
          'Hogar: ${invite.householdName}\nID: ${invite.householdId}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final name = await _askForName(context, 'Tu nombre');
    if (name == null || !context.mounted) return;
    try {
      await ref.read(householdRepositoryProvider).joinFromQr(payload, name);
      ref.invalidate(currentHouseholdProvider);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo usar la invitación: $error')),
        );
      }
    }
  }

  Future<void> _showInvite(BuildContext context, WidgetRef ref) async {
    try {
      final payload =
          await ref.read(householdRepositoryProvider).inviteQrPayload();
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Invitá a tu hogar'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Escaneá este código desde el otro teléfono.'),
              const SizedBox(height: 16),
              SizedBox.square(
                dimension: 220,
                child: QrImageView(
                  data: payload,
                  size: 220,
                  errorStateBuilder: (context, error) => Text(
                    'No se pudo generar el código QR: $error',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Listo'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo generar la invitación: $error')),
        );
      }
    }
  }

  Future<void> _startSyncServer() async {
    try {
      final service = ref.read(syncServiceProvider);
      await service.start();
      await _syncStateSubscription?.cancel();
      _syncStateSubscription = service.states.listen((state) {
        if (mounted) setState(() => _syncState = state);
      });
      if (mounted) {
        setState(() {
          _serverRunning = service.isRunning;
          _syncState = service.state;
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('No se pudo iniciar el servidor local: $error')),
        );
      }
    }
  }

  Future<void> _stopSyncServer() async {
    try {
      final service = ref.read(syncServiceProvider);
      await service.stop();
      if (mounted) {
        setState(() {
          _serverRunning = service.isRunning;
          _syncState = service.state;
        });
      }
    } catch (error) {
      if (mounted) {
        final service = ref.read(syncServiceProvider);
        setState(() {
          _serverRunning = service.isRunning;
          _syncState = service.state;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('No se pudo detener la sincronización: $error')),
        );
      }
    }
  }

  Future<void> _syncWithAddress() async {
    final address = InternetAddress.tryParse(_addressController.text.trim());
    if (address == null ||
        address.type != InternetAddressType.IPv4 ||
        !_isPrivateAddress(address.address)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Ingresá una dirección IPv4 de tu red local')),
      );
      return;
    }
    setState(() => _syncing = true);
    try {
      final service = ref.read(syncServiceProvider);
      await service.syncWith(
            Uri(
              scheme: 'http',
              host: address.address,
              port: SyncService.port,
            ),
          );
      if (mounted) {
        setState(() => _syncState = service.state);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lista sincronizada')),
        );
      }
    } catch (error) {
      if (mounted) {
        if (ref.exists(syncServiceProvider)) {
          setState(() => _syncState = ref.read(syncServiceProvider).state);
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo sincronizar: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _syncNow() async {
    setState(() => _syncing = true);
    try {
      final service = ref.read(syncServiceProvider);
      await service.syncNow();
      if (mounted) setState(() => _syncState = service.state);
    } catch (error) {
      if (mounted) {
        final service = ref.read(syncServiceProvider);
        setState(() => _syncState = service.state);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo sincronizar: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  bool _isPrivateAddress(String value) {
    final octets = value.split('.').map(int.tryParse).toList();
    if (octets.length != 4 || octets.any((octet) => octet == null)) {
      return false;
    }
    final first = octets[0]!;
    final second = octets[1]!;
    return first == 10 ||
        (first == 172 && second >= 16 && second <= 31) ||
        (first == 192 && second == 168) ||
        (first == 169 && second == 254);
  }

  @override
  Widget build(BuildContext context) {
    final household = ref.watch(currentHouseholdProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Tu hogar')),
      body: household.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            Center(child: Text('No se pudo cargar el hogar: $error')),
        data: (current) {
          final syncService = ref.exists(syncServiceProvider)
              ? ref.watch(syncServiceProvider)
              : null;
          final serverRunning =
              _serverRunning || (syncService?.isRunning ?? false);
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Icon(Icons.home_outlined, size: 56),
              const SizedBox(height: 12),
              Text(
                current?.name ?? 'Compartí la lista de compras',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                current == null
                    ? 'Creá un hogar o sumate con una invitación QR para agregar productos. Los productos existentes siguen disponibles sin conexión.'
                    : 'La lista queda guardada en este teléfono. Activá la red local en ambos teléfonos para sincronizar.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              if (current == null) ...[
                FilledButton.icon(
                  onPressed: () => _createHousehold(context, ref),
                  icon: const Icon(Icons.add_home_outlined),
                  label: const Text('Crear un hogar'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _joinHousehold(context, ref),
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Escanear invitación'),
                ),
                TextButton.icon(
                  onPressed: () => _pasteInvite(context, ref),
                  icon: const Icon(Icons.content_paste),
                  label: const Text('Pegar código de invitación'),
                ),
              ] else ...[
                FilledButton.icon(
                  onPressed: () => _showInvite(context, ref),
                  icon: const Icon(Icons.qr_code_2),
                  label: const Text('Invitar a alguien'),
                ),
                const SizedBox(height: 28),
                Text('Sincronización en red local',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(
                  'Con ambos teléfonos en la misma red y la app abierta, '
                  'la sincronización se realiza automáticamente.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                StreamBuilder<SyncState>(
                  stream: syncService?.states ?? const Stream<SyncState>.empty(),
                  initialData: syncService?.state ?? _syncState,
                  builder: (context, snapshot) {
                    final state =
                        snapshot.data ?? syncService?.state ?? _syncState;
                    final status = !serverRunning
                        ? 'Activá la sincronización en ambos teléfonos.'
                        : switch (state.phase) {
                            SyncPhase.starting => 'Iniciando sincronización…',
                            SyncPhase.searching =>
                              'Buscando teléfonos del hogar…',
                            SyncPhase.syncing => 'Sincronizando…',
                            SyncPhase.synced =>
                              state.message ?? 'Lista sincronizada',
                            SyncPhase.discoveryUnavailable => state.message ??
                                'Búsqueda automática no disponible.',
                            SyncPhase.error =>
                              state.message ?? 'No se pudo sincronizar.',
                            SyncPhase.idle => 'Sincronización desactivada.',
                          };
                    final lastSyncedAt = state.lastSyncedAt;
                    final lastSyncedText = lastSyncedAt == null
                        ? null
                        : 'Última sincronización exitosa: '
                            '${MaterialLocalizations.of(context).formatTimeOfDay(
                            TimeOfDay.fromDateTime(lastSyncedAt),
                          )}.';
                    return Column(
                      children: [
                        Text(status, textAlign: TextAlign.center),
                        if (lastSyncedText != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            lastSyncedText,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: serverRunning ? _stopSyncServer : _startSyncServer,
                  icon: Icon(
                    serverRunning
                        ? Icons.wifi_tethering_off
                        : Icons.wifi_tethering,
                  ),
                  label: Text(
                    serverRunning
                        ? 'Desactivar sincronización'
                        : 'Activar este teléfono',
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: !serverRunning || _syncing ? null : _syncNow,
                  icon: _syncing
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync),
                  label: Text(_syncing ? 'Sincronizando…' : 'Sincronizar ahora'),
                ),
                ExpansionTile(
                  title: const Text('Opciones manuales'),
                  subtitle:
                      const Text('Para diagnóstico o si falla la búsqueda'),
                  tilePadding: EdgeInsets.zero,
                  children: [
                    FutureBuilder<List<NetworkInterface>>(
                      future:
                          NetworkInterface.list(type: InternetAddressType.IPv4),
                      builder: (context, snapshot) {
                        final addresses = snapshot.data
                                ?.expand((interface) => interface.addresses)
                                .map((address) => address.address)
                                .where(_isPrivateAddress)
                                .toSet()
                                .toList() ??
                            const <String>[];
                        if (addresses.isEmpty) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            'IP de este teléfono: ${addresses.join(', ')}',
                          ),
                        );
                      },
                    ),
                    TextField(
                      controller: _addressController,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(
                        labelText: 'IP local del otro teléfono',
                        hintText: '192.168.1.20',
                        prefixIcon: Icon(Icons.wifi),
                      ),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: _syncing ? null : _syncWithAddress,
                      icon: _syncing
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.sync),
                      label: Text(
                        _syncing
                            ? 'Sincronizando…'
                            : 'Sincronizar con esta IP',
                      ),
                    ),
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

Future<(String, String)?> _askForNames(
  BuildContext context, {
  required String title,
}) =>
    showDialog<(String, String)>(
      context: context,
      builder: (_) => _HouseholdNamesDialog(title: title),
    );

Future<String?> _askForName(BuildContext context, String title) =>
    showDialog<String>(
      context: context,
      builder: (_) => _NameDialog(title: title),
    );

class _HouseholdNamesDialog extends StatefulWidget {
  const _HouseholdNamesDialog({required this.title});

  final String title;

  @override
  State<_HouseholdNamesDialog> createState() => _HouseholdNamesDialogState();
}

class _HouseholdNamesDialogState extends State<_HouseholdNamesDialog> {
  final _householdController = TextEditingController();
  final _memberController = TextEditingController();

  @override
  void dispose() {
    _householdController.dispose();
    _memberController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _householdController,
              decoration: const InputDecoration(labelText: 'Nombre del hogar'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _memberController,
              decoration: const InputDecoration(labelText: 'Tu nombre'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final home = _householdController.text.trim();
              final member = _memberController.text.trim();
              if (home.isNotEmpty && member.isNotEmpty) {
                Navigator.of(context).pop((home, member));
              }
            },
            child: const Text('Continuar'),
          ),
        ],
      );
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.title});

  final String title;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: TextField(
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nombre'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final name = _controller.text.trim();
              if (name.isNotEmpty) Navigator.of(context).pop(name);
            },
            child: const Text('Continuar'),
          ),
        ],
      );
}

class _PasteInviteDialog extends StatefulWidget {
  const _PasteInviteDialog();

  @override
  State<_PasteInviteDialog> createState() => _PasteInviteDialogState();
}

class _PasteInviteDialogState extends State<_PasteInviteDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Pegar invitación'),
        content: TextField(
          controller: _controller,
          autofocus: true,
          minLines: 2,
          maxLines: 4,
          keyboardType: TextInputType.multiline,
          decoration: const InputDecoration(
            labelText: 'Código o enlace de invitación',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final payload = _controller.text.trim();
              if (payload.isNotEmpty) Navigator.of(context).pop(payload);
            },
            child: const Text('Continuar'),
          ),
        ],
      );
}
