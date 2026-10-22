import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/drawing_image_storage.dart';
import '../../domain/entities/product.dart';
import '../../domain/repositories/grocery_repository.dart';
import '../providers/grocery_providers.dart';

class ProductTile extends ConsumerWidget {
  const ProductTile({required this.product, super.key});

  final Product product;
  static final _imageStorage = DrawingImageStorage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repository = ref.read(groceryRepositoryProvider);
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        onLongPressStart: (details) =>
            _showActions(context, repository, details.globalPosition),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _toggleStatus(context, repository),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: Center(
                    child: FutureBuilder<File?>(
                      future: _imageStorage.resolve(product.imageSrc),
                      builder: (context, snapshot) {
                        final file = snapshot.data;
                        if (file != null) {
                          final image = Image.file(
                            file,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => _placeholder(theme),
                          );
                          return product.needsBuying
                              ? ColorFiltered(
                                  colorFilter: const ColorFilter.matrix([
                                    0.2126, 0.7152, 0.0722, 0, 0,
                                    0.2126, 0.7152, 0.0722, 0, 0,
                                    0.2126, 0.7152, 0.0722, 0, 0,
                                    0, 0, 0, 1, 0,
                                  ]),
                                  child: image,
                                )
                              : image;
                        }
                        return _placeholder(theme);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  product.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelMedium,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _toggleStatus(
    BuildContext context,
    GroceryRepository repository,
  ) async {
    try {
      if (product.needsBuying) {
        await repository.markBought(product.id);
      } else {
        await repository.markEmpty(product.id);
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo actualizar: $error')),
        );
      }
    }
  }

  Future<void> _showActions(
    BuildContext context,
    GroceryRepository repository,
    Offset position,
  ) async {
    final screenSize = MediaQuery.sizeOf(context);
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        screenSize.width - position.dx,
        screenSize.height - position.dy,
      ),
      items: const [
        PopupMenuItem(
          value: 'rename',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.edit_outlined),
            title: Text('Cambiar nombre'),
          ),
        ),
        PopupMenuItem(
          value: 'editDays',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.edit_calendar_outlined),
            title: Text('Cambiar duración'),
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.delete_outline),
            title: Text('Eliminar'),
          ),
        ),
      ],
    );

    if (action == null || !context.mounted) return;

    try {
      switch (action) {
        case 'rename':
          await showDialog<void>(
            context: context,
            builder: (_) => _RenameProductDialog(
              product: product,
              onSave: (name) =>
                  repository.updateProduct(product.id, name: name),
            ),
          );
          break;
        case 'editDays':
          await showDialog<void>(
            context: context,
            builder: (_) => _EditDaysDialog(
              product: product,
              onSave: (days) =>
                  repository.updateProduct(product.id, lastsDays: days),
            ),
          );
          break;
        case 'delete':
          await repository.deleteProduct(product.id);
          break;
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo actualizar: $error')),
        );
      }
    }
  }

  Widget _placeholder(ThemeData theme) => Icon(
        product.needsBuying ? Icons.shopping_basket_outlined : Icons.kitchen,
        color: product.needsBuying
            ? theme.colorScheme.onSurfaceVariant
            : theme.colorScheme.primary,
        size: 40,
      );
}

class _RenameProductDialog extends StatefulWidget {
  const _RenameProductDialog({
    required this.product,
    required this.onSave,
  });

  final Product product;
  final Future<void> Function(String name) onSave;

  @override
  State<_RenameProductDialog> createState() => _RenameProductDialogState();
}

class _RenameProductDialogState extends State<_RenameProductDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.product.name);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(_nameController.text.trim());
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo cambiar el nombre: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Cambiar nombre'),
        content: Form(
          key: _formKey,
          child: TextFormField(
            controller: _nameController,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Nombre'),
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Escribí un nombre'
                : null,
            onFieldSubmitted: (_) => _save(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Guardando…' : 'Guardar'),
          ),
        ],
      );
}

class _EditDaysDialog extends StatefulWidget {
  const _EditDaysDialog({
    required this.product,
    required this.onSave,
  });

  final Product product;
  final Future<void> Function(int days) onSave;

  @override
  State<_EditDaysDialog> createState() => _EditDaysDialogState();
}

class _EditDaysDialogState extends State<_EditDaysDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _daysController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _daysController =
        TextEditingController(text: widget.product.lastsDays.toString());
  }

  @override
  void dispose() {
    _daysController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final days = int.parse(_daysController.text.trim());
    setState(() => _saving = true);

    try {
      await widget.onSave(days);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No se pudo cambiar la duración: $error')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Cambiar duración'),
        content: Form(
          key: _formKey,
          child: TextFormField(
            controller: _daysController,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Días'),
            validator: (value) {
              final days = int.tryParse(value?.trim() ?? '');
              return days == null || days < 1 ? 'Ingresá al menos 1 día' : null;
            },
            onFieldSubmitted: (_) => _save(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Guardando…' : 'Guardar'),
          ),
        ],
      );
}
