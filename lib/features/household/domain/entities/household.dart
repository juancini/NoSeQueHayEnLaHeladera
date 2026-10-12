class Household {
  const Household({required this.id, required this.name});

  final String id;
  final String name;

  factory Household.fromMap(Map<String, Object?> row) =>
      Household(id: row['id']! as String, name: row['name']! as String);
}
