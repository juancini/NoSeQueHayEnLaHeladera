import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

final appDatabaseProvider = Provider<AppDatabase>(
  (ref) => throw StateError('AppDatabase must be overridden in main'),
);

class AppDatabase {
  AppDatabase(this.database);

  final Database database;
  final _changes = StreamController<void>.broadcast();
  final _localChanges = StreamController<void>.broadcast();

  static Future<AppDatabase> open({String? databasePath}) async {
    final dbPath = databasePath ??
        path.join(await getDatabasesPath(), 'heladera.sqlite');
    final database = await openDatabase(
      dbPath,
      version: 2,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE household (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE member (
            id TEXT PRIMARY KEY,
            household_id TEXT NOT NULL REFERENCES household(id),
            name TEXT NOT NULL,
            updated_at INTEGER NOT NULL,
            deleted_at INTEGER,
            seq INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE product (
            id TEXT PRIMARY KEY,
            household_id TEXT,
            name TEXT NOT NULL,
            lasts_days INTEGER NOT NULL,
            last_bought_at INTEGER,
            last_emptied_at INTEGER,
            updated_at INTEGER NOT NULL,
            deleted_at INTEGER,
            seq INTEGER NOT NULL,
            last_writer_member_id TEXT NOT NULL DEFAULT '',
            image_src TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE peer (
            member_id TEXT PRIMARY KEY,
            pull_cursor INTEGER NOT NULL DEFAULT 0,
            push_cursor INTEGER NOT NULL DEFAULT 0,
            address TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE local_state (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');
        await db.execute(
          "INSERT INTO local_state(key, value) VALUES('seq_counter', '0')",
        );
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE product ADD COLUMN image_src TEXT');
        }
      },
    );
    return AppDatabase(database);
  }

  Stream<void> get changes => _changes.stream;

  Stream<void> get localChanges => _localChanges.stream;

  void notifyChanged({bool local = true}) {
    _changes.add(null);
    if (local) _localChanges.add(null);
  }

  Future<int> nextSequence(Transaction transaction) async {
    final rows = await transaction.query(
      'local_state',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['seq_counter'],
      limit: 1,
    );
    final current = rows.isEmpty ? null : rows.first['value'] as String?;
    final next = (int.tryParse(current ?? '') ?? 0) + 1;
    await transaction.insert(
      'local_state',
      {'key': 'seq_counter', 'value': '$next'},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return next;
  }

  Future<String?> readLocalState(String key) async {
    final rows = await database.query(
      'local_state',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> writeLocalState(String key, String value) async {
    await database.insert(
      'local_state',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> close() async {
    await _changes.close();
    await _localChanges.close();
    await database.close();
  }
}
