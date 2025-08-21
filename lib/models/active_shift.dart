// lib/models/active_shift.dart
import 'package:flutter/material.dart' show debugPrint;

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
  final String? endTimeString; // Новое поле
  final DateTime? endTime; // Используется в UI

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

  factory ActiveShift.fromJson(Map<String, dynamic> json) {
    String? originalStartTimeStr;
    DateTime? parsedStartTime;

    if (json['start_time'] != null) {
      originalStartTimeStr = json['start_time'].toString();
      try {
        parsedStartTime = DateTime.parse(originalStartTimeStr);
      } catch (e) {
        parsedStartTime = null;
      }
    }

    String? originalEndTimeStr;
    DateTime? parsedEndTime;

    if (json['end_time'] != null) {
      originalEndTimeStr = json['end_time'].toString();
      try {
        parsedEndTime = DateTime.parse(originalEndTimeStr);
      } catch (e) {
        parsedEndTime = null;
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
      startTimeString: originalStartTimeStr,
      startTime: parsedStartTime,
      isActive: json['is_active'] is bool
          ? json['is_active'] as bool
          : (json['is_active']?.toString().toLowerCase() == 'true'),
      endTimeString: originalEndTimeStr,
      endTime: parsedEndTime,
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
      'start_time': startTime?.toIso8601String(), // ✅ исправлено
      'end_time': endTime?.toIso8601String(), // ✅ исправлено
      'is_active': isActive,
      'selfie': selfie,
    };
  }
}
