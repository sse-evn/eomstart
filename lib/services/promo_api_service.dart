// lib/services/promo_api_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:micro_mobility_app/config/app_config.dart';

class PromoApiService {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<String?> _getToken() async {
    return await _storage.read(key: 'jwt_token');
  }

  Future<List<dynamic>> getAdminPromoCodes() async {
    final token = await _getToken();
    if (token == null) throw Exception('Не авторизован');

    final response = await http.get(
      Uri.parse('${AppConfig.apiBaseUrl}/admin/promo-codes'),
      headers: {'Authorization': 'Bearer $token'},
    );

    final body = utf8.decode(response.bodyBytes);

    if (response.statusCode == 200) {
      final data = jsonDecode(body);
      if (data is List) return data;
      throw Exception('Ожидался массив промокодов');
    } else {
      final error = _tryParseJson(body)?['error'] ?? body;
      throw Exception('Ошибка загрузки: ${response.statusCode} — $error');
    }
  }

  Future<void> createPromoCode({
    required String id,
    required String date, // формат: "YYYY-MM-DD"
    required String title,
    String? description,
  }) async {
    final token = await _getToken();
    if (token == null) throw Exception('Не авторизован');

    final response = await http.post(
      Uri.parse('${AppConfig.apiBaseUrl}/admin/promo-codes'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json; charset=utf-8',
      },
      body: jsonEncode({
        'id': id,
        'date': date,
        'title': title,
        'description': description ?? '',
      }),
    );

    final body = utf8.decode(response.bodyBytes);

    if (response.statusCode != 200 && response.statusCode != 201) {
      final error = _tryParseJson(body)?['error'] ?? body;
      throw Exception('Ошибка создания: ${response.statusCode} — $error');
    }
  }

  Future<void> assignPromoToUser(String promoId, int userId) async {
    final token = await _getToken();
    if (token == null) throw Exception('Не авторизован');

    final response = await http.post(
      Uri.parse('${AppConfig.apiBaseUrl}/admin/promo-codes/$promoId/assign'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json; charset=utf-8',
      },
      body: jsonEncode({'user_id': userId}),
    );

    final body = utf8.decode(response.bodyBytes);

    if (response.statusCode != 200) {
      final error = _tryParseJson(body)?['error'] ?? body;
      throw Exception('Ошибка назначения: ${response.statusCode} — $error');
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
