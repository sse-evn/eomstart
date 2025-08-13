import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:micro_mobility_app/models/active_shift.dart';
import '../models/shift_data.dart';

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
      return jsonDecode(response.body) as List<dynamic>;
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
        'firstName': firstName,
      }),
    );

    if (response.statusCode != 201 && response.statusCode != 200) {
      throw Exception(
          'Failed to create user: ${utf8.decode(response.bodyBytes)}');
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

  Future<List<ShiftData>> getShifts(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/shifts'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final List<dynamic> jsonList = jsonDecode(response.body);
      return jsonList.map((json) => ShiftData.fromJson(json)).toList();
    } else {
      throw Exception(
          'Failed to load shifts: ${response.statusCode} - ${utf8.decode(response.bodyBytes)}');
    }
  }

  Future<void> startSlot({
    required String token,
    required String slotTimeRange,
    required String position,
    required String zone,
    required File selfieImage,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/slot/start'),
    );

    request.headers['Authorization'] = 'Bearer $token';
    request.fields['slot_time_range'] = slotTimeRange;
    request.fields['position'] = position;
    request.fields['zone'] = zone;
    request.files
        .add(await http.MultipartFile.fromPath('selfie', selfieImage.path));

    final response = await request.send();
    final resp = await http.Response.fromStream(response);

    if (resp.statusCode != 200 && resp.statusCode != 201) {
      throw Exception(
          'Failed to start slot: ${resp.reasonPhrase} - ${utf8.decode(resp.bodyBytes)}');
    }
  }

  Future<void> endSlot(String token) async {
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
  }

  Future<ActiveShift?> getActiveShift(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/shifts/active'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data == null) return null;
      if (data is Map<String, dynamic>) {
        return ActiveShift.fromJson(data);
      }
      throw Exception('Invalid response format: expected object or null');
    } else {
      throw Exception(
        'Failed to load active shift: ${response.statusCode} - ${utf8.decode(response.bodyBytes)}',
      );
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
      final List<dynamic> body = jsonDecode(response.body);
      return body.map((e) => e.toString()).toList();
    } else {
      throw Exception(
        'Failed to load time slots: ${response.statusCode} - ${utf8.decode(response.bodyBytes)}',
      );
    }
  }

  Future<List<String>> getAvailablePositions(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/slots/positions'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final List<dynamic> body = jsonDecode(response.body);
      return body.map((e) => e.toString()).toList();
    } else {
      throw Exception(
        'Failed to load positions: ${response.statusCode} - ${utf8.decode(response.bodyBytes)}',
      );
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
      final List<dynamic> body = jsonDecode(response.body);
      return body.map((e) => e.toString()).toList();
    } else {
      throw Exception(
        'Failed to load zones: ${response.statusCode} - ${utf8.decode(response.bodyBytes)}',
      );
    }
  }
}
