import '../models/user_model.dart';

abstract class UserRepository {
  Future<UserModel?> getUserById(String userId);
  Future<void> updateUser(UserModel user);
  Future<void> deleteUser(String userId);
  Stream<UserModel?> watchUser(String userId);
}