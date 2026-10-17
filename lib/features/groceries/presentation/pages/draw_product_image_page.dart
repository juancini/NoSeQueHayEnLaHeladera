import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_drawing_board/flutter_drawing_board.dart';
import 'package:flutter_drawing_board/paint_contents.dart';

import '../../data/drawing_png.dart';

class DrawProductImagePage extends StatefulWidget {
  const DrawProductImagePage({super.key});

  @override
  State<DrawProductImagePage> createState() => _DrawProductImagePageState();
}

class _DrawProductImagePageState extends State<DrawProductImagePage> {
  static const _canvasSize = 300.0;
  static const _colors = [
    Color(0xFF202124),
    Color(0xFFE53935),
    Color(0xFFFB8C00),
    Color(0xFFFDD835),
    Color(0xFF43A047),
    Color(0xFF00ACC1),
    Color(0xFF1E88E5),
    Color(0xFF3949AB),
    Color(0xFF8E24AA),
    Color(0xFFD81B60),
    Color(0xFF795548),
    Color(0xFFFFFFFF),
  ];

  final _controller = DrawingController();
  Color _selectedColor = _colors.first;
  bool _erasing = false;

  @override
  void initState() {
    super.initState();
    _controller.setStyle(color: _selectedColor, strokeWidth: 6);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _selectPen(Color color) {
    setState(() {
      _selectedColor = color;
      _erasing = false;
    });
    _controller
      ..setPaintContent(SimpleLine())
      ..setStyle(color: color, strokeWidth: 6);
  }

  void _selectEraser() {
    setState(() => _erasing = true);
    _controller
      ..setPaintContent(Eraser())
      ..setStyle(color: Colors.transparent, strokeWidth: 24);
  }

  Future<void> _finish() async {
    if (_controller.currentIndex == 0) {
      if (mounted) Navigator.of(context).pop<Uint8List?>(null);
      return;
    }
    try {
      await WidgetsBinding.instance.endOfFrame;
      final data = await _controller.getSurfaceImageData() ??
          await _controller.getImageData(pixelRatio: 1);
      if (data == null) {
        throw StateError('No se pudo exportar el dibujo');
      }
      final bytes =
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      final codec = await ui.instantiateImageCodec(bytes);
      try {
        final frame = await codec.getNextFrame();
        final image = frame.image;
        try {
          if (image.width != _canvasSize.toInt() ||
              image.height != _canvasSize.toInt()) {
            throw StateError(
              'El dibujo exportado tiene dimensiones inesperadas '
              '(${image.width} × ${image.height})',
            );
          }
          final rgba = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          if (rgba == null) {
            throw StateError(
                'No se pudo verificar la transparencia del dibujo');
          }
          final pixels = rgba.buffer.asUint8List(
            rgba.offsetInBytes,
            rgba.lengthInBytes,
          );
          final hasVisiblePixel = DrawingPng.hasVisiblePixels(pixels);
          if (!mounted) return;
          Navigator.of(context).pop<Uint8List?>(
            hasVisiblePixel ? Uint8List.fromList(bytes) : null,
          );
        } finally {
          image.dispose();
        }
      } finally {
        codec.dispose();
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar el dibujo: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Dibujar producto'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop<Uint8List?>(null),
              child: const Text('Omitir'),
            ),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 4,
                  children: [
                    IconButton(
                      tooltip: 'Lápiz',
                      onPressed: () => _selectPen(_selectedColor),
                      isSelected: !_erasing,
                      icon: const Icon(Icons.edit),
                    ),
                    IconButton(
                      tooltip: 'Borrador',
                      onPressed: _selectEraser,
                      isSelected: _erasing,
                      icon: const Icon(Icons.auto_fix_normal),
                    ),
                    IconButton(
                      tooltip: 'Deshacer',
                      onPressed:
                          _controller.canUndo() ? _controller.undo : null,
                      icon: const Icon(Icons.undo),
                    ),
                    IconButton(
                      tooltip: 'Rehacer',
                      onPressed:
                          _controller.canRedo() ? _controller.redo : null,
                      icon: const Icon(Icons.redo),
                    ),
                    IconButton(
                      tooltip: 'Limpiar',
                      onPressed:
                          _controller.canClear() ? _controller.clear : null,
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final color in _colors)
                      Semantics(
                        label: 'Color ${color.toARGB32().toRadixString(16)}',
                        button: true,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => _selectPen(color),
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: color == _selectedColor && !_erasing
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.black26,
                                width: color == _selectedColor && !_erasing
                                    ? 3
                                    : 1,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                Center(
                  child: Container(
                    width: _canvasSize,
                    height: _canvasSize,
                    color: const Color(0xFFE7E7E7),
                    child: DrawingBoard(
                      controller: _controller,
                      background: const SizedBox(
                        width: _canvasSize,
                        height: _canvasSize,
                        child: ColoredBox(color: Colors.transparent),
                      ),
                      boardConstrained: true,
                      boardPanEnabled: false,
                      boardScaleEnabled: false,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'El fondo transparente no se guarda en el dibujo.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _finish,
                  icon: const Icon(Icons.check),
                  label: const Text('Usar dibujo'),
                ),
              ],
            ),
          ),
        ),
      );
}
