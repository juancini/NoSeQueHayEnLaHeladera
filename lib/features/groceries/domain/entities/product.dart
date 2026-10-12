class Product {
  const Product({
    required this.id,
    required this.name,
    required this.lastsDays,
    required this.updatedAt,
    required this.sequence,
    required this.lastWriterMemberId,
    this.lastBoughtAt,
    this.lastEmptiedAt,
    this.deletedAt,
  });

  final String id;
  final String name;
  final int lastsDays;
  final int? lastBoughtAt;
  final int? lastEmptiedAt;
  final int updatedAt;
  final int? deletedAt;
  final int sequence;
  final String lastWriterMemberId;

  bool get needsBuying {
    final boughtAt = lastBoughtAt;
    return boughtAt == null ||
        (lastEmptiedAt != null && lastEmptiedAt! > boughtAt) ||
        DateTime.now().toUtc().millisecondsSinceEpoch >=
            boughtAt + lastsDays * Duration.millisecondsPerDay;
  }

  factory Product.fromMap(Map<String, Object?> row) => Product(
        id: row['id']! as String,
        name: row['name']! as String,
        lastsDays: row['lasts_days']! as int,
        lastBoughtAt: row['last_bought_at'] as int?,
        lastEmptiedAt: row['last_emptied_at'] as int?,
        updatedAt: row['updated_at']! as int,
        deletedAt: row['deleted_at'] as int?,
        sequence: row['seq']! as int,
        lastWriterMemberId:
            row['last_writer_member_id'] as String? ?? '',
      );
}
