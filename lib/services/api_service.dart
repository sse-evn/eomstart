// lib/services/api_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:micro_mobility_app/models/active_shift.dart' as active_shift;
import '../models/shift_data.dart' as shift_data;

class ApiService {
  // 🔴 ВАЖНО: УБРАНЫ ПРОБЕЛЫ В КОНЦЕ URL!
  static const String baseUrl = 'https://eom-sharing.duckdns.org/api';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<Map<String, dynamic>> getUserProfile(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/profile'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception(
          'Failed to load profile: ${response.statusCode} - ${utf8.decode(response.bodyBytes)}');
    }
  }

  Future<void> forceEndShift(String token, int userId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/admin/users/$userId/end-shift'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode != 200 && response.statusCode != 204) {
      final message = utf8.decode(response.bodyBytes);
      throw Exception(
          'Failed to force end shift: ${response.statusCode} — $message');
    }
  }

  Future<void> logout(String token) async {
    await http.post(
      Uri.parse('$baseUrl/logout'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
  }

  Future<List<dynamic>> getAdminUsers(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/admin/users'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final dynamic body = jsonDecode(response.body);
      if (body is List) {
        return body;
      }
      return [];
    } else {
      throw Exception(
          'Failed to load users: ${response.statusCode} - ${utf8.decode(response.bodyBytes)}');
    }
  }

  Future<void> updateUserRole(String token, int userId, String newRole) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/admin/users/$userId/role'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'role': newRole}),
    );

    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception(
          'Failed to update role: ${response.statusCode} - ${utf8.decode(response.bodyBytes)}');
    }
  }

  Future<void> createUser(
      String token, String username, String firstName) async {
    final response = await http.post(
      Uri.parse('$baseUrl/admin/users'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'username': username,
        'first_name': firstName,
      }),
    );

    if (response.statusCode != 201) {
      throw Exception('Ошибка: ${utf8.decode(response.bodyBytes)}');
    }
  }

  Future<void> deleteUser(String token, int userId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/admin/users/$userId'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception(
          'Failed to delete user: ${response.statusCode} - ${utf8.decode(response.bodyBytes)}');
    }
  }

  Future<void> activateUser(String token, int userId) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/admin/users/$userId/status'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'is_active': true}),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to activate user');
    }
  }

  Future<void> deactivateUser(String token, int userId) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/admin/users/$userId/status'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'is_active': false}),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to deactivate user');
    }
  }

  Future<List<shift_data.ShiftData>> getShifts(String token) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/shifts'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final dynamic body = jsonDecode(response.body);
        if (body is List) {
          return body
              .whereType<Map<String, dynamic>>()
              .map((item) => shift_data.ShiftData.fromJson(item))
              .toList();
        }
        return [];
      } else if (response.statusCode == 401) {
        // Пробуем обновить токен
        final newToken = await refreshToken();
        if (newToken != null) {
          return await getShifts(newToken); // Повторяем запрос
        } else {
          throw Exception('Session expired. Please login again.');
        }
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
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/slot/start'),
      );

      request.headers['Authorization'] = 'Bearer $token';
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
      print(
          'Start slot response: ${resp.statusCode} - ${utf8.decode(resp.bodyBytes)}');

      if (resp.statusCode != 200 && resp.statusCode != 201) {
        throw Exception(
            'Failed to start slot: ${resp.reasonPhrase} - ${utf8.decode(resp.bodyBytes)}');
      }
    } catch (e) {
      print('Error in startSlot: $e');
      rethrow;
    }
  }

  Future<void> endSlot(String token) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/slot/end'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode != 200 && response.statusCode != 204) {
        throw Exception(
            'Failed to end slot: ${response.statusCode} - ${utf8.decode(response.bodyBytes)}');
      }
    } catch (e) {
      print('Error in endSlot: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> login(String username, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'password': password,
      }),
    );

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;

      // Сохраняем ОБА токена
      await _storage.write(
          key: 'jwt_token', value: body['token']); // access_token
      await _storage.write(key: 'refresh_token', value: body['refresh_token']);

      return body;
    } else {
      throw Exception('Ошибка авторизации: ${response.statusCode}');
    }
  }

// В ApiService.dart
  Future<String?> refreshToken() async {
    final refreshToken = await _storage.read(key: 'refresh_token');
    if (refreshToken == null) return null;

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': refreshToken}),
      );

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final newAccessToken = body['access_token'];
        if (newAccessToken != null) {
          await _storage.write(key: 'jwt_token', value: newAccessToken);
          return newAccessToken;
        }
      }
    } catch (e) {
      debugPrint('Refresh failed: $e');
    }
    return null;
  }

// В api_service.dart
  Future<active_shift.ActiveShift?> getActiveShift(String token) async {
    final response = await http.get(
      Uri.parse(
          '$baseUrl/shifts/active'), // Этот endpoint возвращает ОДИН объект
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    debugPrint('📡 GetUserActiveShift API status: ${response.statusCode}');
    debugPrint('📡 GetUserActiveShift API body: ${response.body}');

    if (response.statusCode == 200) {
      // Проверяем на "null" или пустое тело
      if (response.body == 'null' || response.body.trim().isEmpty) {
        debugPrint('📡 No active shift found (null response)');
        return null;
      }

      try {
        final dynamic body = jsonDecode(response.body);

        // Если это объект - создаем ActiveShift
        if (body is Map<String, dynamic>) {
          debugPrint('✅ Parsed single active shift object');
          return active_shift.ActiveShift.fromJson(body);
        }
        // Если это массив с одним элементом - берем первый
        else if (body is List &&
            body.isNotEmpty &&
            body[0] is Map<String, dynamic>) {
          debugPrint('✅ Parsed active shift from array[0]');
          return active_shift.ActiveShift.fromJson(body[0]);
        }
        // Если пустой массив
        else if (body is List && body.isEmpty) {
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

  /// Получение списка заданий, назначенных текущему пользователю
  Future<List<dynamic>> getMyTasks({required String token}) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/my/tasks'), // ✅ Правильный маршрут
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final dynamic body = jsonDecode(response.body);
        if (body is List) {
          return body;
        }
        return [];
      } else {
        throw Exception(
            'Failed to load my tasks: ${response.statusCode} - ${utf8.decode(response.bodyBytes)}');
      }
    } catch (e) {
      debugPrint('Error in getMyTasks: $e');
      rethrow;
    }
  }

// Этот метод для получения ВСЕХ активных смен (для админов)
  Future<List<active_shift.ActiveShift>> getActiveShifts(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/admin/shifts/active'), // Другой endpoint!
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    debugPrint('📡 GetActiveShifts API status: ${response.statusCode}');
    debugPrint('📡 GetActiveShifts API body: ${response.body}');

    if (response.statusCode == 200) {
      if (response.body == 'null' || response.body.trim().isEmpty) {
        return [];
      }

      try {
        final dynamic body = jsonDecode(response.body);

        // Ожидаем массив
        if (body is List) {
          List<active_shift.ActiveShift> shifts = [];
          for (var item in body) {
            if (item is Map<String, dynamic>) {
              shifts.add(active_shift.ActiveShift.fromJson(item));
            }
          }
          debugPrint('✅ Parsed ${shifts.length} active shifts');
          return shifts;
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

  Future<List<String>> getAvailablePositions(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/slots/positions'), // предполагаемый эндпоинт
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

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
    final response = await http.get(
      Uri.parse('$baseUrl/slots/times'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

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
    final response = await http.get(
      Uri.parse('$baseUrl/slots/zones'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final dynamic body = jsonDecode(response.body);
      if (body is List) {
        return body.map((e) => e.toString()).toList();
      }
      return [];
    } else {
      throw Exception(
          'Failed to load zones: ${response.statusCode} - ${utf8.decode(response.bodyBytes)}');
    }
  }

  // === НОВЫЕ МЕТОДЫ ДЛЯ РАБОТЫ С ЗАДАНИЯМИ ===

  /// Получение списка всех заданий
  Future<List<dynamic>> getTasks({
    required String token,
    String? adminUsername,
  }) async {
    try {
      // Создаем URI с параметрами запроса
      final uri = Uri.parse('$baseUrl/admin/tasks');
      final queryParams = <String, String>{};

      if (adminUsername != null && adminUsername.isNotEmpty) {
        queryParams['admin_username'] = adminUsername;
      }

      final finalUri = uri.replace(queryParameters: queryParams);

      final response = await http.get(
        finalUri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final dynamic body = jsonDecode(response.body);
        if (body is List) {
          return body;
        }
        return [];
      } else {
        throw Exception(
            'Failed to load tasks: ${response.statusCode} - ${utf8.decode(response.bodyBytes)}');
      }
    } catch (e) {
      debugPrint('Error loading tasks: $e');
      rethrow;
    }
  }

  /// Создание нового задания
  Future<void> createTask({
    required String token,
    required String assigneeUsername,
    required String title,
    required String description,
    required String priority,
    DateTime? deadline,
    File? image,
  }) async {
    try {
      if (image != null) {
        // Если есть изображение, используем multipart request
        final request = http.MultipartRequest(
          'POST',
          Uri.parse('$baseUrl/admin/tasks'),
        );

        request.headers['Authorization'] = 'Bearer $token';

        // Добавляем текстовые поля
        request.fields['assignee_username'] = assigneeUsername;
        request.fields['title'] = title;
        request.fields['description'] = description;
        request.fields['priority'] = priority;
        if (deadline != null) {
          request.fields['deadline'] = deadline.toIso8601String();
        }

        // Добавляем изображение
        if (await image.exists()) {
          request.files.add(
            await http.MultipartFile.fromPath('image', image.path),
          );
        }

        final response = await request.send();
        final resp = await http.Response.fromStream(response);

        if (resp.statusCode != 200 && resp.statusCode != 201) {
          throw Exception(
              'Failed to create task: ${resp.statusCode} - ${utf8.decode(resp.bodyBytes)}');
        }
      } else {
        // Если нет изображения, используем обычный POST
        final response = await http.post(
          Uri.parse('$baseUrl/admin/tasks'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'assignee_username': assigneeUsername,
            'title': title,
            'description': description,
            'priority': priority,
            if (deadline != null) 'deadline': deadline.toIso8601String(),
          }),
        );

        if (response.statusCode != 200 && response.statusCode != 201) {
          throw Exception(
              'Failed to create task: ${response.statusCode} - ${utf8.decode(response.bodyBytes)}');
        }
      }
    } catch (e) {
      debugPrint('Error creating task: $e');
      rethrow;
    }
  }

  /// Обновление статуса задания
  Future<void> updateTaskStatus({
    required String token,
    required int taskId,
    required String status,
  }) async {
    try {
      final response = await http.patch(
        Uri.parse('$baseUrl/admin/tasks/$taskId/status'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'status': status}),
      );

      if (response.statusCode != 200) {
        throw Exception(
            'Failed to update task status: ${response.statusCode} - ${utf8.decode(response.bodyBytes)}');
      }
    } catch (e) {
      debugPrint('Error updating task status: $e');
      rethrow;
    }
  }

  /// Удаление задания
  Future<void> deleteTask({
    required String token,
    required int taskId,
  }) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/admin/tasks/$taskId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode != 200 && response.statusCode != 204) {
        throw Exception(
            'Failed to delete task: ${response.statusCode} - ${utf8.decode(response.bodyBytes)}');
      }
    } catch (e) {
      debugPrint('Error deleting task: $e');
      rethrow;
    }
  }

  // === НОВЫЕ МЕТОДЫ ДЛЯ РАБОТЫ С КАРТАМИ ===

  /// Получение списка всех загруженных карт
  Future<List<dynamic>> getUploadedMaps(String token) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/admin/maps'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final dynamic body = jsonDecode(response.body);
        if (body is List) {
          return body;
        }
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

  /// Загрузка новой карты на сервер
  Future<void> uploadMap({
    required String token,
    required String city,
    required String description,
    required File geoJsonFile,
  }) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/admin/maps/upload'),
      );

      request.headers['Authorization'] = 'Bearer $token';

      // Добавляем текстовые поля
      request.fields['city'] = city;
      request.fields['description'] = description;

      // Добавляем файл GeoJSON
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

  /// Удаление карты с сервера
  Future<void> deleteMap({
    required String token,
    required int mapId,
  }) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/admin/maps/$mapId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode != 200 && response.statusCode != 204) {
        throw Exception(
            'Failed to delete map: ${response.statusCode} - ${utf8.decode(response.bodyBytes)}');
      }
    } catch (e) {
      debugPrint('Error deleting map: $e');
      rethrow;
    }
  }

  /// Получение карты по ID для просмотра
  Future<Map<String, dynamic>> getMapById({
    required String token,
    required int mapId,
  }) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/admin/maps/$mapId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

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
}
