import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_se_que_hay_en_la_heladera/core/database/app_database.dart';
import 'package:no_se_que_hay_en_la_heladera/features/groceries/data/drawing_image_storage.dart';
import 'package:no_se_que_hay_en_la_heladera/features/groceries/data/repositories/sqlite_grocery_repository.dart';
import 'package:no_se_que_hay_en_la_heladera/features/sync/data/sync_data_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory temporaryDirectory;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    temporaryDirectory =
        await Directory.systemTemp.createTemp('heladera-database-');
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('migrates schema version 1 product table to include image_src',
      () async {
    final databasePath = '${temporaryDirectory.path}/legacy.sqlite';
    final oldDatabase = await databaseFactory.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE product ('
            'id TEXT PRIMARY KEY, household_id TEXT, name TEXT NOT NULL, '
            'lasts_days INTEGER NOT NULL, last_bought_at INTEGER, '
            'last_emptied_at INTEGER, updated_at INTEGER NOT NULL, '
            'deleted_at INTEGER, seq INTEGER NOT NULL, '
            "last_writer_member_id TEXT NOT NULL DEFAULT '')",
          );
          await db.insert('product', {
            'id': 'legacy',
            'name': 'Leche',
            'lasts_days': 5,
            'updated_at': 100,
            'seq': 1,
          });
        },
      ),
    );
    await oldDatabase.close();

    final appDatabase = await AppDatabase.open(databasePath: databasePath);
    addTearDown(appDatabase.close);
    final columns =
        await appDatabase.database.rawQuery('PRAGMA table_info(product)');
    expect(columns.map((column) => column['name']), contains('image_src'));
    final row = (await appDatabase.database.query('product')).single;
    expect(row['name'], 'Leche');
    expect(row['image_src'], isNull);
  });

  test('local soft-deletion keeps shared image until last active reference',
      () async {
    final storage = _storage(temporaryDirectory);
    final imageSrc = await storage.savePng(Uint8List.fromList([1, 2, 3]));
    final database = await AppDatabase.open(
      databasePath: '${temporaryDirectory.path}/shared.sqlite',
    );
    addTearDown(database.close);
    await database.database.insert('household', {'id': 'home', 'name': 'Casa'});
    await _insertProduct(database, 'one', imageSrc);
    await _insertProduct(database, 'two', imageSrc);
    final repository = SqliteGroceryRepository(database, imageStorage: storage);

    await repository.deleteProduct('one');
    expect(await storage.resolve(imageSrc), isNotNull);
    expect(
      (await database.database.query(
        'product',
        where: 'id = ?',
        whereArgs: ['one'],
      ))
          .single['deleted_at'],
      isNotNull,
    );

    await repository.deleteProduct('two');
    expect(await storage.resolve(imageSrc), isNull);
    expect(await database.database.query('product'), hasLength(2));
  });

  test('sync tombstone preserves the row and cleans its unshared drawing',
      () async {
    final storage = _storage(temporaryDirectory);
    final imageSrc = await storage.savePng(Uint8List.fromList([8, 7, 6]));
    final database = await AppDatabase.open(
      databasePath: '${temporaryDirectory.path}/sync.sqlite',
    );
    addTearDown(database.close);
    await database.database.insert('household', {'id': 'home', 'name': 'Casa'});
    await database.writeLocalState('seq_counter', '1');
    await _insertProduct(database, 'milk', imageSrc);
    final store = SyncDataStore(database, imageStorage: storage);

    await store.applyResponse(
      peerId: 'remote-device',
      peerAddress: '192.168.1.3',
      sentThrough: 0,
      response: {
        'cursor': 2,
        'changes': [
          {
            'table': 'product',
            'row': {
              'id': 'milk',
              'household_id': 'home',
              'name': 'Leche',
              'lasts_days': 5,
              'last_bought_at': null,
              'last_emptied_at': null,
              'updated_at': 2,
              'deleted_at': 2,
              'last_writer_member_id': 'remote',
              'image_src': imageSrc,
            },
          },
        ],
      },
    );

    expect(await storage.resolve(imageSrc), isNull);
    final tombstone = (await database.database.query('product')).single;
    expect(tombstone['deleted_at'], 2);
    expect(tombstone['image_src'], imageSrc);
  });

  test('manifest snapshot is read-only and does not advance peer cursors',
      () async {
    final database = await AppDatabase.open(
      databasePath: '${temporaryDirectory.path}/snapshot.sqlite',
    );
    addTearDown(database.close);
    await database.database.insert('household', {'id': 'home', 'name': 'Casa'});
    await _insertProduct(database, 'milk', null);
    await database.writeLocalState('seq_counter', '1');

    final snapshot = await SyncDataStore(database).snapshotAfter(0);

    expect(snapshot.cursor, 1);
    expect(snapshot.changes, hasLength(1));
    expect(await database.database.query('peer'), isEmpty);
    expect(await database.readLocalState('seq_counter'), '1');
    expect((await database.database.query('product')).single['seq'], 1);
  });
}

DrawingImageStorage _storage(Directory directory) =>
    DrawingImageStorage(documentsDirectory: () async => directory);

Future<void> _insertProduct(
  AppDatabase database,
  String id,
  String? imageSrc,
) async {
  await database.database.insert('product', {
    'id': id,
    'household_id': 'home',
    'name': 'Leche',
    'lasts_days': 5,
    'last_bought_at': null,
    'last_emptied_at': null,
    'updated_at': 1,
    'deleted_at': null,
    'seq': 1,
    'last_writer_member_id': 'local',
    'image_src': imageSrc,
  });
}
