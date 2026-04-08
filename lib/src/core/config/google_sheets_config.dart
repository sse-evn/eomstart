// lib/config/google_sheets_config.dart

import 'package:flutter/material.dart';

class GoogleSheetsConfig {
  // 🔗 URL Google Apps Script (всегда должен быть один)
  static const String googleSheetUrl =
      'https://script.google.com/macros/s/AKfycbysUFcRsG-LLf34s6nOtt6OKJowbuOzfvxV6djDcC9j2JtBwupRDgAjkAKnVi3ZK6C1yw/exec';

  // 💵 Валюта
  static const String currency = '₸';

  // 🕰️ Время автоматической выгрузки (по серверному времени)
  static const int autoExportHour = 0; // 0 = 00:00
  static const int autoExportMinute = 30; // 30 минут

  // 💰 Ставка за час (8 часов = 10 000 ₸)
  static const double hourlyRate = 1250.0;

  // ✅ Удобный геттер: когда следующая выгрузка?
  static TimeOfDay get autoExportTimeOfDay =>
      const TimeOfDay(hour: autoExportHour, minute: autoExportMinute);

  // ✅ Проверка: совпадает ли текущее время с временем выгрузки?
  static bool isTimeForExport(DateTime now) {
    return now.hour == autoExportHour && now.minute == autoExportMinute;
  }
}
