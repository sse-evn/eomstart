// lib/utils/time_utils.dart
String extractTimeFromIsoString(String? isoString) {
  if (isoString == null || isoString.isEmpty) return '—:—';

  final RegExp timeRegex = RegExp(r'T(\d{2}:\d{2}(?::\d{2})?)');
  final Match? match = timeRegex.firstMatch(isoString);
  if (match != null) return match.group(1)!;

  try {
    final timePart = isoString.split('T').last.split(RegExp(r'[.\+Z]')).first;
    final parts = timePart.split(':');
    if (parts.length >= 2) {
      return '${parts[0]}:${parts[1]}';
    }
  } catch (e) {
    // ничего не делаем
  }

  return '—:—';
}

String extractDateFromIsoString(String? isoString) {
  if (isoString == null || isoString.isEmpty) return '—';

  try {
    final datePart = isoString.split('T').first;
    final parts = datePart.split('-');
    if (parts.length == 3) {
      return '${parts[2]}.${parts[1]}.${int.parse(parts[0]) % 100}'; // ДД.ММ.ГГ
    }
  } catch (e) {
    // ничего не делаем
  }

  return '—';
}
