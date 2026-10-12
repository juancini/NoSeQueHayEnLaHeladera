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
                product.needsBuying ? Icons.shopping_basket_outlined : Icons.kitchen,
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
                    product.needsBuying ? 'Falta · dura ${product.lastsDays} días' :
                        'Hay · dura ${product.lastsDays} días',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: product.needsBuying ? 'Marcar como comprado' : 'Marcar como terminado',
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
                  if (action == 'delete') await repository.deleteProduct(product.id);
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
