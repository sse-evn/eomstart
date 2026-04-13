import 'package:intl/intl.dart';

class TimeUtils {
  static String formatTime(String? isoString) {
    if (isoString == null || isoString.isEmpty) return '— : —';
    try {
      final dateTime = DateTime.parse(isoString).toLocal();
      return DateFormat('HH:mm').format(dateTime);
    } catch (e) {
      return '— : —';
    }
  }

  static String formatDate(String? isoString) {
    if (isoString == null || isoString.isEmpty) return '';
    try {
      final dateTime = DateTime.parse(isoString).toLocal();
      return DateFormat('dd.MM.yyyy').format(dateTime);
    } catch (e) {
      return '';
    }
  }
}

String extractTimeFromIsoString(String? isoString) {
  return TimeUtils.formatTime(isoString);
}

String extractDateFromIsoString(String? isoString) {
  return TimeUtils.formatDate(isoString);
}

class BreakTimeUtils {
  static final List<Map<String, String>> scheduledBreaks = [
    {'start': '10:00', 'end': '10:40', 'label': 'Утренний перерыв 1'},
    {'start': '10:40', 'end': '11:20', 'label': 'Утренний перерыв 2'},
    {'start': '14:00', 'end': '14:40', 'label': 'Обеденный перерыв'},
    {'start': '19:00', 'end': '19:40', 'label': 'Вечерний перерыв 1'},
    {'start': '19:40', 'end': '20:20', 'label': 'Вечерний перерыв 2'},
  ];

  static Map<String, dynamic> getBreakStatus() {
    final now = DateTime.now();
    final hour = now.hour;
    final minute = now.minute;
    final currentTimeMinutes = hour * 60 + minute;

    for (var b in scheduledBreaks) {
      final startParts = b['start']!.split(':');
      final endParts = b['end']!.split(':');
      final startMinutes = int.parse(startParts[0]) * 60 + int.parse(startParts[1]);
      final endMinutes = int.parse(endParts[0]) * 60 + int.parse(endParts[1]);

      if (currentTimeMinutes >= startMinutes && currentTimeMinutes < endMinutes) {
        return {
          'isInside': true,
          'label': b['label'],
          'range': '${b['start']} - ${b['end']}',
          'remainingMinutes': endMinutes - currentTimeMinutes,
        };
      }
    }

    // Find next break
    for (var b in scheduledBreaks) {
      final startParts = b['start']!.split(':');
      final startMinutes = int.parse(startParts[0]) * 60 + int.parse(startParts[1]);
      if (startMinutes > currentTimeMinutes) {
        return {
          'isInside': false,
          'label': 'Следующий перерыв',
          'range': '${b['start']} - ${b['end']}',
          'startsInMinutes': startMinutes - currentTimeMinutes,
        };
      }
    }

    return {
      'isInside': false,
      'label': 'Перерывы на сегодня окончены',
      'range': '',
    };
  }

  static String getCurrentBreakTime() {
    final status = getBreakStatus();
    if (status['isInside'] == true) {
      return status['range'];
    }
    return ''; // Возвращаем пустоту, если сейчас не время перерыва
  }

  static DateTime? getSlotEndTime(String slotRange, {DateTime? shiftStartTime}) {
    if (slotRange.isEmpty || !slotRange.contains('-')) return null;
    try {
      final parts = slotRange.split('-');
      if (parts.length < 2) return null;
      final endTimeToken = parts[1].trim();
      final timeParts = endTimeToken.split(':');
      if (timeParts.length < 2) return null;
      
      final hour = int.parse(timeParts[0]);
      final minute = int.parse(timeParts[1]);
      
      // Используем дату начала смены как базу
      final baseDate = shiftStartTime ?? DateTime.now();
      var end = DateTime(baseDate.year, baseDate.month, baseDate.day, hour, minute);
      
      final startTimeToken = parts[0].trim();
      final startTimeParts = startTimeToken.split(':');
      final startHour = int.parse(startTimeParts[0]);
      final startMinute = int.parse(startTimeParts[1]);
      final start = DateTime(baseDate.year, baseDate.month, baseDate.day, startHour, startMinute);
      
      if (end.isBefore(start)) {
        // Слот переходит через полночь
        end = end.add(const Duration(days: 1));
      }
      
      return end;
    } catch (e) {
      return null;
    }
  }

  static bool isSlotExpired(String slotRange, {DateTime? shiftStartTime}) {
    final endTime = getSlotEndTime(slotRange, shiftStartTime: shiftStartTime);
    if (endTime == null) return false;
    // Буфер в 1 минуту
    return DateTime.now().isAfter(endTime.add(const Duration(minutes: 1)));
  }
}
