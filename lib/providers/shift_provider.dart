// providers/shift_provider.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/shift_data.dart';
import '../services/api_service.dart';

class ShiftProvider with ChangeNotifier {
  final ApiService _apiService;
  final FlutterSecureStorage _storage;
  final SharedPreferences _prefs;

  String? _token;
  SlotState _slotState = SlotState.inactive;
  List<ShiftData> _shiftHistory = [];
  DateTime _selectedDate = DateTime.now();
  Timer? _timer;
  DateTime? _startTime; // Время начала активного слота

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
    print('✅ ShiftProvider: Инициализация...');

    if (_token == null) {
      _token = await _storage.read(key: 'jwt_token');
    }

    // Восстанавливаем startTime из SharedPreferences
    final String? savedStartTime = _prefs.getString('active_slot_start_time');
    final String? storedState = await _storage.read(key: 'slot_state');

    if (storedState == 'active' && savedStartTime != null) {
      _slotState = SlotState.active;
      _startTime = DateTime.parse(savedStartTime);
      print(
          '✅ ShiftProvider: Восстановлено активное состояние. Начало: $_startTime');
    } else {
      _slotState = SlotState.inactive;
      _startTime = null;
    }

    // Загружаем смены и проверяем активный слот на сервере
    await loadShifts();

    // Запускаем таймер, если слот активен
    if (_slotState == SlotState.active) {
      _startTimer();
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      notifyListeners(); // Обновляем UI каждую секунду
    });
  }

  Future<void> setToken(String token) async {
    _token = token;
    await _storage.write(key: 'jwt_token', value: token);
    print('✅ Токен сохранён');
    await _initializeShiftProvider();
  }

  SlotState get slotState => _slotState;
  List<ShiftData> get shiftHistory => _shiftHistory;
  DateTime get selectedDate => _selectedDate;
  DateTime? get startTime => _startTime;

  String get formattedWorkTime {
    if (_startTime == null) return '0ч 0мин';
    final duration = DateTime.now().difference(_startTime!);
    final h = duration.inHours;
    final m = (duration.inMinutes % 60);
    return '${h}ч ${m}мин';
  }

  Future<void> loadShifts() async {
    if (_token == null) {
      print('❌ ShiftProvider: Токен не установлен');
      return;
    }
    try {
      print('✅ Загружаю смены...');
      _shiftHistory = await _apiService.getShifts(_token!);
      print('✅ Смены загружены: ${_shiftHistory.length} записей');

      // 🔍 Проверяем, есть ли активный слот на сервере
      final activeShift = _shiftHistory.lastWhereOrNull((s) => s.isActive);
      if (activeShift != null) {
        if (_slotState != SlotState.active) {
          _slotState = SlotState.active;
          _startTime = DateTime.parse(activeShift.startTime);

          // Сохраняем локально
          await _storage.write(key: 'slot_state', value: 'active');
          await _prefs.setString(
              'active_slot_start_time', _startTime!.toIso8601String());

          _startTimer();
          print('✅ Восстановлен активный слот с сервера: $_startTime');
        }
      } else {
        // Если на сервере нет активного слота, но у нас был — сбросим
        if (_slotState == SlotState.active) {
          _slotState = SlotState.inactive;
          _startTime = null;
          await _storage.write(key: 'slot_state', value: 'inactive');
          await _prefs.remove('active_slot_start_time');
        }
      }

      notifyListeners();
    } catch (e) {
      print('❌ Ошибка загрузки смен: $e');
    }
  }

  void selectDate(DateTime date) {
    _selectedDate = DateTime(date.year, date.month, date.day);
    notifyListeners();
  }

  Future<void> startSlot({
    required String slotTimeRange,
    required String position,
    required String zone,
    required XFile selfie,
  }) async {
    if (_slotState == SlotState.active) {
      print('⚠️ Слот уже активен. Отмена повторного запуска.');
      return;
    }

    if (_token == null) {
      print('❌ Ошибка: Токен не установлен');
      throw Exception('Токен не установлен');
    }

    final File imageFile = File(selfie.path);
    try {
      await _apiService.startSlot(
        token: _token!,
        slotTimeRange: slotTimeRange,
        position: position,
        zone: zone,
        selfieImage: imageFile,
      );

      _startTime = DateTime.now();
      _slotState = SlotState.active;

      // Сохраняем
      await _storage.write(key: 'slot_state', value: 'active');
      await _prefs.setString(
          'active_slot_start_time', _startTime!.toIso8601String());

      _startTimer();
      await loadShifts();
      notifyListeners();

      print('✅ Слот успешно начат');
    } catch (e) {
      print('❌ Ошибка при старте слота: $e');
      rethrow;
    }
  }

  Future<void> endSlot() async {
    if (_token == null) throw Exception('Токен не установлен');
    if (_slotState != SlotState.active) return;

    try {
      await _apiService.endSlot(_token!);

      _slotState = SlotState.inactive;
      _timer?.cancel();
      _startTime = null;

      await _storage.write(key: 'slot_state', value: 'inactive');
      await _prefs.remove('active_slot_start_time');

      await loadShifts();
      notifyListeners();

      print('✅ Слот завершён');
    } catch (e) {
      print('❌ Ошибка при завершении слота: $e');
      rethrow;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

enum SlotState { inactive, active }

// ✅ Расширение для безопасного поиска
extension IterableFirstOrNull<T> on Iterable<T> {
  T? lastWhereOrNull(bool Function(T) test) {
    T? result;
    for (final item in this) {
      if (test(item)) result = item;
    }
    return result;
  }
}
