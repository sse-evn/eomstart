// providers/shift_provider.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart'; // Импортируем Secure Storage
import '../models/shift_data.dart';
import '../services/api_service.dart';

class ShiftProvider with ChangeNotifier {
  final ApiService _apiService; // Теперь final
  final FlutterSecureStorage _storage; // Добавляем Secure Storage

  String? _token;
  SlotState _slotState = SlotState.inactive;
  List<ShiftData> _shiftHistory = [];
  DateTime _selectedDate = DateTime.now();
  int _activeDurationInSeconds = 0;
  Timer? _timer;

  // ✅ ИСПРАВЛЕНИЕ: Изменяем конструктор, чтобы принимать ApiService, FlutterSecureStorage
  // и initialToken как именованные и обязательные параметры.
  ShiftProvider({
    required ApiService apiService,
    required FlutterSecureStorage storage,
    String? initialToken, // Токен, переданный из main.dart
  })  : _apiService = apiService,
        _storage = storage {
    _token = initialToken; // Устанавливаем токен здесь
    _initializeShiftProvider(); // Инициализируем провайдер после установки токена
  }

  Future<void> _initializeShiftProvider() async {
    print('✅ ShiftProvider: Инициализация...');
    // Токен уже должен быть установлен через конструктор
    // но на всякий случай, если бы мы вызывали этот метод отдельно:
    // _token = await _storage.read(key: 'jwt_token');

    final String? storedSlotState = await _storage.read(key: 'slot_state');
    if (storedSlotState == 'active') {
      _slotState = SlotState.active;
      // Если слот был активен, нужно восстановить duration.
      // Это может быть сделано через API-запрос к серверу,
      // или если сервер возвращает время начала активного слота.
      // Для простоты здесь мы пока не восстанавливаем точное время,
      // но в реальном приложении это важно.
      // Например, можно сохранить startTime в storage и потом вычитать.
      print('✅ ShiftProvider: Восстановлено активное состояние слота.');
    } else {
      _slotState = SlotState.inactive;
    }
    await loadShifts(); // Загружаем смены после инициализации
    notifyListeners();
    // Запускаем таймер только если слот действительно активен
    if (_slotState == SlotState.active) {
      _startTimer();
    }
  }

  // Метод setToken теперь сохраняет токен и загружает данные
  // Его логика изменена, чтобы соответствовать новому потоку инициализации
  Future<void> setToken(String token) async {
    _token = token;
    await _storage.write(key: 'jwt_token', value: token); // Сохраняем токен
    print('✅ ShiftProvider: Токен установлен и сохранен: $token');
    await _initializeShiftProvider(); // Переинициализируем провайдер с новым токеном
  }

  SlotState get slotState => _slotState;
  List<ShiftData> get shiftHistory => _shiftHistory;
  DateTime get selectedDate => _selectedDate;
  int get activeDuration => _activeDurationInSeconds;

  String get formattedWorkTime {
    final h = _activeDurationInSeconds ~/ 3600;
    final m = (_activeDurationInSeconds % 3600) ~/ 60;
    return '${h}ч ${m}мин';
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _activeDurationInSeconds++;
      if (_activeDurationInSeconds % 10 == 0) {
        // Обновляем UI только каждые 10 секунд
        notifyListeners();
      }
    });
  }

  Future<void> loadShifts() async {
    if (_token == null) {
      print('❌ ShiftProvider: Токен не установлен, не могу загрузить смены');
      return;
    }
    try {
      print('✅ Загружаю смены...');
      _shiftHistory = await _apiService.getShifts(_token!);
      print('✅ Смены загружены: ${_shiftHistory.length} записей');
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
    print('✅ ShiftProvider.startSlot вызван');
    print(
        'Slot: $slotTimeRange, Pos: $position, Zone: $zone, Selfie: ${selfie.path}');

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
      print('✅ API: Слот успешно начат');

      _slotState = SlotState.active;
      _activeDurationInSeconds = 0;
      //_startTimer(); // Таймер запускается в _initializeShiftProvider
      await _storage.write(
          key: 'slot_state', value: 'active'); // Сохраняем состояние слота
      await loadShifts();
      notifyListeners();
      // Перезапускаем таймер после успешного старта
      _startTimer();
    } catch (e) {
      print('❌ Ошибка при старте слота: $e');
      rethrow;
    }
  }

  Future<void> endSlot() async {
    if (_token == null) throw Exception('Токен не установлен');
    try {
      await _apiService.endSlot(_token!);
      _slotState = SlotState.inactive;
      _timer?.cancel();
      _activeDurationInSeconds = 0;
      await _storage.write(
          key: 'slot_state', value: 'inactive'); // Сохраняем состояние слота
      await loadShifts();
      notifyListeners();
    } catch (e) {
      print('❌ Ошибка при завершении слота: $e'); // Добавил вывод ошибки
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
