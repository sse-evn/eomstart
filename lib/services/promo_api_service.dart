import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:micro_mobility_app/config/app_config.dart';

class PromoApiServiceException implements Exception {
  final int? statusCode;
  final String message;

  PromoApiServiceException(this.message, {this.statusCode});

  @override
  String toString() => 'PromoApiServiceException(status=$statusCode): $message';
}

class PromoApiService {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<String?> _getToken() async {
    return await _storage.read(key: 'jwt_token');
  }

  Future<void> uploadPromoFile(List<int> fileBytes) async {
    final token = await _getToken();
    if (token == null) {
      throw PromoApiServiceException('Не авторизован', statusCode: 401);
    }

    final uri = Uri.parse('${AppConfig.apiBaseUrl}/promo/upload');
    final request = http.MultipartRequest('POST', uri);
    request.headers['Authorization'] = 'Bearer $token';
    request.files.add(
      http.MultipartFile.fromBytes('file', fileBytes, filename: 'promos.xlsx'),
    );

    final response = await request.send();
    final responseBody = await response.stream.bytesToString();

    if (response.statusCode == 200) {
      return;
    } else if (response.statusCode == 401) {
      throw PromoApiServiceException('Сессия истекла', statusCode: 401);
    } else if (response.statusCode == 403) {
      throw PromoApiServiceException(
          'Доступ запрещён: нужны права администратора',
          statusCode: 403);
    } else {
      final error = _tryParseJson(responseBody)?['error'] ?? responseBody;
      throw PromoApiServiceException('Ошибка загрузки: $error',
          statusCode: response.statusCode);
    }
  }

  Future<void> uploadPromoFromGoogleSheet(String sheetUrl) async {
    final token = await _getToken();
    if (token == null) {
      throw PromoApiServiceException('Не авторизован', statusCode: 401);
    }

    final response = await http.post(
      Uri.parse('${AppConfig.apiBaseUrl}/promo/upload'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json; charset=utf-8',
      },
      body: jsonEncode({'google_sheet_url': sheetUrl}),
    );

    if (response.statusCode == 200) {
      return;
    } else if (response.statusCode == 401) {
      throw PromoApiServiceException('Сессия истекла', statusCode: 401);
    } else if (response.statusCode == 403) {
      throw PromoApiServiceException(
          'Доступ запрещён: нужны права администратора',
          statusCode: 403);
    } else {
      final body = utf8.decode(response.bodyBytes);
      final error = _tryParseJson(body)?['error'] ?? body;
      throw PromoApiServiceException('Ошибка: $error',
          statusCode: response.statusCode);
    }
  }

  Future<Map<String, dynamic>> getPromoStats() async {
    final token = await _getToken();
    if (token == null) {
      throw PromoApiServiceException('Не авторизован', statusCode: 401);
    }

    final response = await http.get(
      Uri.parse('${AppConfig.apiBaseUrl}/promo/stats'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode == 200) {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } else if (response.statusCode == 401) {
      throw PromoApiServiceException('Сессия истекла', statusCode: 401);
    } else if (response.statusCode == 403) {
      throw PromoApiServiceException(
          'Доступ запрещён: нужны права администратора',
          statusCode: 403);
    } else {
      throw PromoApiServiceException('Ошибка загрузки статистики',
          statusCode: response.statusCode);
    }
  }

  Future<Map<String, dynamic>> claimPromoByBrand(String brand) async {
    final token = await _getToken();
    if (token == null) {
      throw PromoApiServiceException('Не авторизован', statusCode: 401);
    }

    final response = await http.post(
      Uri.parse('${AppConfig.apiBaseUrl}/promo/claim/$brand'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode == 200) {
      return jsonDecode(utf8.decode(response.bodyBytes))
          as Map<String, dynamic>;
    } else if (response.statusCode == 401) {
      throw PromoApiServiceException('Сессия истекла', statusCode: 401);
    } else if (response.statusCode == 400) {
      final body = utf8.decode(response.bodyBytes);
      final error = _tryParseJson(body)?['error'] ?? body;
      throw PromoApiServiceException(error.toString(), statusCode: 400);
    } else {
      throw PromoApiServiceException('Не удалось получить промокод',
          statusCode: response.statusCode);
    }
  }

  Future<List<dynamic>> getClaimedPromos() async {
    final token = await _getToken();
    if (token == null) {
      throw PromoApiServiceException('Не авторизован', statusCode: 401);
    }

    final response = await http.get(
      Uri.parse('${AppConfig.apiBaseUrl}/admin/users'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode == 200) {
      final users = jsonDecode(utf8.decode(response.bodyBytes)) as List;
      return users.where((user) {
        if (user is Map && user.containsKey('promo_codes')) {
          final promos = user['promo_codes'] as Map?;
          return promos != null && promos.isNotEmpty;
        }
        return false;
      }).toList();
    } else if (response.statusCode == 401) {
      throw PromoApiServiceException('Сессия истекла', statusCode: 401);
    } else if (response.statusCode == 403) {
      throw PromoApiServiceException('Доступ запрещён', statusCode: 403);
    } else {
      throw PromoApiServiceException('Ошибка загрузки данных пользователей',
          statusCode: response.statusCode);
    }
  }

  Future<void> setActivePromoBrand(String brand, {int days = 10}) async {
    final token = await _getToken();
    if (token == null) {
      throw PromoApiServiceException('Не авторизован', statusCode: 401);
    }

    final response = await http.post(
      Uri.parse('${AppConfig.apiBaseUrl}/admin/promo/activate-brand'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json'
      },
      body: jsonEncode({'brand': brand, 'days': days}),
    );

    if (response.statusCode == 401)
      throw PromoApiServiceException('Сессия истекла', statusCode: 401);
    if (response.statusCode == 403)
      throw PromoApiServiceException('Доступ запрещён', statusCode: 403);
    if (response.statusCode != 200) {
      final error = _tryParseJson(utf8.decode(response.bodyBytes))?['error'];
      throw PromoApiServiceException(error ?? 'Неизвестная ошибка',
          statusCode: response.statusCode);
    }
  }

  Future<void> clearActivePromoBrand() async {
    final token = await _getToken();
    if (token == null) {
      throw PromoApiServiceException('Не авторизован', statusCode: 401);
    }

    final response = await http.delete(
      Uri.parse('${AppConfig.apiBaseUrl}/admin/promo/activate-brand'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode == 401)
      throw PromoApiServiceException('Сессия истекла', statusCode: 401);
    if (response.statusCode == 403)
      throw PromoApiServiceException('Доступ запрещён', statusCode: 403);
    if (response.statusCode != 200) {
      throw PromoApiServiceException('Ошибка при сбросе',
          statusCode: response.statusCode);
    }
  }

  Future<Map<String, dynamic>?> getActivePromoBrand() async {
    final token = await _getToken();
    if (token == null) {
      throw PromoApiServiceException('Не авторизован', statusCode: 401);
    }

    final response = await http.get(
      Uri.parse('${AppConfig.apiBaseUrl}/admin/promo/active-brand'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode == 200) {
      final body = utf8.decode(response.bodyBytes);
      if (body == 'null' || body.trim().isEmpty) return null;
      return jsonDecode(body);
    }
    return null;
  }

  Map<String, dynamic>? _tryParseJson(String body) {
    try {
      return jsonDecode(body) as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }
}
