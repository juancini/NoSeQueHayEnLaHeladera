import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../data/sync_service.dart';

final syncServiceProvider = Provider<SyncService>((ref) {
  final service = SyncService(ref.watch(appDatabaseProvider));
  ref.onDispose(() {
    unawaited(
      service.dispose().catchError((Object error, StackTrace stackTrace) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'sync service disposal',
          ),
        );
      }),
    );
  });
  return service;
});
