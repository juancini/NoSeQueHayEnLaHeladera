import '../entities/household.dart';
import '../entities/member.dart';

abstract interface class HouseholdRepository {
  Future<Household> createHousehold(String name, String myName);
  Future<Household?> current();
  Future<String> inviteQrPayload();
  Future<void> joinFromQr(String payload, String myName);
  Stream<List<Member>> watchMembers();
}
