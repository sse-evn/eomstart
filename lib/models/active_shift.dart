// lib/models/active_shift.dart
import 'package:flutter/material.dart' show debugPrint;

class ActiveShift {
  final int id;
  final int userId;
  final String username;
  final String slotTimeRange;
  final String position;
  final String zone;

  /// Храним оригинальную строку времени от сервера для точного отображения
  final String? startTimeString;

  /// Храним DateTime для потенциальных расчетов (например, продолжительность)
  final DateTime? startTime;
  final bool isActive;
  final String selfie;

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
  });

  factory ActiveShift.fromJson(Map<String, dynamic> json) {
    debugPrint('🔧 ActiveShift.fromJson called with: $json');

    String? originalStartTimeStr;
    DateTime? parsedStartTime;

    if (json['start_time'] != null) {
      originalStartTimeStr = json['start_time'].toString();
      try {
        // Парсим для потенциальных расчетов (остается в UTC внутри Dart)
        parsedStartTime = DateTime.parse(originalStartTimeStr);
        debugPrint(
            '🕒 Parsed start_time for DateTime: $parsedStartTime (original: $originalStartTimeStr)');
      } catch (e) {
        debugPrint('❌ Error parsing start_time for DateTime: $e');
        parsedStartTime = null;
      }
    }

    return ActiveShift(
      id: json['id'] is int
          ? json['id'] as int
          : int.tryParse('${json['id']}') ?? 0,
      userId: json['user_id'] is int
          ? json['user_id'] as int
          : int.tryParse('${json['user_id']}') ?? 0,
      username: json['username']?.toString() ?? '',
      slotTimeRange: json['slot_time_range']?.toString() ?? '',
      position: json['position']?.toString() ?? '',
      zone: json['zone']?.toString() ?? '',
      selfie: json['selfie']?.toString() ?? '',
      startTimeString: originalStartTimeStr, // Сохраняем оригинальную строку
      startTime: parsedStartTime, // Сохраняем DateTime
      isActive: json['is_active'] is bool
          ? json['is_active'] as bool
          : (json['is_active']?.toString().toLowerCase() == 'true'),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'username': username,
      'slot_time_range': slotTimeRange,
      'position': position,
      'zone': zone,
      'start_time':
          startTime?.toIso8601String(), // Используем DateTime для сериализации
      'is_active': isActive,
      'selfie': selfie,
    };
  }
}

/// Вспомогательная функция для извлечения времени HH:MM из строки ISO 8601
/// Например, из "2025-08-14T09:46:53.633706464+05:00" извлекает "09:46"
String extractTimeFromIsoString(String? isoString) {
  if (isoString == null || isoString.isEmpty) return '...';

  // Регулярное выражение для поиска времени в формате HH:MM после 'T'
  final RegExp timeRegex = RegExp(r'T(\d{2}:\d{2})');
  final Match? match = timeRegex.firstMatch(isoString);

  if (match != null) {
    return match.group(1)!; // Возвращаем найденную группу (HH:MM)
  } else {
    // Если стандартный формат не подошел, попробуем просто последние 5 символов до '+', 'Z' или конца строки
    // Это менее надежно, но может помочь в некоторых случаях
    try {
      final parts = isoString.split('T');
      if (parts.length > 1) {
        final timePartWithTz = parts[1];
        // Убираем часть с часовым поясом (после '+' или 'Z')
        final timePart = timePartWithTz.split(RegExp(r'[+Z]'))[0];
        // Берем только HH:MM
        final timeComponents = timePart.split(':');
        if (timeComponents.length >= 2) {
          return '${timeComponents[0]}:${timeComponents[1]}';
        }
      }
    } catch (e) {
      debugPrint('Error in fallback time extraction: $e');
    }
    return '...';
  }
}
