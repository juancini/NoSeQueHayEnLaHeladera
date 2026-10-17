import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/product.dart';
import '../providers/grocery_providers.dart';

class ProductTile extends ConsumerWidget {
  const ProductTile({required this.product, super.key});

  final Product product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repository = ref.read(groceryRepositoryProvider);
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: product.needsBuying
                  ? theme.colorScheme.tertiaryContainer
                  : theme.colorScheme.primaryContainer,
              child: Icon(
                product.needsBuying
                    ? Icons.shopping_basket_outlined
                    : Icons.kitchen,
                color: product.needsBuying
                    ? theme.colorScheme.onTertiaryContainer
                    : theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product.name, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    product.needsBuying
                        ? 'Falta · dura ${product.lastsDays} días'
                        : 'Hay · dura ${product.lastsDays} días',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: product.needsBuying
                  ? 'Marcar como comprado'
                  : 'Marcar como terminado',
              onPressed: () async {
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
              },
              icon: Icon(
                product.needsBuying
                    ? Icons.check_circle_outline
                    : Icons.remove_shopping_cart_outlined,
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Acciones',
              onSelected: (action) async {
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
                          onSave: (days) => repository.updateProduct(product.id,
                              lastsDays: days),
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
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'rename',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.edit_outlined),
                    title: Text('Cambiar nombre'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'editDays',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.edit_calendar_outlined),
                    title: Text('Cambiar duración'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.delete_outline),
                    title: Text('Eliminar'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
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
