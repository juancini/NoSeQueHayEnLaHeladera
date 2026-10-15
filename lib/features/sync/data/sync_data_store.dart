import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';
import '../domain/sync_merge_engine.dart';

class SyncDataStore {
  SyncDataStore(this._appDatabase);

  final AppDatabase _appDatabase;

  Future<String?> get householdId async {
    final rows = await _appDatabase.database.query('household', limit: 1);
    return rows.isEmpty ? null : rows.first['id'] as String?;
  }

  Future<Map<String, Object?>> requestFor(
    String peerAddress, {
    String? peerId,
  }) async {
    return _appDatabase.database.transaction((transaction) async {
      final peerRows = await transaction.query(
        'peer',
        where: peerId == null ? 'address = ?' : 'member_id = ?',
        whereArgs: [peerId ?? peerAddress],
        limit: 1,
      );
      final peer =
          peerRows.isEmpty ? const <String, Object?>{} : peerRows.first;
      final pullCursor = peer['pull_cursor'] as int? ?? 0;
      final pushCursor = peer['push_cursor'] as int? ?? 0;
      final changes = await _changesAfter(pushCursor, executor: transaction);
      return {
        'since': pullCursor,
        'cursor': await _currentSequence(transaction),
        'changes': changes,
      };
    });
  }

  Future<Map<String, Object?>> exchange(
    String senderId,
    Map<String, Object?> request,
  ) async {
    final since = _nonNegativeInt(request['since'], 'since');
    final senderCursor = _nonNegativeInt(request['cursor'], 'cursor');
    final changes = _readChangeList(request['changes']);
    late List<Map<String, Object?>> outgoing;
    late int cursor;
    await _appDatabase.database.transaction((transaction) async {
      final currentSequence = await _currentSequence(transaction);
      if (since > currentSequence) {
        throw const FormatException('since cursor is ahead of this device');
      }
      await _applyChanges(transaction, changes);
      outgoing = await _changesAfter(since, executor: transaction);
      final peerRows = await transaction.query(
        'peer',
        where: 'member_id = ?',
        whereArgs: [senderId],
        limit: 1,
      );
      final oldPeer =
          peerRows.isEmpty ? const <String, Object?>{} : peerRows.first;
      await transaction.insert(
        'peer',
        {
          'member_id': senderId,
          'pull_cursor':
              _maxInt(oldPeer['pull_cursor'] as int? ?? 0, senderCursor),
          'push_cursor': _maxInt(oldPeer['push_cursor'] as int? ?? 0, since),
          'address': oldPeer['address'],
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await _recordSuccessfulSync(transaction);
      cursor = await _currentSequence(transaction);
    });
    _appDatabase.notifyChanged(local: false);
    return {'changes': outgoing, 'cursor': cursor};
  }

  Future<void> applyResponse({
    required String peerId,
    required String peerAddress,
    required Map<String, Object?> response,
    required int sentThrough,
  }) async {
    final cursor = _nonNegativeInt(response['cursor'], 'cursor');
    final changes = _readChangeList(response['changes']);
    await _appDatabase.database.transaction((transaction) async {
      await _applyChanges(transaction, changes);
      final rows = await transaction.query(
        'peer',
        where: 'member_id = ?',
        whereArgs: [peerId],
        limit: 1,
      );
      final oldPeer = rows.isEmpty ? const <String, Object?>{} : rows.first;
      await transaction.insert(
        'peer',
        {
          'member_id': peerId,
          'pull_cursor': _maxInt(
            oldPeer['pull_cursor'] as int? ?? 0,
            cursor,
          ),
          'push_cursor': _maxInt(
            oldPeer['push_cursor'] as int? ?? 0,
            sentThrough,
          ),
          'address': peerAddress,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await _recordSuccessfulSync(transaction);
    });
    _appDatabase.notifyChanged(local: false);
  }

  Future<void> _recordSuccessfulSync(Transaction transaction) async {
    final rows = await transaction.query(
      'local_state',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['last_sync_at'],
      limit: 1,
    );
    final previous = rows.isEmpty
        ? 0
        : int.tryParse(rows.first['value'] as String? ?? '') ?? 0;
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await transaction.insert(
      'local_state',
      {
        'key': 'last_sync_at',
        'value': '${now > previous ? now : previous}',
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, Object?>>> _changesAfter(
    int sequence, {
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? _appDatabase.database;
    final households = await db.query('household', limit: 1);
    if (households.isEmpty) return [];
    final householdId = households.first['id'] as String;
    final products = await db.query(
      'product',
      where: 'household_id = ? AND seq > ?',
      whereArgs: [householdId, sequence],
      orderBy: 'seq ASC',
    );
    final members = await db.query(
      'member',
      where: 'household_id = ? AND seq > ?',
      whereArgs: [householdId, sequence],
      orderBy: 'seq ASC',
    );
    final changes = <(int, Map<String, Object?>)>[
      for (final row in products)
        (row['seq'] as int, {'table': 'product', 'row': _withoutSequence(row)}),
      for (final row in members)
        (row['seq'] as int, {'table': 'member', 'row': _withoutSequence(row)}),
    ];
    changes.sort((a, b) => a.$1.compareTo(b.$1));
    return changes.map((entry) => entry.$2).toList();
  }

  Map<String, Object?> _withoutSequence(Map<String, Object?> row) {
    final copy = Map<String, Object?>.from(row)..remove('seq');
    return copy;
  }

  List<Map<String, Object?>> _readChangeList(Object? value) {
    if (value is! List) throw const FormatException('changes must be a list');
    return value.map((change) {
      if (change is! Map ||
          change['table'] is! String ||
          change['row'] is! Map) {
        throw const FormatException('Invalid change record');
      }
      return {
        'table': change['table'] as String,
        'row': Map<String, Object?>.from(change['row'] as Map),
      };
    }).toList();
  }

  Future<void> _applyChanges(
    Transaction transaction,
    List<Map<String, Object?>> changes,
  ) async {
    final currentHouseholdId = await _householdId(transaction);
    if (currentHouseholdId == null) {
      throw StateError('No hay un hogar configurado para sincronizar');
    }
    for (final change in changes) {
      final table = change['table'] as String;
      final incoming = change['row']! as Map<String, Object?>;
      if (table == 'product') {
        await _applyProduct(transaction, currentHouseholdId, incoming);
      } else if (table == 'member') {
        await _applyMember(transaction, currentHouseholdId, incoming);
      } else {
        throw const FormatException('Unsupported sync table');
      }
    }
  }

  Future<void> _applyProduct(
    Transaction transaction,
    String householdId,
    Map<String, Object?> source,
  ) async {
    final incoming = _validatedProduct(source, householdId);
    final rows = await transaction.query(
      'product',
      where: 'id = ?',
      whereArgs: [incoming['id']],
      limit: 1,
    );
    final existing = rows.isEmpty ? null : rows.first;
    if (existing != null &&
        existing['household_id'] != null &&
        existing['household_id'] != householdId) {
      throw const FormatException('Product belongs to another household');
    }
    final merged = existing == null
        ? incoming
        : SyncMergeEngine.mergeProduct(local: existing, incoming: incoming);
    if (existing != null && _sameProduct(existing, merged)) return;
    final sequence = await _appDatabase.nextSequence(transaction);
    await transaction.insert(
      'product',
      {...merged, 'seq': sequence},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Map<String, Object?> _validatedProduct(
    Map<String, Object?> row,
    String householdId,
  ) {
    if (row['id'] is! String ||
        row['household_id'] != householdId ||
        row['name'] is! String ||
        (row['name'] as String).trim().isEmpty ||
        row['lasts_days'] is! int ||
        (row['lasts_days'] as int) < 1 ||
        row['updated_at'] is! int ||
        row['last_writer_member_id'] is! String ||
        !_isNullableInt(row['last_bought_at']) ||
        !_isNullableInt(row['last_emptied_at']) ||
        !_isNullableInt(row['deleted_at'])) {
      throw const FormatException('Invalid product row');
    }
    return {
      'id': row['id'],
      'household_id': householdId,
      'name': (row['name'] as String).trim(),
      'lasts_days': row['lasts_days'],
      'last_bought_at': row['last_bought_at'],
      'last_emptied_at': row['last_emptied_at'],
      'updated_at': row['updated_at'],
      'deleted_at': row['deleted_at'],
      'last_writer_member_id': row['last_writer_member_id'],
    };
  }

  bool _sameProduct(Map<String, Object?> local, Map<String, Object?> merged) {
    const fields = [
      'id',
      'household_id',
      'name',
      'lasts_days',
      'last_bought_at',
      'last_emptied_at',
      'updated_at',
      'deleted_at',
      'last_writer_member_id',
    ];
    return fields.every((field) => local[field] == merged[field]);
  }

  Future<void> _applyMember(
    Transaction transaction,
    String householdId,
    Map<String, Object?> row,
  ) async {
    if (row['id'] is! String ||
        row['household_id'] != householdId ||
        row['name'] is! String ||
        row['updated_at'] is! int ||
        !_isNullableInt(row['deleted_at'])) {
      throw const FormatException('Invalid member row');
    }
    final memberId = row['id'] as String;
    final incomingName = (row['name'] as String).trim();
    if (incomingName.isEmpty)
      throw const FormatException('Invalid member name');
    final rows = await transaction.query(
      'member',
      where: 'id = ?',
      whereArgs: [memberId],
      limit: 1,
    );
    final existing = rows.isEmpty ? null : rows.first;
    if (existing != null && existing['household_id'] != householdId) {
      throw const FormatException('Member belongs to another household');
    }
    final wins = existing == null ||
        (row['updated_at'] as int) > (existing['updated_at'] as int) ||
        ((row['updated_at'] as int) == (existing['updated_at'] as int) &&
            (incomingName.compareTo(existing['name'] as String) > 0 ||
                (incomingName == existing['name'] &&
                    _deletedAtOrder(row['deleted_at'] as int?) >
                        _deletedAtOrder(existing['deleted_at'] as int?))));
    if (!wins) return;
    if (existing != null &&
        existing['name'] == incomingName &&
        existing['updated_at'] == row['updated_at'] &&
        existing['deleted_at'] == row['deleted_at']) {
      return;
    }
    final sequence = await _appDatabase.nextSequence(transaction);
    await transaction.insert(
      'member',
      {
        'id': memberId,
        'household_id': householdId,
        'name': incomingName,
        'updated_at': row['updated_at'],
        'deleted_at': row['deleted_at'],
        'seq': sequence,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> _householdId(Transaction transaction) async {
    final rows = await transaction.query('household', limit: 1);
    return rows.isEmpty ? null : rows.first['id'] as String?;
  }

  Future<int> _currentSequence(Transaction transaction) async {
    final rows = await transaction.query(
      'local_state',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['seq_counter'],
      limit: 1,
    );
    return rows.isEmpty ? 0 : int.tryParse(rows.first['value'] as String) ?? 0;
  }

  int _nonNegativeInt(Object? value, String field) {
    if (value is! int || value < 0) {
      throw FormatException('$field must be a non-negative integer');
    }
    return value;
  }

  bool _isNullableInt(Object? value) => value == null || value is int;

  int _deletedAtOrder(int? timestamp) => timestamp ?? -1;

  int _maxInt(int first, int second) => first >= second ? first : second;
}
