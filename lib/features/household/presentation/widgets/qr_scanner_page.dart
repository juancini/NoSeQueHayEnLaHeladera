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
        body: Stack(
          alignment: Alignment.center,
          children: [
            MobileScanner(
              onDetect: (capture) {
                if (_handled) return;
                if (capture.barcodes.isEmpty) return;
                final value = capture.barcodes.first.rawValue;
                if (value == null) return;
                _handled = true;
                Navigator.of(context).pop(value);
              },
            ),
            Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 3),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            const Positioned(
              bottom: 40,
              left: 24,
              right: 24,
              child: Text(
                'Alineá el código QR dentro del recuadro',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ],
        ),
      );
}
