// lib/services/user_promo_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:micro_mobility_app/config/app_config.dart';

class UserPromoService {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<String?> _getToken() async {
    return await _storage.read(key: 'jwt_token');
  }

  Future<Map<String, dynamic>> fetchDailyPromoCodes() async {
    final token = await _getToken();
    if (token == null) {
      throw Exception('Не авторизован: токен отсутствует');
    }

    final response = await http.get(
      Uri.parse('${AppConfig.apiBaseUrl}/daily-promo-codes'),
      headers: {'Authorization': 'Bearer $token'},
    );

    final responseBody = utf8.decode(response.bodyBytes);

    if (response.statusCode == 200) {
      final decoded = jsonDecode(responseBody);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      } else {
        throw Exception('Сервер вернул некорректный формат данных');
      }
    } else {
      final errorJson = _tryParseJson(responseBody);
      final errorMsg = errorJson?['error'] ?? responseBody;
      throw Exception('HTTP ${response.statusCode}: $errorMsg');
    }
  }

  Future<void> claimPromoCode(String promoId) async {
    final token = await _getToken();
    if (token == null) {
      throw Exception('Не авторизован');
    }

    final response = await http.post(
      Uri.parse('${AppConfig.apiBaseUrl}/claim-daily-promo'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json; charset=utf-8',
      },
      body: jsonEncode({'promo_id': promoId}),
    );

    final responseBody = utf8.decode(response.bodyBytes);

    if (response.statusCode != 200) {
      final errorJson = _tryParseJson(responseBody);
      final errorMsg = errorJson?['error'] ?? responseBody;
      throw Exception('Ошибка: ${response.statusCode} — $errorMsg');
    }
  }

  Map<String, dynamic>? _tryParseJson(String body) {
    try {
      return jsonDecode(body) as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }
}
