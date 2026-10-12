import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../data/repositories/sqlite_household_repository.dart';
import '../../domain/entities/household.dart';
import '../../domain/repositories/household_repository.dart';

final householdRepositoryProvider = Provider<HouseholdRepository>(
  (ref) => SqliteHouseholdRepository(ref.watch(appDatabaseProvider)),
);

final currentHouseholdProvider = FutureProvider<Household?>(
  (ref) => ref.watch(householdRepositoryProvider).current(),
);
