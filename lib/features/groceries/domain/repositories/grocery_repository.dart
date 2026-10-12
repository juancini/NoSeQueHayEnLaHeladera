import '../entities/product.dart';

abstract interface class GroceryRepository {
  Stream<List<Product>> watchProducts();
  Stream<List<Product>> watchShoppingList();
  Future<Product> addProduct(String name, int lastsDays);
  Future<void> updateProduct(String id, {String? name, int? lastsDays});
  Future<void> markBought(String id);
  Future<void> markEmpty(String id);
  Future<void> deleteProduct(String id);
}
