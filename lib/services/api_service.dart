import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:micro_mobility_app/models/active_shift.dart' as active_shift;
import '../models/shift_data.dart' as shift_data;

class ApiService {
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

        // Более безопасная обработка данных
        if (body is List) {
          List<shift_data.ShiftData> shifts = [];
          for (var item in body) {
            try {
              if (item is Map<String, dynamic>) {
                shifts.add(shift_data.ShiftData.fromJson(item));
              }
            } catch (e) {
              print('Error parsing shift item: $e');
              continue;
            }
          }
          return shifts;
        }
        return [];
      } else {
        print('Shifts API error: ${response.statusCode} - ${response.body}');
        throw Exception(
            'Failed to load shifts: ${response.statusCode} - ${utf8.decode(response.bodyBytes)}');
      }
    } catch (e) {
      print('Network error in getShifts: $e');
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

      // Проверяем существование файла перед добавлением
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

  Future<active_shift.ActiveShift?> getActiveShift(String token) async {
    final shifts = await getActiveShifts(token);
    return shifts.isNotEmpty ? shifts.first : null;
  }

  Future<List<active_shift.ActiveShift>> getActiveShifts(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/shifts/active'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      if (response.body == 'null' || response.body.isEmpty) {
        return [];
      }

      final dynamic body = jsonDecode(response.body);
      if (body is List) {
        List<active_shift.ActiveShift> shifts = [];
        for (var item in body) {
          try {
            if (item is Map<String, dynamic>) {
              shifts.add(active_shift.ActiveShift.fromJson(item));
            }
          } catch (e) {
            print('Error parsing active shift item: $e');
            continue;
          }
        }
        return shifts;
      }
      return [];
    } else {
      throw Exception(
          'Failed to load active shifts: ${response.statusCode} - ${utf8.decode(response.bodyBytes)}');
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
}
