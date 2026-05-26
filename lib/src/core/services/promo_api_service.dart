import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:micro_mobility_app/src/core/config/app_config.dart';
import 'package:http_parser/http_parser.dart';

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

  Future<void> uploadPromoFile(
    List<int> fileBytes, {
    required String brand,
    required String validUntil,
    String? subtype,
  }) async {
    final token = await _getToken();
    if (token == null) {
      throw PromoApiServiceException('Не авторизован', statusCode: 401);
    }

    final uri = Uri.parse('${AppConfig.apiBaseUrl}/promo/upload');
    final request = http.MultipartRequest('POST', uri);

    request.headers['Authorization'] = 'Bearer $token';

    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        fileBytes,
        filename: 'promos.xlsx',
        contentType: MediaType(
          'application',
          'vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        ),
      ),
    );

    request.fields['brand'] = brand;
    request.fields['valid_until'] = validUntil;
    if (subtype != null && subtype.isNotEmpty) {
      request.fields['subtype'] = subtype;
    }

    final response = await request.send();
    final body = await response.stream.bytesToString();

    if (response.statusCode == 200) return;

    if (response.statusCode == 401) {
      throw PromoApiServiceException('Сессия истекла', statusCode: 401);
    }
    if (response.statusCode == 403) {
      throw PromoApiServiceException(
        'Доступ запрещён: нужны права администратора',
        statusCode: 403,
      );
    }

    final error = _tryParseJson(body)?['error'] ?? body;
    throw PromoApiServiceException(
      'Ошибка загрузки: $error',
      statusCode: response.statusCode,
    );
  }

  Future<void> uploadPromoFromGoogleSheet(String sheetUrl,
      {required String brand, required String validUntil, String? subtype}) async {
    final token = await _getToken();
    if (token == null) {
      throw PromoApiServiceException('Не авторизован', statusCode: 401);
    }

    final bodyMap = {
      'google_sheet_url': sheetUrl,
      'brand': brand,
      'valid_until': validUntil,
    };
    if (subtype != null && subtype.isNotEmpty) {
      bodyMap['subtype'] = subtype;
    }

    final response = await http.post(
      Uri.parse('${AppConfig.apiBaseUrl}/promo/upload'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json; charset=utf-8',
      },
      body: jsonEncode(bodyMap),
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
      // Успешно получен промокод
      return jsonDecode(utf8.decode(response.bodyBytes))
          as Map<String, dynamic>;
    } else {
      // Другие ошибки (400, 401, 403, 409, 500 и т.д.)
      final body = utf8.decode(response.bodyBytes);
      final errorData = _tryParseJson(body);
      final errorMessage = errorData?['error'] ?? 'Ошибка сервера (${response.statusCode})';
      
      throw PromoApiServiceException(
        errorMessage.toString(),
        statusCode: response.statusCode,
      );
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

  Future<List<dynamic>> getAllAdminUsers() async {
    final token = await _getToken();
    if (token == null) {
      throw PromoApiServiceException('Не авторизован', statusCode: 401);
    }

    final response = await http.get(
      Uri.parse('${AppConfig.apiBaseUrl}/admin/users'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode == 200) {
      return jsonDecode(utf8.decode(response.bodyBytes)) as List;
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

    if (response.statusCode == 401) {
      throw PromoApiServiceException('Сессия истекла', statusCode: 401);
    }
    if (response.statusCode == 403) {
      throw PromoApiServiceException('Доступ запрещён', statusCode: 403);
    }
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

    if (response.statusCode == 401) {
      throw PromoApiServiceException('Сессия истекла', statusCode: 401);
    }
    if (response.statusCode == 403) {
      throw PromoApiServiceException('Доступ запрещён', statusCode: 403);
    }
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

  Future<Map<String, String>> getBrandFormats() async {
    final token = await _getToken();
    if (token == null) {
      throw PromoApiServiceException('Не авторизован', statusCode: 401);
    }

    final response = await http.get(
      Uri.parse('${AppConfig.apiBaseUrl}/admin/promo/formats'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map;
      return data.map((key, value) => MapEntry(key.toString(), value.toString()));
    } else if (response.statusCode == 401) {
      throw PromoApiServiceException('Сессия истекла', statusCode: 401);
    } else if (response.statusCode == 403) {
      throw PromoApiServiceException('Доступ запрещён', statusCode: 403);
    } else {
      throw PromoApiServiceException('Ошибка загрузки форматов',
          statusCode: response.statusCode);
    }
  }

  Future<void> updateBrandFormat(String brand, String format) async {
    final token = await _getToken();
    if (token == null) {
      throw PromoApiServiceException('Не авторизован', statusCode: 401);
    }

    final response = await http.put(
      Uri.parse('${AppConfig.apiBaseUrl}/admin/promo/formats'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json'
      },
      body: jsonEncode({'brand': brand, 'format': format}),
    );

    if (response.statusCode == 401) {
      throw PromoApiServiceException('Сессия истекла', statusCode: 401);
    }
    if (response.statusCode == 403) {
      throw PromoApiServiceException('Доступ запрещён', statusCode: 403);
    }
    if (response.statusCode != 200) {
      final error = _tryParseJson(utf8.decode(response.bodyBytes))?['error'];
      throw PromoApiServiceException(error ?? 'Неизвестная ошибка',
          statusCode: response.statusCode);
    }
  }

  Map<String, dynamic>? _tryParseJson(String body) {
    try {
      return jsonDecode(body) as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  // ───── Bolt Accounts ─────

  Future<List<dynamic>> getBoltAccounts() async {
    final token = await _getToken();
    if (token == null) throw PromoApiServiceException('Не авторизован', statusCode: 401);

    final response = await http.get(
      Uri.parse('${AppConfig.apiBaseUrl}/admin/bolt-accounts'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode == 200) {
      return jsonDecode(utf8.decode(response.bodyBytes)) as List;
    }
    throw PromoApiServiceException('Ошибка загрузки', statusCode: response.statusCode);
  }

  Future<void> createBoltAccount(String login, String password, {String description = ''}) async {
    final token = await _getToken();
    if (token == null) throw PromoApiServiceException('Не авторизован', statusCode: 401);

    final response = await http.post(
      Uri.parse('${AppConfig.apiBaseUrl}/admin/bolt-accounts'),
      headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
      body: jsonEncode({'login': login, 'password': password, 'description': description}),
    );

    if (response.statusCode != 201) {
      final error = _tryParseJson(utf8.decode(response.bodyBytes))?['error'] ?? 'Ошибка';
      throw PromoApiServiceException(error, statusCode: response.statusCode);
    }
  }

  Future<void> updateBoltAccount(int id, {String? login, String? password, String? description, bool? isActive}) async {
    final token = await _getToken();
    if (token == null) throw PromoApiServiceException('Не авторизован', statusCode: 401);

    final body = <String, dynamic>{};
    if (login != null) body['login'] = login;
    if (password != null) body['password'] = password;
    if (description != null) body['description'] = description;
    if (isActive != null) body['is_active'] = isActive;

    final response = await http.put(
      Uri.parse('${AppConfig.apiBaseUrl}/admin/bolt-accounts/$id'),
      headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    if (response.statusCode != 200) {
      throw PromoApiServiceException('Ошибка обновления', statusCode: response.statusCode);
    }
  }

  Future<void> deleteBoltAccount(int id) async {
    final token = await _getToken();
    if (token == null) throw PromoApiServiceException('Не авторизован', statusCode: 401);

    final response = await http.delete(
      Uri.parse('${AppConfig.apiBaseUrl}/admin/bolt-accounts/$id'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode != 200) {
      throw PromoApiServiceException('Ошибка удаления', statusCode: response.statusCode);
    }
  }

  Future<void> bulkAssignBoltAccount(int accountId, List<int> userIds) async {
    final token = await _getToken();
    if (token == null) throw PromoApiServiceException('Не авторизован', statusCode: 401);

    final response = await http.post(
      Uri.parse('${AppConfig.apiBaseUrl}/admin/bolt-accounts/$accountId/bulk-assign'),
      headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
      body: jsonEncode({'user_ids': userIds}),
    );

    if (response.statusCode != 200) {
      throw PromoApiServiceException('Ошибка назначения', statusCode: response.statusCode);
    }
  }

  Future<void> unassignBoltAccount(int accountId, int userId) async {
    final token = await _getToken();
    if (token == null) throw PromoApiServiceException('Не авторизован', statusCode: 401);

    final response = await http.delete(
      Uri.parse('${AppConfig.apiBaseUrl}/admin/bolt-accounts/$accountId/unassign/$userId'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode != 200) {
      throw PromoApiServiceException('Ошибка снятия назначения', statusCode: response.statusCode);
    }
  }

  Future<Map<String, dynamic>?> getMyBoltAccount() async {
    final token = await _getToken();
    if (token == null) throw PromoApiServiceException('Не авторизован', statusCode: 401);

    final response = await http.get(
      Uri.parse('${AppConfig.apiBaseUrl}/bolt-account'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode == 200) {
      final body = utf8.decode(response.bodyBytes);
      if (body == 'null' || body.trim().isEmpty) return null;
      return jsonDecode(body) as Map<String, dynamic>;
    }
    return null;
  }
}
