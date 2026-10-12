import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../data/repositories/sqlite_grocery_repository.dart';
import '../../domain/entities/product.dart';
import '../../domain/repositories/grocery_repository.dart';

final groceryRepositoryProvider = Provider<GroceryRepository>(
  (ref) => SqliteGroceryRepository(ref.watch(appDatabaseProvider)),
);

final productsProvider = StreamProvider<List<Product>>(
  (ref) => ref.watch(groceryRepositoryProvider).watchProducts(),
);
