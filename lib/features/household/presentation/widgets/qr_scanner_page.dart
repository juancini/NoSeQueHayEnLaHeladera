import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class QrScannerPage extends StatefulWidget {
  const QrScannerPage({super.key});

  @override
  State<QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<QrScannerPage> {
  bool _handled = false;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Escanear invitación')),
        body: Column(
          children: [
            Expanded(
              child: MobileScanner(
                onDetect: (capture) {
                  if (_handled) return;
                  if (capture.barcodes.isEmpty) return;
                  final value = capture.barcodes.first.rawValue;
                  if (value == null) return;
                  _handled = true;
                  Navigator.of(context).pop(value);
                },
                errorBuilder: (context, error, child) => _CameraError(
                  permissionDenied:
                      error.errorCode == MobileScannerErrorCode.permissionDenied,
                  onPaste: _pasteInvite,
                ),
              ),
            ),
            const SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Alineá el código QR dentro del recuadro',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _pasteInvite,
          icon: const Icon(Icons.content_paste),
          label: const Text('Pegar código'),
        ),
      );

  Future<void> _pasteInvite() async {
    final payload = await showDialog<String>(
      context: context,
      builder: (_) => const _PasteInviteDialog(),
    );
    if (payload != null && mounted) {
      Navigator.of(context).pop(payload);
    }
  }
}

class _CameraError extends StatelessWidget {
  const _CameraError({
    required this.permissionDenied,
    required this.onPaste,
  });

  final bool permissionDenied;
  final VoidCallback onPaste;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography_outlined, size: 48),
              const SizedBox(height: 16),
              Text(
                permissionDenied
                    ? 'No hay permiso para usar la cámara. Podés habilitarlo en la configuración del teléfono o pegar el código.'
                    : 'No se pudo iniciar la cámara. Podés intentarlo de nuevo o pegar el código.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onPaste,
                icon: const Icon(Icons.content_paste),
                label: const Text('Pegar código'),
              ),
            ],
          ),
        ),
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
