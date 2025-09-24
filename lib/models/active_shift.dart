// lib/models/active_shift.dart
import 'package:flutter/material.dart' show debugPrint;
import 'dart:convert';

class ActiveShift {
  final int id;
  final int userId;

  final String username;
  final String slotTimeRange;
  final String position;
  final String zone;
  final String? startTimeString;
  final DateTime? startTime;
  final bool isActive;
  final String selfie;
  final String? endTimeString;
  final DateTime? endTime;

  ActiveShift({
    required this.id,
    required this.userId,
    required this.username,
    required this.slotTimeRange,
    required this.position,
    required this.zone,
    this.startTimeString,
    this.startTime,
    required this.isActive,
    required this.selfie,
    this.endTimeString,
    this.endTime,
  });

  /// Создаёт [ActiveShift] из JSON
  factory ActiveShift.fromJson(Map<String, dynamic> json) {
    // Парсинг startTime
    final startTimeStr = _extractString(json, 'start_time');
    final parsedStartTime = _parseDateTime(startTimeStr);

    // Парсинг endTime
    final endTimeStr = _extractString(json, 'end_time');
    final parsedEndTime = _parseDateTime(endTimeStr);

    // Парсинг ID
    final id = _parseInt(json['id'], 'id');
    final userId = _parseInt(json['user_id'], 'user_id');

    return ActiveShift(
      id: id,
      userId: userId,
      username: _extractString(json, 'username') ?? '',
      slotTimeRange: _extractString(json, 'slot_time_range') ?? '',
      position: _extractString(json, 'position') ?? '',
      zone: _extractString(json, 'zone') ?? '',
      selfie: _extractString(json, 'selfie') ?? '',
      startTimeString: startTimeStr,
      startTime: parsedStartTime,
      isActive: _parseBool(json['is_active']),
      endTimeString: endTimeStr,
      endTime: parsedEndTime,
    );
  }

  /// Экспортирует объект в JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'username': username,
      'slot_time_range': slotTimeRange,
      'position': position,
      'zone': zone,
      'start_time': startTime?.toIso8601String(),
      'end_time': endTime?.toIso8601String(),
      'is_active': isActive,
      'selfie': selfie,
    };
  }

  @override
  String toString() {
    return 'ActiveShift(id: $id, userId: $userId, username: $username, slotTimeRange: $slotTimeRange, position: $position, zone: $zone, startTime: $startTime, endTime: $endTime, isActive: $isActive)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ActiveShift &&
        id == other.id &&
        userId == other.userId &&
        username == other.username &&
        slotTimeRange == other.slotTimeRange &&
        position == other.position &&
        zone == other.zone &&
        startTimeString == other.startTimeString &&
        startTime == other.startTime &&
        endTimeString == other.endTimeString &&
        endTime == other.endTime &&
        isActive == other.isActive &&
        selfie == other.selfie;
  }

  @override
  int get hashCode {
    return Object.hash(
      id,
      userId,
      username,
      slotTimeRange,
      position,
      zone,
      startTimeString,
      startTime,
      endTimeString,
      endTime,
      isActive,
      selfie,
    );
  }

  // =============================
  // ВСПОМОГАТЕЛЬНЫЕ СТАТИЧЕСКИЕ МЕТОДЫ
  // =============================

  /// Извлекает строку из JSON, обрабатывает int/bool как строку
  static String? _extractString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) return null;
    return value.toString();
  }

  /// Парсит int, безопасно обрабатывает String
  static int _parseInt(dynamic value, String field) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is String) {
      final parsed = int.tryParse(value);
      if (parsed != null) return parsed;
      debugPrint('❌ ActiveShift: Не удалось распарсить $field: $value');
    }
    return 0;
  }

  /// Парсит bool (true/false, "true"/"false", 1/0)
  static bool _parseBool(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is String) {
      final lower = value.toLowerCase();
      return lower == 'true' || lower == '1' || lower == 'yes';
    }
    if (value is int) {
      return value != 0;
    }
    return false;
  }

  /// Парсит DateTime, логирует ошибки
  static DateTime? _parseDateTime(String? value) {
    if (value == null || value.isEmpty) return null;
    try {
      return DateTime.parse(value);
    } catch (e) {
      debugPrint('❌ ActiveShift: Ошибка парсинга времени: $value → $e');
      return null;
    }
  }
}
