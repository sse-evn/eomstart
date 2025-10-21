// lib/utils/auth_utils.dart
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:micro_mobility_app/screens/auth_screen/login_screen.dart';

final _storage = const FlutterSecureStorage();

/// Выполняет выход из аккаунта: очищает токены и перенаправляет на экран входа.
Future<void> logout(BuildContext context) async {
  await _storage.delete(key: 'jwt_token');
  await _storage.delete(key: 'refresh_token');
  await _storage.delete(key: 'user_profile');

  if (context.mounted) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (Route<dynamic> route) => false,
    );
  }
}
