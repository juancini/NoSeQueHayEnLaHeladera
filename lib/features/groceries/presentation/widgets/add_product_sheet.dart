import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/grocery_providers.dart';
import '../pages/draw_product_image_page.dart';

class AddProductSheet extends ConsumerStatefulWidget {
  const AddProductSheet({super.key});

  @override
  ConsumerState<AddProductSheet> createState() => _AddProductSheetState();
}

class _AddProductSheetState extends ConsumerState<AddProductSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _customDaysController = TextEditingController();
  int? _selectedDays = 3;
  bool _saving = false;
  Uint8List? _imagePng;
  static const _suggestions = [3, 5, 7];

  @override
  void dispose() {
    _nameController.dispose();
    _customDaysController.dispose();
    super.dispose();
  }

  int? get _days {
    if (_selectedDays != null) return _selectedDays;
    return int.tryParse(_customDaysController.text.trim());
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref.read(groceryRepositoryProvider).addProduct(
            _nameController.text,
            _days!,
            imagePng: _imagePng,
          );
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo agregar el producto: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _drawImage() async {
    final image = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(builder: (_) => const DrawProductImagePage()),
    );
    if (mounted && image != null) setState(() => _imagePng = image);
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          24,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 24,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Agregar producto', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 20),
              TextFormField(
                controller: _nameController,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: '¿Qué producto?',
                  hintText: 'Leche, huevos, tomates…',
                ),
                validator: (value) =>
                    value == null || value.trim().isEmpty ? 'Escribí un nombre' : null,
                onFieldSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 20),
              Text('¿Cuántos días suele durar?', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final days in _suggestions)
                    ChoiceChip(
                      label: Text(days == 7 ? '1 semana' : '$days días'),
                      selected: _selectedDays == days,
                      onSelected: (_) => setState(() => _selectedDays = days),
                    ),
                  ChoiceChip(
                    label: const Text('Otro'),
                    selected: _selectedDays == null,
                    onSelected: (_) => setState(() => _selectedDays = null),
                  ),
                ],
              ),
              if (_selectedDays == null) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _customDaysController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Días'),
                  validator: (_) {
                    if (_selectedDays != null) return null;
                    final days = _days;
                    return days == null || days < 1 ? 'Ingresá al menos 1 día' : null;
                  },
                ),
              ],
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _saving ? null : _drawImage,
                icon: Icon(_imagePng == null ? Icons.draw_outlined : Icons.image),
                label: Text(
                  _imagePng == null
                      ? 'Dibujar imagen (opcional)'
                      : 'Cambiar dibujo',
                ),
              ),
              if (_imagePng != null) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(
                    _imagePng!,
                    width: 64,
                    height: 64,
                    fit: BoxFit.cover,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'Guardando…' : 'Agregar'),
                ),
              ),
            ],
          ),
        ),
      );
}
