class SyncImageNegotiation {
  const SyncImageNegotiation._();

  static List<String> missingHashes({
    required Iterable<String> referenced,
    required Iterable<String> available,
  }) {
    final availableSet = available.toSet();
    return referenced.where((hash) => !availableSet.contains(hash)).toSet().toList()
      ..sort();
  }
}
