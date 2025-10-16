import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:micro_mobility_app/models/active_shift.dart' as active_shift;
import '../models/shift_data.dart' as shift_data;
import '../config/config.dart';

class ApiService {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<http.Response> _authorizedRequest(
    Future<http.Response> Function(String token) requestFunction,
    String originalToken,
  ) async {
    http.Response response = await requestFunction(originalToken);

    if (response.statusCode == 401) {
      debugPrint('Access token expired (401). Attempting to refresh...');
      final newToken = await refreshToken();
      if (newToken != null) {
        debugPrint('Token refreshed successfully. Retrying request...');
        response = await requestFunction(newToken);
      } else {
        debugPrint('Failed to refresh token. User needs to log in again.');
      }
    }
    return response;
  }

  Future<String?> refreshToken() async {
    try {
      final refreshToken = await _storage.read(key: 'refresh_token');
      if (refreshToken == null || refreshToken.isEmpty) {
        debugPrint('No refresh token found in storage.');
        return null;
      }

      debugPrint('Attempting to refresh token with stored refresh token.');

      final response = await http.post(
        Uri.parse(AppConfig.refreshTokenUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': refreshToken}),
      );

      debugPrint('Refresh token response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>?;

        final newAccessToken = body?['token'] as String?;
        final newRefreshToken = body?['refresh_token'] as String?;

        if (newAccessToken != null) {
          await _storage.write(key: 'jwt_token', value: newAccessToken);
          if (newRefreshToken != null) {
            await _storage.write(key: 'refresh_token', value: newRefreshToken);
            debugPrint('New access and refresh tokens saved.');
          } else {
            debugPrint('Warning: New refresh token not received from server.');
          }
          return newAccessToken;
        } else {
          debugPrint('Refresh response missing access token.');
        }
      } else {
        debugPrint(
            'Refresh token request failed: ${response.statusCode}. Clearing tokens.');
        await _storage.delete(key: 'jwt_token');
        await _storage.delete(key: 'refresh_token');
      }
    } catch (e, stackTrace) {
      debugPrint(
          'Exception during token refresh: $e\nStack trace: $stackTrace');
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
      final body = jsonDecode(response.body) as Map<String, dynamic>?;

      final accessToken = body?['token'] as String?;
      final refreshToken = body?['refresh_token'] as String?;

      if (accessToken != null && refreshToken != null) {
        await _storage.write(key: 'jwt_token', value: accessToken);
        await _storage.write(key: 'refresh_token', value: refreshToken);
        debugPrint('Login successful. Tokens saved.');
        return body!;
      } else {
        debugPrint('Login response missing tokens.');
        throw Exception(
            'Ошибка авторизации: Неполный ответ от сервера (отсутствуют токены)');
      }
    } else {
      debugPrint('Login failed: ${response.statusCode} - ${response.body}');
      String errorMessage = 'Ошибка авторизации: ${response.statusCode}';
      try {
        final errorBody = jsonDecode(response.body) as Map<String, dynamic>?;
        errorMessage = errorBody?['error']?.toString() ??
            errorBody?['message']?.toString() ??
            errorMessage;
      } catch (e) {
        debugPrint('Error parsing login error response: $e');
      }
      throw Exception(errorMessage);
    }
  }

  Future<void> logout(String token) async {
    try {
      final response = await http.post(
        Uri.parse(AppConfig.logoutUrl),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );
      if (response.statusCode != 200) {
        debugPrint('Logout endpoint returned status ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error calling logout endpoint (not critical): $e');
    } finally {
      await _storage.delete(key: 'jwt_token');
      await _storage.delete(key: 'refresh_token');
      debugPrint('Tokens cleared on logout.');
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
      String errorMessage = 'Failed to update role';
      try {
        final errorBody = jsonDecode(utf8.decode(response.bodyBytes));
        errorMessage = errorBody['error']?.toString() ?? errorMessage;
        if (errorMessage == 'Failed to update role') {
          errorMessage = errorBody['message']?.toString() ?? errorMessage;
        }
      } catch (e) {
        debugPrint('Ошибка парсинга тела ошибки updateUserRole: $e');
      }
      throw Exception(errorMessage);
    }
  }

  Future<void> updateUserStatus(String token, int userId, String status) async {
    final response = await _authorizedRequest((token) async {
      return await http.patch(
        Uri.parse('${AppConfig.apiBaseUrl}/admin/users/$userId/status'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'status': status}),
      );
    }, token);
    if (response.statusCode != 200) {
      String errorMessage = 'Failed to update user status';
      try {
        final errorBody = jsonDecode(utf8.decode(response.bodyBytes));
        errorMessage = errorBody['error']?.toString() ?? errorMessage;
        if (errorMessage == 'Failed to update user status') {
          errorMessage = errorBody['message']?.toString() ?? errorMessage;
        }
      } catch (e) {
        debugPrint('Ошибка парсинга тела ошибки updateUserStatus: $e');
      }
      throw Exception(errorMessage);
    }
  }

  Future<void> createUser(
    String token,
    String username,
    String password, {
    String? firstName,
  }) async {
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
          if (firstName != null) 'first_name': firstName,
        }),
      );
    }, token);
    if (response.statusCode != 201) {
      String errorMessage = 'Failed to create user';
      try {
        final errorBody = jsonDecode(utf8.decode(response.bodyBytes));
        errorMessage = errorBody['error']?.toString() ?? errorMessage;
        if (errorMessage == 'Failed to create user') {
          errorMessage = errorBody['message']?.toString() ?? errorMessage;
        }
      } catch (e) {
        debugPrint('Ошибка парсинга тела ошибки createUser: $e');
      }
      throw Exception(errorMessage);
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
      String errorMessage = 'Failed to delete user';
      try {
        final errorBody = jsonDecode(utf8.decode(response.bodyBytes));
        errorMessage = errorBody['error']?.toString() ?? errorMessage;
        if (errorMessage == 'Failed to delete user') {
          errorMessage = errorBody['message']?.toString() ?? errorMessage;
        }
      } catch (e) {
        debugPrint('Ошибка парсинга тела ошибки deleteUser: $e');
      }
      throw Exception(errorMessage);
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
        String errorMessage = 'Failed to load shifts';
        try {
          final errorBody = jsonDecode(utf8.decode(response.bodyBytes));
          errorMessage = errorBody['error']?.toString() ?? errorMessage;
          if (errorMessage == 'Failed to load shifts') {
            errorMessage = errorBody['message']?.toString() ?? errorMessage;
          }
        } catch (e) {
          debugPrint('Ошибка парсинга тела ошибки getShifts: $e');
        }
        throw Exception(errorMessage);
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
        String errorMessage = 'Failed to start slot';
        try {
          final errorBody = jsonDecode(utf8.decode(resp.bodyBytes));
          errorMessage = errorBody['error']?.toString() ?? errorMessage;
          if (errorMessage == 'Failed to start slot') {
            errorMessage = errorBody['message']?.toString() ?? errorMessage;
          }
        } catch (e) {
          debugPrint('Ошибка парсинга тела ошибки startSlot: $e');
        }
        throw Exception(errorMessage);
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
        String errorMessage = 'Failed to end slot';
        try {
          final errorBody = jsonDecode(utf8.decode(response.bodyBytes));
          errorMessage = errorBody['error']?.toString() ?? errorMessage;
          if (errorMessage == 'Failed to end slot') {
            errorMessage = errorBody['message']?.toString() ?? errorMessage;
          }
        } catch (e) {
          debugPrint('Ошибка парсинга тела ошибки endSlot: $e');
        }
        throw Exception(errorMessage);
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
    if (response.statusCode == 200) {
      if (response.body == 'null' || response.body.trim().isEmpty) {
        return null;
      }
      try {
        final dynamic body = jsonDecode(response.body);
        if (body is Map<String, dynamic>) {
          return active_shift.ActiveShift.fromJson(body);
        } else if (body is List &&
            body.isNotEmpty &&
            body[0] is Map<String, dynamic>) {
          return active_shift.ActiveShift.fromJson(body[0]);
        } else if (body is List && body.isEmpty) {
          return null;
        }
        return null;
      } catch (e) {
        return null;
      }
    } else {
      String errorMessage = 'Failed to load active shift';
      try {
        final errorBody = jsonDecode(utf8.decode(response.bodyBytes));
        errorMessage = errorBody['error']?.toString() ?? errorMessage;
        if (errorMessage == 'Failed to load active shift') {
          errorMessage = errorBody['message']?.toString() ?? errorMessage;
        }
      } catch (e) {
        debugPrint('Ошибка парсинга тела ошибки getActiveShift: $e');
      }
      debugPrint(errorMessage);
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
        return [];
      } catch (e) {
        return [];
      }
    } else {
      String errorMessage = 'Failed to load active shifts';
      try {
        final errorBody = jsonDecode(utf8.decode(response.bodyBytes));
        errorMessage = errorBody['error']?.toString() ?? errorMessage;
        if (errorMessage == 'Failed to load active shifts') {
          errorMessage = errorBody['message']?.toString() ?? errorMessage;
        }
      } catch (e) {
        debugPrint('Ошибка парсинга тела ошибки getActiveShifts: $e');
      }
      throw Exception(errorMessage);
    }
  }

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
      String errorMessage = 'Failed to load ended shifts';
      try {
        final errorBody = jsonDecode(utf8.decode(response.bodyBytes));
        errorMessage = errorBody['error']?.toString() ?? errorMessage;
        if (errorMessage == 'Failed to load ended shifts') {
          errorMessage = errorBody['message']?.toString() ?? errorMessage;
        }
      } catch (e) {
        debugPrint('Ошибка парсинга тела ошибки getEndedShifts: $e');
      }
      throw Exception(errorMessage);
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
      String errorMessage = 'Failed to load positions';
      try {
        final errorBody = jsonDecode(utf8.decode(response.bodyBytes));
        errorMessage = errorBody['error']?.toString() ?? errorMessage;
        if (errorMessage == 'Failed to load positions') {
          errorMessage = errorBody['message']?.toString() ?? errorMessage;
        }
      } catch (e) {
        debugPrint('Ошибка парсинга тела ошибки getAvailablePositions: $e');
      }
      throw Exception(errorMessage);
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
      String errorMessage = 'Failed to load time slots';
      try {
        final errorBody = jsonDecode(utf8.decode(response.bodyBytes));
        errorMessage = errorBody['error']?.toString() ?? errorMessage;
        if (errorMessage == 'Failed to load time slots') {
          errorMessage = errorBody['message']?.toString() ?? errorMessage;
        }
      } catch (e) {
        debugPrint('Ошибка парсинга тела ошибки getAvailableTimeSlots: $e');
      }
      throw Exception(errorMessage);
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
        return body
            .map((e) {
              if (e is Map<String, dynamic> && e.containsKey('name')) {
                return e['name'].toString();
              } else if (e is String) {
                return e;
              }
              return '';
            })
            .where((name) => name.isNotEmpty)
            .toList();
      }
      return [];
    } else {
      String errorMessage = 'Failed to load zones';
      try {
        final errorBody = jsonDecode(utf8.decode(response.bodyBytes));
        errorMessage = errorBody['error']?.toString() ?? errorMessage;
        if (errorMessage == 'Failed to load zones') {
          errorMessage = errorBody['message']?.toString() ?? errorMessage;
        }
      } catch (e) {
        debugPrint('Ошибка парсинга тела ошибки getAvailableZones: $e');
      }
      throw Exception(errorMessage);
    }
  }

  Future<List<Map<String, dynamic>>> getAvailableZonesRaw(String token) async {
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
        return body.cast<Map<String, dynamic>>();
      }
      return [];
    } else {
      String errorMessage = 'Failed to load zones raw';
      try {
        final errorBody = jsonDecode(utf8.decode(response.bodyBytes));
        errorMessage = errorBody['error']?.toString() ?? errorMessage;
        if (errorMessage == 'Failed to load zones raw') {
          errorMessage = errorBody['message']?.toString() ?? errorMessage;
        }
      } catch (e) {
        debugPrint('Ошибка парсинга тела ошибки getAvailableZonesRaw: $e');
      }
      throw Exception(errorMessage);
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
      String errorMessage = 'Failed to create zone';
      try {
        final errorBody = jsonDecode(utf8.decode(response.bodyBytes));
        errorMessage = errorBody['error']?.toString() ?? errorMessage;
        if (errorMessage == 'Failed to create zone') {
          errorMessage = errorBody['message']?.toString() ?? errorMessage;
        }
      } catch (e) {
        debugPrint('Ошибка парсинга тела ошибки createZone: $e');
      }
      throw Exception(errorMessage);
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
      String errorMessage = 'Failed to update zone';
      try {
        final errorBody = jsonDecode(utf8.decode(response.bodyBytes));
        errorMessage = errorBody['error']?.toString() ?? errorMessage;
        if (errorMessage == 'Failed to update zone') {
          errorMessage = errorBody['message']?.toString() ?? errorMessage;
        }
      } catch (e) {
        debugPrint('Ошибка парсинга тела ошибки updateZone: $e');
      }
      throw Exception(errorMessage);
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
      String errorMessage = 'Failed to delete zone';
      try {
        final errorBody = jsonDecode(utf8.decode(response.bodyBytes));
        errorMessage = errorBody['error']?.toString() ?? errorMessage;
        if (errorMessage == 'Failed to delete zone') {
          errorMessage = errorBody['message']?.toString() ?? errorMessage;
        }
      } catch (e) {
        debugPrint('Ошибка парсинга тела ошибки deleteZone: $e');
      }
      throw Exception(errorMessage);
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
        String errorMessage = 'Failed to load maps';
        try {
          final errorBody = jsonDecode(utf8.decode(response.bodyBytes));
          errorMessage = errorBody['error']?.toString() ?? errorMessage;
          if (errorMessage == 'Failed to load maps') {
            errorMessage = errorBody['message']?.toString() ?? errorMessage;
          }
        } catch (e) {
          debugPrint('Ошибка парсинга тела ошибки getUploadedMaps: $e');
        }
        throw Exception(errorMessage);
      }
    } catch (e) {
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
        String errorMessage = 'Failed to upload map';
        try {
          final errorBody = jsonDecode(utf8.decode(resp.bodyBytes));
          errorMessage = errorBody['error']?.toString() ?? errorMessage;
          if (errorMessage == 'Failed to upload map') {
            errorMessage = errorBody['message']?.toString() ?? errorMessage;
          }
        } catch (e) {
          debugPrint('Ошибка парсинга тела ошибки uploadMap: $e');
        }
        throw Exception(errorMessage);
      }
    } catch (e) {
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
        String errorMessage = 'Failed to delete map';
        try {
          final errorBody = jsonDecode(utf8.decode(response.bodyBytes));
          errorMessage = errorBody['error']?.toString() ?? errorMessage;
          if (errorMessage == 'Failed to delete map') {
            errorMessage = errorBody['message']?.toString() ?? errorMessage;
          }
        } catch (e) {
          debugPrint('Ошибка парсинга тела ошибки deleteMap: $e');
        }
        throw Exception(errorMessage);
      }
    } catch (e) {
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
        String errorMessage = 'Failed to load map by ID';
        try {
          final errorBody = jsonDecode(utf8.decode(response.bodyBytes));
          errorMessage = errorBody['error']?.toString() ?? errorMessage;
          if (errorMessage == 'Failed to load map by ID') {
            errorMessage = errorBody['message']?.toString() ?? errorMessage;
          }
        } catch (e) {
          debugPrint('Ошибка парсинга тела ошибки getMapById: $e');
        }
        throw Exception(errorMessage);
      }
    } catch (e) {
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
      throw Exception('Ошибка: $message');
    }
  }

  Future<List<dynamic>> getShiftsByDate(String token, String date) async {
    final response = await _authorizedRequest((token) async {
      return await http.get(
        Uri.parse('${AppConfig.apiBaseUrl}/shifts/date/$date'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );
    }, token);
    if (response.statusCode == 200) {
      final dynamic body = jsonDecode(utf8.decode(response.bodyBytes));
      if (body is List) return body.cast<dynamic>();
      return [];
    } else {
      throw Exception(
          'Не удалось загрузить смены за $date: ${response.statusCode} - ${utf8.decode(response.bodyBytes)}');
    }
  }

  Future<List<String>> getAvailableTimeSlotsForStart(String token) async {
    final response = await _authorizedRequest((token) async {
      return await http.get(
        Uri.parse('${AppConfig.apiBaseUrl}/time-slots/available-for-start'),
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
      String errorMessage = 'Failed to load available time slots';
      try {
        final errorBody = jsonDecode(utf8.decode(response.bodyBytes));
        errorMessage = errorBody['error']?.toString() ?? errorMessage;
        if (errorMessage == 'Failed to load available time slots') {
          errorMessage = errorBody['message']?.toString() ?? errorMessage;
        }
      } catch (e) {
        debugPrint(
            'Ошибка парсинга тела ошибки getAvailableTimeSlotsForStart: $e');
      }
      throw Exception(errorMessage);
    }
  }

  Future<Map<String, dynamic>> getDailyPromoCodes(String token) async {
    final response = await _authorizedRequest((token) async {
      return await http.get(
        Uri.parse('${AppConfig.apiBaseUrl}/promo/daily'),
        headers: {'Authorization': 'Bearer $token'},
      );
    }, token);

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception('Не удалось загрузить промокоды');
    }
  }

  Future<void> claimDailyPromo(String token, String promoId) async {
    final response = await _authorizedRequest((token) async {
      return await http.post(
        Uri.parse('${AppConfig.apiBaseUrl}/promo/claim'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'promo_id': promoId}),
      );
    }, token);

    if (response.statusCode != 200) {
      throw Exception('Не удалось получить промокод');
    }
  }
}
