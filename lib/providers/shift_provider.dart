// lib/providers/shift_provider.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart'; // Для XFile
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Импорты моделей
import 'package:micro_mobility_app/models/active_shift.dart'
    as model; // Импорт модели ActiveShift
import '../models/shift_data.dart'; // Импорт модели ShiftData
// Импорт сервиса
import '../services/api_service.dart'; // Импорт ApiService

class ShiftProvider with ChangeNotifier {
  final ApiService _apiService;
  final FlutterSecureStorage _storage;
  final SharedPreferences _prefs;

  String? _token;
  model.ActiveShift? _activeShift;
  List<ShiftData> _shiftHistory = [];
  DateTime _selectedDate = DateTime.now();
  Timer? _timer;

  ShiftProvider({
    required ApiService apiService,
    required FlutterSecureStorage storage,
    required SharedPreferences prefs,
    String? initialToken,
  })  : _apiService = apiService,
        _storage = storage,
        _prefs = prefs {
    _token = initialToken;
    _initializeShiftProvider();
  }

  Future<void> _initializeShiftProvider() async {
    if (_token == null) {
      _token = await _storage.read(key: 'jwt_token');
    }
    await loadShifts();
  }

  void _startTimer() {
    _timer?.cancel();
    if (_activeShift?.startTime != null) {
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        notifyListeners(); // Обновляем UI каждую секунду для таймера
      });
    }
  }

  Future<void> setToken(String token) async {
    _token = token;
    await _storage.write(key: 'jwt_token', value: token);
    await _initializeShiftProvider();
  }

  model.ActiveShift? get activeShift => _activeShift;
  List<ShiftData> get shiftHistory => _shiftHistory;
  DateTime get selectedDate => _selectedDate;

  String get formattedWorkTime {
    if (_activeShift?.startTime == null) return '0ч 0мин';
    final duration = DateTime.now().difference(_activeShift!.startTime!);
    final h = duration.inHours;
    final m = (duration.inMinutes % 60);
    return '${h}ч ${m}мин';
  }

  Future<void> loadShifts() async {
    if (_token == null) {
      // Если токена нет, сбрасываем данные
      _shiftHistory = [];
      _activeShift = null;
      _timer?.cancel();
      notifyListeners();
      return;
    }

    try {
      // --- Загрузка истории смен ---
      final dynamic shiftsData = await _apiService.getShifts(_token!);
      if (shiftsData is List) {
        // Более безопасный парсинг списка ShiftData
        _shiftHistory = shiftsData
            .whereType<Map<String, dynamic>>() // Фильтруем только Map
            .map((json) => ShiftData.fromJson(json)) // Парсим из Json
            .toList();
      } else {
        _shiftHistory = [];
      }

      // --- Загрузка активной смены ---
      final activeShift = await _apiService.getActiveShift(_token!);
      _activeShift = activeShift;

      // --- Управление таймером ---
      if (activeShift != null) {
        _startTimer(); // Запускаем таймер, если есть активная смена
      } else {
        _timer?.cancel(); // Останавливаем таймер, если смены нет
      }

      notifyListeners(); // Уведомляем слушателей об изменении данных
    } catch (e) {
      debugPrint('ShiftProvider.loadShifts error: $e');
      // В случае ошибки (например, сети) сбрасываем данные
      _shiftHistory = [];
      _activeShift = null;
      _timer?.cancel();
      notifyListeners();
      // Не пробрасываем ошибку дальше, чтобы не ломать UI
    }
  }

  void selectDate(DateTime date) {
    _selectedDate = DateTime(date.year, date.month, date.day);
    notifyListeners();
  }

  /// Начало новой смены
  Future<void> startSlot({
    required String slotTimeRange,
    required String position,
    required String zone,
    required XFile selfie, // Принимаем XFile напрямую
  }) async {
    // Предотвращаем множественный запуск
    if (_activeShift != null) {
      debugPrint('ShiftProvider: Cannot start slot, already active.');
      return;
    }
    if (_token == null) {
      debugPrint('ShiftProvider: Cannot start slot, no token.');
      throw Exception('Токен не установлен');
    }

    // Преобразуем XFile в File для передачи в API
    final File imageFile = File(selfie.path);

    try {
      await _apiService.startSlot(
        token: _token!,
        slotTimeRange: slotTimeRange,
        position: position,
        zone: zone,
        selfieImage: imageFile,
      );
      debugPrint('ShiftProvider: Slot started successfully.');

      // Перезагружаем данные смен (историю и активную)
      // Используем unawaited, чтобы не блокировать UI
      unawaited(loadShifts());
    } catch (e) {
      debugPrint('ShiftProvider.startSlot error: $e');
      rethrow; // Пробрасываем ошибку, чтобы её можно было обработать в UI
    }
  }

  /// Завершение текущей смены
  Future<void> endSlot() async {
    if (_token == null) {
      debugPrint('ShiftProvider: Cannot end slot, no token.');
      throw Exception('Токен не установлен');
    }
    if (_activeShift == null) {
      debugPrint('ShiftProvider: Cannot end slot, no active shift.');
      return; // Нечего завершать
    }

    try {
      await _apiService.endSlot(_token!);
      debugPrint('ShiftProvider: Slot ended successfully.');

      // Перезагружаем данные смен
      unawaited(loadShifts());
    } catch (e) {
      debugPrint('ShiftProvider.endSlot error: $e');
      rethrow; // Пробрасываем ошибку
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
