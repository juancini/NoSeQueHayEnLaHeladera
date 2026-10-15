import 'dart:async';

import 'package:uuid/uuid.dart';

import '../../../../core/database/app_database.dart';
import '../../domain/entities/product.dart';
import '../../domain/repositories/grocery_repository.dart';

class SqliteGroceryRepository implements GroceryRepository {
  SqliteGroceryRepository(this._appDatabase);

  final AppDatabase _appDatabase;
  static const _uuid = Uuid();

  @override
  Stream<List<Product>> watchProducts() {
    late StreamController<List<Product>> controller;
    StreamSubscription<void>? changesSubscription;
    Timer? refreshTimer;

    Future<void> refresh() async {
      try {
        controller.add(await _loadProducts());
      } catch (error, stackTrace) {
        controller.addError(error, stackTrace);
      }
    }

    controller = StreamController<List<Product>>(
      onListen: () {
        refresh();
        changesSubscription = _appDatabase.changes.listen((_) => refresh());
        refreshTimer =
            Timer.periodic(const Duration(minutes: 1), (_) => refresh());
      },
      onCancel: () async {
        refreshTimer?.cancel();
        await changesSubscription?.cancel();
      },
    );
    return controller.stream;
  }

  @override
  Stream<List<Product>> watchShoppingList() => watchProducts()
      .map((products) => products.where((p) => p.needsBuying).toList());

  Future<List<Product>> _loadProducts() async {
    final rows = await _appDatabase.database.query(
      'product',
      where: 'deleted_at IS NULL',
      orderBy: 'name COLLATE NOCASE ASC',
    );
    final products = rows.map(Product.fromMap).toList();
    products.sort((a, b) {
      if (a.needsBuying != b.needsBuying) return a.needsBuying ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return products;
  }

  @override
  Future<Product> addProduct(String name, int lastsDays) async {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      throw ArgumentError('El nombre no puede estar vacío');
    }
    if (lastsDays < 1) {
      throw ArgumentError.value(
        lastsDays,
        'lastsDays',
        'La duración de un producto debe ser al menos un (1) día.',
      );
    }
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final memberId = await _appDatabase.readLocalState('member_id') ?? '';
    late Product product;
    await _appDatabase.database.transaction((transaction) async {
      final householdRows = await transaction.query('household', limit: 1);
      if (householdRows.isEmpty) {
        throw StateError(
          'Primero tenés que crear o unirte a un hogar para agregar productos',
        );
      }
      final householdId = householdRows.first['id'] as String;
      final sequence = await _appDatabase.nextSequence(transaction);
      final row = <String, Object?>{
        'id': _uuid.v4(),
        'household_id': householdId,
        'name': normalizedName,
        'lasts_days': lastsDays,
        'last_bought_at': null,
        'last_emptied_at': null,
        'updated_at': now,
        'deleted_at': null,
        'seq': sequence,
        'last_writer_member_id': memberId,
      };
      await transaction.insert('product', row);
      product = Product.fromMap(row);
    });
    _appDatabase.notifyChanged();
    return product;
  }

  @override
  Future<void> updateProduct(
    String id, {
    String? name,
    int? lastsDays,
  }) async {
    if (name != null && name.trim().isEmpty) {
      throw ArgumentError('El nombre no puede estar vacío');
    }
    if (lastsDays != null && lastsDays < 1) {
      throw ArgumentError.value(lastsDays, 'lastsDays');
    }
    final changes = <String, Object?>{};
    if (name != null) changes['name'] = name.trim();
    if (lastsDays != null) changes['lasts_days'] = lastsDays;
    if (changes.isEmpty) return;
    await _writeProduct(id, changes, updateMetadata: true);
  }

  @override
  Future<void> markBought(String id) async {
    await _writeProduct(id, {
      'last_bought_at': DateTime.now().toUtc().millisecondsSinceEpoch,
    });
  }

  @override
  Future<void> markEmpty(String id) async {
    await _writeProduct(id, {
      'last_emptied_at': DateTime.now().toUtc().millisecondsSinceEpoch,
    });
  }

  @override
  Future<void> deleteProduct(String id) async {
    await _writeProduct(
      id,
      {'deleted_at': DateTime.now().toUtc().millisecondsSinceEpoch},
      updateMetadata: true,
    );
  }

  Future<void> _writeProduct(
    String id,
    Map<String, Object?> values, {
    bool updateMetadata = false,
  }) async {
    final memberId = await _appDatabase.readLocalState('member_id') ?? '';
    await _appDatabase.database.transaction((transaction) async {
      final sequence = await _appDatabase.nextSequence(transaction);
      final fields = <String, Object?>{
        ...values,
        'seq': sequence,
      };
      if (updateMetadata) {
        fields['updated_at'] = DateTime.now().toUtc().millisecondsSinceEpoch;
        fields['last_writer_member_id'] = memberId;
      }
      final count = await transaction.update(
        'product',
        fields,
        where: 'id = ? AND deleted_at IS NULL',
        whereArgs: [id],
      );
      if (count == 0) throw StateError('No existe el producto solicitado');
    });
    _appDatabase.notifyChanged();
  }
}
