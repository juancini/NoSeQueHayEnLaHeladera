import 'dart:convert';
import 'dart:math';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_database.dart';
import '../../domain/entities/household.dart';
import '../../domain/entities/household_invite.dart';
import '../../domain/entities/member.dart';
import '../../domain/repositories/household_repository.dart';

class SqliteHouseholdRepository implements HouseholdRepository {
  SqliteHouseholdRepository(this._appDatabase);

  final AppDatabase _appDatabase;
  static const _uuid = Uuid();

  @override
  Future<Household> createHousehold(String name, String myName) async {
    final householdName = name.trim();
    final memberName = myName.trim();
    if (householdName.isEmpty || memberName.isEmpty) {
      throw ArgumentError('El nombre del hogar y el nombre de la persona son obligatorios');
    }
    final household = Household(id: _uuid.v4(), name: householdName);
    final memberId = _uuid.v4();
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final secret = List<int>.generate(32, (_) => Random.secure().nextInt(256));
    await _appDatabase.database.transaction((transaction) async {
      await transaction.delete('member');
      await transaction.delete('household');
      await transaction.insert('household', {'id': household.id, 'name': household.name});
      final localProducts = await transaction.query(
        'product',
        columns: ['id'],
        where: 'household_id IS NULL',
      );
      for (final product in localProducts) {
        final productSequence = await _appDatabase.nextSequence(transaction);
        await transaction.update(
          'product',
          {'household_id': household.id, 'seq': productSequence},
          where: 'id = ?',
          whereArgs: [product['id']],
        );
      }
      final sequence = await _appDatabase.nextSequence(transaction);
      await transaction.insert('member', {
        'id': memberId,
        'household_id': household.id,
        'name': memberName,
        'updated_at': now,
        'deleted_at': null,
        'seq': sequence,
      });
      await transaction.insert(
        'local_state',
        {'key': 'household_secret', 'value': base64UrlEncode(secret)},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await transaction.insert(
        'local_state',
        {'key': 'member_id', 'value': memberId},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
    _appDatabase.notifyChanged();
    return household;
  }

  @override
  Future<Household?> current() async {
    final rows = await _appDatabase.database.query('household', limit: 1);
    return rows.isEmpty ? null : Household.fromMap(rows.first);
  }

  @override
  Future<String> inviteQrPayload() async {
    final household = await current();
    final secret = await _appDatabase.readLocalState('household_secret');
    if (household == null || secret == null) {
      throw StateError('Primero tenés que crear un hogar');
    }
    return HouseholdInvite(
      householdId: household.id,
      householdName: household.name,
      secret: secret,
    ).toPayload();
  }

  @override
  Future<void> joinFromQr(String payload, String myName) async {
    final memberName = myName.trim();
    if (memberName.isEmpty) throw ArgumentError('El nombre no puede estar vacío');
    final invite = HouseholdInvite.fromPayload(payload);
    final household = Household(
      id: invite.householdId,
      name: invite.householdName,
    );
    final memberId = _uuid.v4();
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await _appDatabase.database.transaction((transaction) async {
      await transaction.delete('member');
      await transaction.delete('household');
      await transaction.insert('household', {'id': household.id, 'name': household.name});
      final localProducts = await transaction.query(
        'product',
        columns: ['id'],
        where: 'household_id IS NULL',
      );
      final sequence = await _appDatabase.nextSequence(transaction);
      await transaction.insert('member', {
        'id': memberId,
        'household_id': household.id,
        'name': memberName,
        'updated_at': now,
        'deleted_at': null,
        'seq': sequence,
      });
      for (final entry in [
        MapEntry('household_secret', invite.secret),
        MapEntry('member_id', memberId),
      ]) {
        await transaction.insert(
          'local_state',
          {'key': entry.key, 'value': entry.value},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      for (final product in localProducts) {
        final productSequence = await _appDatabase.nextSequence(transaction);
        await transaction.update(
          'product',
          {'household_id': household.id, 'seq': productSequence},
          where: 'id = ?',
          whereArgs: [product['id']],
        );
      }
    });
    _appDatabase.notifyChanged();
  }

  @override
  Stream<List<Member>> watchMembers() async* {
    yield await _loadMembers();
    await for (final _ in _appDatabase.changes) {
      yield await _loadMembers();
    }
  }

  Future<List<Member>> _loadMembers() async {
    final rows = await _appDatabase.database.query(
      'member',
      where: 'deleted_at IS NULL',
      orderBy: 'name COLLATE NOCASE ASC',
    );
    return rows.map(Member.fromMap).toList();
  }
}
