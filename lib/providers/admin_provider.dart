// // lib/providers/admin_provider.dart
// import 'package:flutter/material.dart';
// import 'package:flutter_secure_storage/flutter_secure_storage.dart';
// import 'package:micro_mobility_app/services/api_service.dart';

// class AdminProvider with ChangeNotifier {
//   final ApiService _apiService = ApiService();
//   final FlutterSecureStorage _storage = const FlutterSecureStorage();

//   String _currentUserRole = '';
//   String get currentUserRole => _currentUserRole;

//   bool get isAdmin => _currentUserRole == 'superadmin';

//   // Инициализация профиля
//   Future<bool> initProfile() async {
//     try {
//       final token = await _storage.read(key: 'jwt_token');
//       if (token == null) return false;

//       final profile = await _apiService.getUserProfile(token);
//       final role = (profile['role'] ?? 'user').toString().toLowerCase();

//       _currentUserRole = role;
//       notifyListeners();
//       return true;
//     } catch (e) {
//       debugPrint('Ошибка загрузки профиля: $e');
//       return false;
//     }
//   }

//   // Обновить пользователей
//   Future<List<dynamic>> fetchUsers() async {
//     final token = await _storage.read(key: 'jwt_token');
//     if (token == null) throw Exception('Токен не найден');
//     return await _apiService.getAdminUsers(token);
//   }

//   // Обновить роль
//   Future<void> updateUserRole(
//       int userId, String newRole, String username) async {
//     final token = await _storage.read(key: 'jwt_token');
//     if (token == null) throw Exception('Токен не найден');
//     await _apiService.updateUserRole(token, userId, newRole);
//   }

//   // // Активировать
//   // Future<void> activateUser(int userId) async {
//   //   final token = await _storage.read(key: 'jwt_token');
//   //   if (token == null) throw Exception('Токен не найден');
//   //   await _apiService.activateUser(token, userId);
//   // }

//   // // Деактивировать
//   // Future<void> deactivateUser(int userId) async {
//   //   final token = await _storage.read(key: 'jwt_token');
//   //   if (token == null) throw Exception('Токен не найден');
//   //   await _apiService.deactivateUser(token, userId);
//   // }

//   // Удалить
//   // Future<void> deleteUser(int userId) async {
//   //   final token = await _storage.read(key: 'jwt_token');
//   //   if (token == null) throw Exception('Токен не найден');
//   //   await _apiService.deleteUser(token, userId);
//   // }

//   // // Создать
//   // Future<void> createUser(String username, String? firstName) async {
//   //   final token = await _storage.read(key: 'jwt_token');
//   //   if (token == null) throw Exception('Токен не найден');
//   //   await _apiService.createUser(token, username, firstName ?? '');
//   // }
// }
