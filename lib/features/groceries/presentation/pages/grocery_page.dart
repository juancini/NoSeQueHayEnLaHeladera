import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../household/presentation/pages/household_page.dart';
import '../../../household/presentation/providers/household_providers.dart';
import '../providers/grocery_providers.dart';
import '../widgets/add_product_sheet.dart';
import '../widgets/product_tile.dart';

class GroceryPage extends ConsumerStatefulWidget {
  const GroceryPage({super.key});

  @override
  ConsumerState<GroceryPage> createState() => _GroceryPageState();
}

class _GroceryPageState extends ConsumerState<GroceryPage> {
  bool _shoppingOnly = false;

  Future<void> _addProduct() async {
    try {
      final household = await ref.read(currentHouseholdProvider.future);
      if (!mounted) return;
      if (household == null) {
        await Navigator.of(context).push<void>(
          MaterialPageRoute<void>(builder: (_) => const HouseholdPage()),
        );
        return;
      }
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => const AddProductSheet(),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo comprobar el hogar: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final products = ref.watch(productsProvider);
    final household = ref.watch(currentHouseholdProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('No se que hay en la heladerApp'),
        actions: [
          IconButton(
            tooltip: 'Hogar y personas',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const HouseholdPage()),
            ),
            icon: const Icon(Icons.home_outlined),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          household.when(
            data: (value) => value == null
                ? const _HouseholdHint()
                : Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: Text(
                      value.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                    value: false,
                    label: Text('Todo'),
                    icon: Icon(Icons.kitchen)),
                ButtonSegment(
                  value: true,
                  label: Text('Para comprar'),
                  icon: Icon(Icons.shopping_basket_outlined),
                ),
              ],
              selected: {_shoppingOnly},
              onSelectionChanged: (selection) =>
                  setState(() => _shoppingOnly = selection.single),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: products.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) =>
                  Center(child: Text('No se pudo cargar la lista: $error')),
              data: (allProducts) {
                final visible = _shoppingOnly
                    ? allProducts
                        .where((product) => product.needsBuying)
                        .toList()
                    : allProducts;
                if (visible.isEmpty) {
                  return _EmptyState(shoppingOnly: _shoppingOnly);
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                  itemCount: visible.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) =>
                      ProductTile(product: visible[index]),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addProduct,
        icon: const Icon(Icons.add),
        label: const Text('Agregar'),
      ),
    );
  }
}

class _HouseholdHint extends StatelessWidget {
  const _HouseholdHint();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Text(
          'Creá o unite a un hogar para agregar productos.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.shoppingOnly});

  final bool shoppingOnly;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                shoppingOnly
                    ? Icons.check_circle_outline
                    : Icons.kitchen_outlined,
                size: 56,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                shoppingOnly
                    ? 'No falta nada por comprar'
                    : 'Todavía no agregaste productos',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                  'Agregá lo que usás en casa y te ayudamos a recordarlo.'),
            ],
          ),
        ),
      );
}
