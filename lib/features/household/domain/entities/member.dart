class Member {
  const Member({
    required this.id,
    required this.householdId,
    required this.name,
    required this.updatedAt,
    required this.sequence,
    this.deletedAt,
  });

  final String id;
  final String householdId;
  final String name;
  final int updatedAt;
  final int sequence;
  final int? deletedAt;

  factory Member.fromMap(Map<String, Object?> row) => Member(
        id: row['id']! as String,
        householdId: row['household_id']! as String,
        name: row['name']! as String,
        updatedAt: row['updated_at']! as int,
        deletedAt: row['deleted_at'] as int?,
        sequence: row['seq']! as int,
      );
}
