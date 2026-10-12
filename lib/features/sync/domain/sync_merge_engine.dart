class SyncMergeEngine {
  const SyncMergeEngine._();

  static Map<String, Object?> mergeProduct({
    required Map<String, Object?> local,
    required Map<String, Object?> incoming,
  }) {
    final winner = _metadataWins(local, incoming) ? local : incoming;
    return {
      'id': local['id'],
      'household_id': local['household_id'] ?? incoming['household_id'],
      'name': winner['name'],
      'lasts_days': winner['lasts_days'],
      'last_bought_at': _maxTimestamp(
        local['last_bought_at'] as int?,
        incoming['last_bought_at'] as int?,
      ),
      'last_emptied_at': _maxTimestamp(
        local['last_emptied_at'] as int?,
        incoming['last_emptied_at'] as int?,
      ),
      'updated_at': winner['updated_at'],
      'deleted_at': winner['deleted_at'],
      'last_writer_member_id': winner['last_writer_member_id'],
    };
  }

  static bool _metadataWins(
    Map<String, Object?> local,
    Map<String, Object?> incoming,
  ) {
    final localUpdatedAt = local['updated_at'] as int;
    final incomingUpdatedAt = incoming['updated_at'] as int;
    if (localUpdatedAt != incomingUpdatedAt) {
      return localUpdatedAt > incomingUpdatedAt;
    }
    final localWriter = local['last_writer_member_id'] as String? ?? '';
    final incomingWriter = incoming['last_writer_member_id'] as String? ?? '';
    return localWriter.compareTo(incomingWriter) >= 0;
  }

  static int? _maxTimestamp(int? first, int? second) {
    if (first == null) return second;
    if (second == null) return first;
    return first >= second ? first : second;
  }
}
