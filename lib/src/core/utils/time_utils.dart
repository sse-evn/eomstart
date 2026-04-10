// lib/src/core/utils/time_utils.dart
import 'package:intl/intl.dart';

class TimeUtils {
  static String formatTime(String? isoString) {
    if (isoString == null || isoString.isEmpty) return '--:--';
    try {
      final dateTime = DateTime.parse(isoString).toLocal();
      return DateFormat('HH:mm').format(dateTime);
    } catch (e) {
      return '--:--';
    }
  }

  static String formatDate(String? isoString) {
    if (isoString == null || isoString.isEmpty) return '--.--.--';
    try {
      final dateTime = DateTime.parse(isoString).toLocal();
      return DateFormat('dd.MM.yy').format(dateTime);
    } catch (e) {
      return '--.--.--';
    }
  }

  static String formatFullDate(String? isoString) {
    if (isoString == null || isoString.isEmpty) return '--.--.----';
    try {
      final dateTime = DateTime.parse(isoString).toLocal();
      return DateFormat('dd.MM.yyyy').format(dateTime);
    } catch (e) {
      return '--.--.----';
    }
  }
}

// Keep old functions for compatibility
String extractTimeFromIsoString(String? isoString) => TimeUtils.formatTime(isoString);
String extractDateFromIsoString(String? isoString) => TimeUtils.formatDate(isoString);
