import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:micro_mobility_app/models/active_shift.dart' as active_shift;
import '../models/shift_data.dart' as shift_data;
import '../config.dart';

class ApiService {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<http.Response> _authorizedRequest(
    Future<http.Response> Function(String token) requestFunction,
    String originalToken,
  ) async {
    http.Response response = await requestFunction(originalToken);

    if (response.statusCode == 401) {
      debugPrint('🚨 401 received, attempting token refresh...');
      final newToken = await refreshToken();
      if (newToken != null) {
        debugPrint('✅ Token refreshed, retrying request...');
        response = await requestFunction(newToken);
      } else {
        debugPrint('❌ Token refresh failed');
      }
    }

    return response;
  }

  Future<String?> refreshToken() async {
    try {
      final refreshToken = await _storage.read(key: 'refresh_token');
      if (refreshToken == null) {
        debugPrint('No refresh token found');
        return null;
      }

      debugPrint('🔄 Attempting to refresh token...');
      final response = await http.post(
        Uri.parse(AppConfig.refreshTokenUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': refreshToken}),
      );

      debugPrint('🔄 Refresh response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final newAccessToken = body['access_token'];
        if (newAccessToken != null) {
          await _storage.write(key: 'jwt_token', value: newAccessToken);
          debugPrint('✅ Access token refreshed and saved.');
          return newAccessToken as String;
        }
      } else {
        debugPrint(
            '🔄 Failed to refresh token: ${response.statusCode} - ${response.body}');
        await _storage.delete(key: 'refresh_token');
      }
    } catch (e) {
      debugPrint('🔄 Exception during token refresh: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>> login(String username, String password) async {
    final response = await http.post(
      Uri.parse(AppConfig.loginUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'password': password,
      }),
    );

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      await _storage.write(key: 'jwt_token', value: body['token']);
      await _storage.write(key: 'refresh_token', value: body['refresh_token']);
      return body;
    } else {
      throw Exception(
          'Ошибка авторизации: ${response.statusCode} - ${response.body}');
    }
  }

  Future<void> logout(String token) async {
    try {
      await http.post(
        Uri.parse(AppConfig.logoutUrl),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );
    } catch (e) {
      debugPrint('Error calling logout endpoint: $e');
    } finally {
      await _storage.delete(key: 'jwt_token');
      await _storage.delete(key: 'refresh_token');
    }
  }

  Future<Map<String, dynamic>> getScooterStatsForShift(String token) async {
    final response = await _authorizedRequest((token) async {
      return await http.get(
        Uri.parse(AppConfig.scooterStatsUrl),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );
    }, token);

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception(
          'Failed to load scooter stats: ${response.statusCode} - ${utf8.decode(response.bodyBytes)}');
    }
  }

  Future<int?> getUserTelegramId(String token, int userId) async {
    final response = await _authorizedRequest((token) async {
      return await http.get(
        Uri.parse(AppConfig.userTelegramIdUrl(userId)),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );
    }, token);

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return body['telegram_user_id'] as int?;
    } else {
      debugPrint(
          'getUserTelegramId: Failed for user $userId. Status: ${response.statusCode}, Body: ${response.body}');
      return null;
    }
  }

  Future<Map<String, dynamic>> getUserProfile(String token) async {
    final response = await _authorizedRequest((token) async {
      return await http.get(
        Uri.parse(AppConfig.profileUrl),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );
    }, token);

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception(
          'Failed to load profile: ${response.statusCode} - ${utf8.decode(response.bodyBytes)}');
    }
  }

  Future<List<dynamic>> getAdminUsers(String token) async {
    final response = await _authorizedRequest((token) async {
      return await http.get(
        Uri.parse(AppConfig.adminUsersUrl),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );
    }, token);

    if (response.statusCode == 200) {
      final dynamic body = jsonDecode(response.body);
      if (body is List) return body;
      return [];
    } else {
      throw Exception(
          'Failed to load users: ${response.statusCode} - ${utf8.decode(response.bodyBytes)}');
    }
  }

  Future<void> updateUserRole(String token, int userId, String newRole) async {
    final response = await _authorizedRequest((token) async {
      return await http.patch(
        Uri.parse(AppConfig.updateUserRoleUrl(userId)),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'role': newRole}),
      );
    }, token);

    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception(
          'Failed to update role: ${response.statusCode} - ${utf8.decode(response.bodyBytes)}');
    }
  }

  Future<void> createUser(
      String token, String username, String password) async {
    final response = await _authorizedRequest((token) async {
      return await http.post(
        Uri.parse(AppConfig.adminUsersUrl),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'username': username,
          'password': password,
        }),
      );
    }, token);

    if (response.statusCode != 201) {
      throw Exception('Ошибка: ${utf8.decode(response.bodyBytes)}');
    }
  }

  Future<void> deleteUser(String token, int userId) async {
    final response = await _authorizedRequest((token) async {
      return await http.delete(
        Uri.parse(AppConfig.deleteUserUrl(userId)),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );
    }, token);

    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception(
          'Failed to delete user: ${response.statusCode} - ${utf8.decode(response.bodyBytes)}');
    }
  }

  Future<void> activateUser(String token, int userId) async {
    final response = await _authorizedRequest((token) async {
      return await http.patch(
        Uri.parse(AppConfig.updateUserStatusUrl(userId)),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'is_active': true}),
      );
    }, token);

    if (response.statusCode != 200) {
      throw Exception('Failed to activate user');
    }
  }

  Future<void> deactivateUser(String token, int userId) async {
    final response = await _authorizedRequest((token) async {
      return await http.patch(
        Uri.parse(AppConfig.updateUserStatusUrl(userId)),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'is_active': false}),
      );
    }, token);

    if (response.statusCode != 200) {
      throw Exception('Failed to deactivate user');
    }
  }

  Future<void> forceEndShift(String token, int userId) async {
    final response = await _authorizedRequest((token) async {
      return await http.post(
        Uri.parse(AppConfig.forceEndShiftUrl(userId)),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );
    }, token);

    if (response.statusCode != 200 && response.statusCode != 204) {
      final message = utf8.decode(response.bodyBytes);
      throw Exception(
          'Failed to force end shift: ${response.statusCode} — $message');
    }
  }

  Future<List<shift_data.ShiftData>> getShifts(String token) async {
    try {
      final response = await _authorizedRequest((token) async {
        return await http.get(
          Uri.parse(AppConfig.shiftsUrl),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        );
      }, token);

      if (response.statusCode == 200) {
        final dynamic body = jsonDecode(response.body);
        if (body is List) {
          return body
              .whereType<Map<String, dynamic>>()
              .map((item) => shift_data.ShiftData.fromJson(item))
              .toList();
        }
        return [];
      } else {
        throw Exception(
            'Failed to load shifts: ${response.statusCode} - ${utf8.decode(response.bodyBytes)}');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> startSlot({
    required String token,
    required String slotTimeRange,
    required String position,
    required String zone,
    required File selfieImage,
  }) async {
    try {
      String effectiveToken = token;
      if (await _isTokenAboutToExpire(token)) {
        final newToken = await refreshToken();
        if (newToken != null) {
          effectiveToken = newToken;
        } else {
          throw Exception('Token expired and refresh failed');
        }
      }

      final request =
          http.MultipartRequest('POST', Uri.parse(AppConfig.startSlotUrl));
      request.headers['Authorization'] = 'Bearer $effectiveToken';
      request.fields['slot_time_range'] = slotTimeRange;
      request.fields['position'] = position;
      request.fields['zone'] = zone;

      if (await selfieImage.exists()) {
        request.files
            .add(await http.MultipartFile.fromPath('selfie', selfieImage.path));
      } else {
        throw Exception('Selfie file does not exist');
      }

      final response = await request.send();
      final resp = await http.Response.fromStream(response);

      if (resp.statusCode != 200 && resp.statusCode != 201) {
        throw Exception(
            'Failed to start slot: ${resp.reasonPhrase} - ${utf8.decode(resp.bodyBytes)}');
      }
    } catch (e) {
      debugPrint('Error in startSlot: $e');
      rethrow;
    }
  }

  Future<void> endSlot(String token) async {
    try {
      final response = await _authorizedRequest((token) async {
        return await http.post(
          Uri.parse(AppConfig.endSlotUrl),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        );
      }, token);

      if (response.statusCode != 200 && response.statusCode != 204) {
        throw Exception(
            'Failed to end slot: ${response.statusCode} - ${utf8.decode(response.bodyBytes)}');
      }
    } catch (e) {
      debugPrint('Error in endSlot: $e');
      rethrow;
    }
  }

  Future<active_shift.ActiveShift?> getActiveShift(String token) async {
    final response = await _authorizedRequest((token) async {
      return await http.get(
        Uri.parse(AppConfig.activeShiftUrl),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );
    }, token);

    debugPrint('📡 GetUserActiveShift API status: ${response.statusCode}');
    debugPrint('📡 GetUserActiveShift API body: ${response.body}');

    if (response.statusCode == 200) {
      if (response.body == 'null' || response.body.trim().isEmpty) {
        debugPrint('📡 No active shift found (null response)');
        return null;
      }

      try {
        final dynamic body = jsonDecode(response.body);
        if (body is Map<String, dynamic>) {
          debugPrint('✅ Parsed single active shift object');
          return active_shift.ActiveShift.fromJson(body);
        } else if (body is List &&
            body.isNotEmpty &&
            body[0] is Map<String, dynamic>) {
          debugPrint('✅ Parsed active shift from array[0]');
          return active_shift.ActiveShift.fromJson(body[0]);
        } else if (body is List && body.isEmpty) {
          debugPrint('📡 Empty array response, no active shift');
          return null;
        }
        debugPrint('❌ Unexpected response format: ${body.runtimeType}');
        return null;
      } catch (e) {
        debugPrint('❌ Error parsing active shift: $e');
        return null;
      }
    } else {
      debugPrint('❌ API error: ${response.statusCode} - ${response.body}');
      return null;
    }
  }

  Future<List<active_shift.ActiveShift>> getActiveShifts(String token) async {
    final response = await _authorizedRequest((token) async {
      return await http.get(
        Uri.parse('${AppConfig.apiBaseUrl}/admin/active-shifts'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );
    }, token);

    debugPrint('📡 GetActiveShifts API status: ${response.statusCode}');
    debugPrint('📡 GetActiveShifts API body: ${response.body}');

    if (response.statusCode == 200) {
      if (response.body == 'null' || response.body.trim().isEmpty) {
        return [];
      }

      try {
        final dynamic body = jsonDecode(response.body);
        if (body is List) {
          return body
              .whereType<Map<String, dynamic>>()
              .map((item) => active_shift.ActiveShift.fromJson(item))
              .toList();
        }
        debugPrint('❌ Expected array but got: ${body.runtimeType}');
        return [];
      } catch (e) {
        debugPrint('❌ Error parsing active shifts list: $e');
        return [];
      }
    } else {
      throw Exception('Failed to load active shifts: ${response.statusCode}');
    }
  }

  // ✅ НОВЫЙ МЕТОД: Получение завершённых смен
  Future<List<active_shift.ActiveShift>> getEndedShifts(String token) async {
    final response = await _authorizedRequest((token) async {
      return await http.get(
        Uri.parse('${AppConfig.apiBaseUrl}/admin/ended-shifts'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );
    }, token);

    if (response.statusCode == 200) {
      final dynamic body = jsonDecode(response.body);
      if (body is List) {
        return body
            .whereType<Map<String, dynamic>>()
            .map((item) => active_shift.ActiveShift.fromJson(item))
            .toList();
      }
      return [];
    } else {
      throw Exception('Failed to load ended shifts: ${response.statusCode}');
    }
  }

  Future<List<String>> getAvailablePositions(String token) async {
    final response = await _authorizedRequest((token) async {
      return await http.get(
        Uri.parse(AppConfig.positionsUrl),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );
    }, token);

    if (response.statusCode == 200) {
      final dynamic body = jsonDecode(response.body);
      if (body is List) {
        return body.map((e) => e.toString()).toList();
      }
      return [];
    } else {
      throw Exception(
          'Failed to load positions: ${response.statusCode} - ${utf8.decode(response.bodyBytes)}');
    }
  }

  Future<List<String>> getAvailableTimeSlots(String token) async {
    final response = await _authorizedRequest((token) async {
      return await http.get(
        Uri.parse(AppConfig.timeSlotsUrl),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );
    }, token);

    if (response.statusCode == 200) {
      final dynamic body = jsonDecode(response.body);
      if (body is List) {
        return body.map((e) => e.toString()).toList();
      }
      return [];
    } else {
      throw Exception(
          'Failed to load time slots: ${response.statusCode} - ${utf8.decode(response.bodyBytes)}');
    }
  }

  Future<List<String>> getAvailableZones(String token) async {
    final response = await _authorizedRequest((token) async {
      return await http.get(
        Uri.parse(AppConfig.zonesUrl),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );
    }, token);

    if (response.statusCode == 200) {
      final dynamic body = jsonDecode(response.body);
      if (body is List) {
        return body.map((e) => e.toString()).toList();
      }
      return [];
    } else {
      throw Exception('Failed to load zones: ${response.statusCode}');
    }
  }

  Future<void> createZone(String token, String name) async {
    final response = await _authorizedRequest((token) async {
      return await http.post(
        Uri.parse(AppConfig.adminZonesUrl),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'name': name}),
      );
    }, token);

    if (response.statusCode != 201) {
      throw Exception('Failed to create zone');
    }
  }

  Future<void> updateZone(String token, int id, String name) async {
    final response = await _authorizedRequest((token) async {
      return await http.put(
        Uri.parse(AppConfig.updateZoneUrl(id)),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'name': name}),
      );
    }, token);

    if (response.statusCode != 200) {
      throw Exception('Failed to update zone');
    }
  }

  Future<void> deleteZone(String token, int id) async {
    final response = await _authorizedRequest((token) async {
      return await http.delete(
        Uri.parse(AppConfig.updateZoneUrl(id)),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );
    }, token);

    if (response.statusCode != 200) {
      throw Exception('Failed to delete zone');
    }
  }

  Future<List<dynamic>> getUploadedMaps(String token) async {
    try {
      final response = await _authorizedRequest((token) async {
        return await http.get(
          Uri.parse(AppConfig.adminMapsUrl),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        );
      }, token);

      if (response.statusCode == 200) {
        final dynamic body = jsonDecode(response.body);
        if (body is List) return body;
        return [];
      } else {
        throw Exception(
            'Failed to load maps: ${response.statusCode} - ${utf8.decode(response.bodyBytes)}');
      }
    } catch (e) {
      debugPrint('Error loading maps: $e');
      rethrow;
    }
  }

  Future<void> uploadMap({
    required String token,
    required String city,
    required String description,
    required File geoJsonFile,
  }) async {
    try {
      String effectiveToken = token;
      if (await _isTokenAboutToExpire(token)) {
        final newToken = await refreshToken();
        if (newToken != null) {
          effectiveToken = newToken;
        } else {
          throw Exception('Token expired and refresh failed');
        }
      }

      final request =
          http.MultipartRequest('POST', Uri.parse(AppConfig.uploadMapUrl));
      request.headers['Authorization'] = 'Bearer $effectiveToken';
      request.fields['city'] = city;
      request.fields['description'] = description;

      if (await geoJsonFile.exists()) {
        final file = await http.MultipartFile.fromPath(
          'geojson_file',
          geoJsonFile.path,
          filename: geoJsonFile.path.split('/').last,
        );
        request.files.add(file);
      } else {
        throw Exception('GeoJSON file does not exist');
      }

      final response = await request.send();
      final resp = await http.Response.fromStream(response);

      if (resp.statusCode != 200 && resp.statusCode != 201) {
        throw Exception(
            'Failed to upload map: ${resp.statusCode} - ${utf8.decode(resp.bodyBytes)}');
      }
    } catch (e) {
      debugPrint('Error uploading map: $e');
      rethrow;
    }
  }

  Future<void> deleteMap({
    required String token,
    required int mapId,
  }) async {
    try {
      final response = await _authorizedRequest((token) async {
        return await http.delete(
          Uri.parse(AppConfig.deleteMapUrl(mapId)),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        );
      }, token);

      if (response.statusCode != 200 && response.statusCode != 204) {
        throw Exception(
            'Failed to delete map: ${response.statusCode} - ${utf8.decode(response.bodyBytes)}');
      }
    } catch (e) {
      debugPrint('Error deleting map: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getMapById({
    required String token,
    required int mapId,
  }) async {
    try {
      final response = await _authorizedRequest((token) async {
        return await http.get(
          Uri.parse(AppConfig.getMapByIdUrl(mapId)),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        );
      }, token);

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        throw Exception(
            'Failed to load map: ${response.statusCode} - ${utf8.decode(response.bodyBytes)}');
      }
    } catch (e) {
      debugPrint('Error loading map by id: $e');
      rethrow;
    }
  }

  Future<bool> _isTokenAboutToExpire(String token) async {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return true;
      final payload = parts[1];
      final normalizedPayload = base64Url.normalize(payload);
      final payloadBytes = base64Url.decode(normalizedPayload);
      final payloadJson = utf8.decode(payloadBytes);
      final payloadMap = jsonDecode(payloadJson) as Map<String, dynamic>;
      final exp = payloadMap['exp'];
      if (exp is int) {
        final expirationTime = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
        return DateTime.now()
            .isAfter(expirationTime.subtract(const Duration(seconds: 30)));
      }
    } catch (e) {
      debugPrint('Error checking token expiration: $e');
    }
    return true;
  }

  Future<void> generateShifts({
    required String token,
    required DateTime date,
    required int morningCount,
    required int eveningCount,
    required List<int> selectedScoutIds,
  }) async {
    if (morningCount == 0 && eveningCount == 0) {
      throw Exception('Укажите хотя бы одну смену');
    }

    if (selectedScoutIds.isEmpty) {
      throw Exception('Не выбрано ни одного скаута');
    }

    final body = {
      'date':
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
      'morning_count': morningCount,
      'evening_count': eveningCount,
      'scout_ids': selectedScoutIds,
    };

    debugPrint('📤 Отправляю на генерацию смен: $body');

    final response = await _authorizedRequest((token) async {
      return await http.post(
        Uri.parse(AppConfig.generateShiftsUrl),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );
    }, token);

    if (response.statusCode != 200 && response.statusCode != 201) {
      final message = utf8.decode(response.bodyBytes);
      debugPrint('❌ Ошибка генерации смен: $message');
      throw Exception('Ошибка: $message');
    }
  }
}
