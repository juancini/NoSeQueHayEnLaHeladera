import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../data/sync_service.dart';

final syncServiceProvider = Provider<SyncService>((ref) {
  final service = SyncService(ref.watch(appDatabaseProvider));
  ref.onDispose(() => unawaited(service.stop()));
  return service;
});
