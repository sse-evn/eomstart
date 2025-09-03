// // lib/services/auto_export_service.dart

// import 'dart:async';
// import 'dart:io';
// import 'package:flutter/material.dart';
// import 'package:flutter_local_notifications/flutter_local_notifications.dart';
// import 'package:shared_preferences/shared_preferences.dart';
// import 'package:micro_mobility_app/config/google_sheets_config.dart';
// import 'package:micro_mobility_app/screens/admin/shift_history_screen.dart';
// import 'package:micro_mobility_app/services/api_service.dart';

// class AutoExportService {
//   static final AutoExportService _instance = AutoExportService._internal();
//   factory AutoExportService() => _instance;
//   AutoExportService._internal();

//   late SharedPreferences _prefs;
//   late Timer _timer;
//   late ApiService _apiService;

//   Future<void> init() async {
//     _prefs = await SharedPreferences.getInstance();
//     _apiService = ApiService();

//     // Проверяем, запускалась ли уже сегодня
//     final lastRun = _prefs.getString('last_auto_export');
//     final now = DateTime.now().toUtc().toString();

//     if (lastRun == null || !now.startsWith(lastRun.split(' ')[0])) {
//       _startTimer();
//     }
//   }

//   void _startTimer() {
//     // Запускаем раз в 24 часа в 00:30
//     final now = DateTime.now();
//     final nextRun = DateTime(now.year, now.month, now.day, 0, 30);
//     if (now.isAfter(nextRun)) {
//       nextRun.add(const Duration(days: 1));
//     }

//     final duration = nextRun.difference(now);
//     _timer = Timer(duration, _runExport);
//   }

//   void _runExport() async {
//     try {
//       final shifts =
//           await _apiService.getEndedShifts('fake_token'); // замени на реальный
//       if (shifts.isEmpty) {
//         debugPrint('Нет данных для выгрузки');
//         return;
//       }

//       // Здесь должен быть вызов функции экспорта
//       // Например, через HTTP или через ваш сервис
//       debugPrint('Автоматическая выгрузка запущена');

//       // Сохраняем время последнего запуска
//       final now = DateTime.now().toUtc().toString();
//       await _prefs.setString('last_auto_export', now);

//       // Уведомление
//       final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
//       const AndroidInitializationSettings androidInitializationSettings =
//           AndroidInitializationSettings('@mipmap/ic_launcher');
//       const InitializationSettings initializationSettings =
//           InitializationSettings(android: androidInitializationSettings);
//       await flutterLocalNotificationsPlugin.initialize(initializationSettings);

//       const NotificationDetails notificationDetails = NotificationDetails(
//         android: AndroidNotificationDetails(
//           'channel_id',
//           'Channel name',
//           importance: Importance.high,
//           priority: Priority.high,
//         ),
//       );

//       await flutterLocalNotificationsPlugin.show(
//         0,
//         'Автоматическая выгрузка',
//         'Данные успешно отправлены в Google Таблицы',
//         notificationDetails,
//       );
//     } catch (e) {
//       debugPrint('Ошибка автозагрузки: $e');
//     }
//   }

//   void dispose() {
//     _timer?.cancel();
//   }
// }
