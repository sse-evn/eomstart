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
      'start_time': startTime?.toIso8601String(),
      'is_active': isActive,
      'selfie': selfie,
    };
  }
}

String extractTimeFromIsoString(String? isoString) {
  if (isoString == null || isoString.isEmpty) return '...';
  final RegExp timeRegex = RegExp(r'T(\d{2}:\d{2})');
  final Match? match = timeRegex.firstMatch(isoString);
  if (match != null) {
    return match.group(1)!;
  } else {
    try {
      final parts = isoString.split('T');
      if (parts.length > 1) {
        final timePartWithTz = parts[1];
        final timePart = timePartWithTz.split(RegExp(r'[+Z]'))[0];
        final timeComponents = timePart.split(':');
        if (timeComponents.length >= 2) {
          return '${timeComponents[0]}:${timeComponents[1]}';
        }
      }
    } catch (e) {}
    return '...';
  }
}
