// lib/providers/shift_provider.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart'; // Для XFile
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

// === ДОБАВЛЕНО: Импорт для работы с временными зонами ===
import 'package:timezone/timezone.dart' as tz;
// !!! УБРАЛИ: import 'package:timezone/data/latest.dart' as tz_data; !!!
// Инициализация теперь происходит в main.dart

// Импорты моделей
import 'package:micro_mobility_app/models/active_shift.dart' as model;
import '../models/shift_data.dart';

// Импорт сервиса
import '../services/api_service.dart';

class ShiftProvider with ChangeNotifier {
  final ApiService _apiService;
  final FlutterSecureStorage _storage;
  final SharedPreferences _prefs;

  String? _token;
  model.ActiveShift? _activeShift;
  List<ShiftData> _shiftHistory = [];
  // === ИЗМЕНЕНО: Храним выбранную дату в UTC+5 ===
  DateTime _selectedDate = _toAlmatyTime(DateTime.now());
  Timer? _timer;

  bool _isEndingSlot = false; // 🔒 Защита от двойного вызова
  bool _isStartingSlot = false; // 🔒 Защита при старте

  // === ДОБАВЛЕНО: Поля для статистики бота ===
  Map<String, dynamic>? _botStatsData;
  bool _isLoadingBotStats = false;
  // Кэшируем время последнего запроса, чтобы не запрашивать слишком часто
  DateTime? _lastBotStatsFetchTime;

  // === ИЗМЕНЕНО: Храним username вместо user_id ===
  String? _currentUsername;
  List<ShiftData> get activeShifts =>
      _shiftHistory.where((shift) => shift.isActive).toList();
  ShiftProvider({
    required ApiService apiService,
    required FlutterSecureStorage storage,
    required SharedPreferences prefs,
    String? initialToken,
  })  : _apiService = apiService,
        _storage = storage,
        _prefs = prefs {
    // !!! УБРАЛИ: tz_data.initializeTimeZones(); !!!
    // Инициализация временных зон происходит в main.dart
    _token = initialToken;
    _initializeShiftProvider();
  }

  // === ДОБАВЛЕНО: Вспомогательная функция для преобразования в Almaty время ===
  static DateTime _toAlmatyTime(DateTime dateTime) {
    // !!! Теперь это безопасно, так как initializeTimeZones() уже был вызван в main() !!!
    final almatyLocation = tz.getLocation('Asia/Almaty');
    // Создаем TZDateTime из обычного DateTime
    final tzDateTime = tz.TZDateTime.from(dateTime, almatyLocation);
    // Преобразуем обратно в DateTime, но уже в нужной зоне
    return tzDateTime.toLocal();
  }

  // === ДОБАВЛЕНО: Вспомогательная функция для получения текущего времени в Almaty ===
  static DateTime _nowInAlmaty() {
    final almatyLocation = tz.getLocation('Asia/Almaty');
    return tz.TZDateTime.now(almatyLocation).toLocal();
  }

  void _startTimer() {
    _timer?.cancel();
    if (_activeShift?.startTime != null) {
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        notifyListeners(); // Обновляем UI каждую секунду
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

  // === ДОБАВЛЕНО: Геттеры для статистики бота ===
  Map<String, dynamic>? get botStatsData => _botStatsData;
  bool get isLoadingBotStats => _isLoadingBotStats;

  // === ИЗМЕНЕНО: Геттер для username ===
  String? get currentUsername => _currentUsername;

  // ✅ Исправленный метод без двойного преобразования
  String get formattedWorkTime {
    if (_activeShift?.startTime == null) return '0ч 0мин 0с';

    // Просто форматируем startTime как "ЧЧ:ММ:СС"
    final time = _activeShift!.startTime!;
    return '${time.hour}ч ${time.minute}мин ${time.second}с';
  }

  Future<void> _initializeShiftProvider() async {
    if (_token == null) {
      _token = await _storage.read(key: 'jwt_token');
    }
    await loadShifts();
  }

  Future<void> loadShifts() async {
    if (_token == null) {
      _shiftHistory = [];
      _activeShift = null;
      _currentUsername = null; // Сбрасываем username
      _timer?.cancel();
      notifyListeners();
      return;
    }

    try {
      final dynamic shiftsData = await _apiService.getShifts(_token!);
      if (shiftsData is List) {
        _shiftHistory = shiftsData
            .whereType<Map<String, dynamic>>()
            .map((json) => ShiftData.fromJson(json))
            .toList();
      } else {
        _shiftHistory = [];
      }

      final activeShift = await _apiService.getActiveShift(_token!);
      _activeShift = activeShift;

      // === ИЗМЕНЕНО: Устанавливаем username ===
      if (activeShift != null) {
        _currentUsername = activeShift.username; // Используем username
        _startTimer();
      } else {
        _currentUsername = null;
        _timer?.cancel();
      }

      notifyListeners();
    } catch (e) {
      debugPrint('ShiftProvider.loadShifts error: $e');
      _shiftHistory = [];
      _activeShift = null;
      _currentUsername = null;
      _timer?.cancel();
      notifyListeners();
    }
  }

  // === ИЗМЕНЕНО: Установка даты с учетом Almaty времени ===
  void selectDate(DateTime date) {
    // Преобразуем выбранную дату в Almaty время
    _selectedDate = _toAlmatyTime(DateTime(date.year, date.month, date.day));
    notifyListeners();
  }

  /// Начало новой смены
  Future<void> startSlot({
    required String slotTimeRange,
    required String position,
    required String zone,
    required XFile selfie,
  }) async {
    if (_isStartingSlot) {
      debugPrint('ShiftProvider: Start slot already in progress.');
      return;
    }
    if (_activeShift != null) {
      debugPrint('ShiftProvider: Cannot start slot, already active.');
      return;
    }
    if (_token == null) {
      debugPrint('ShiftProvider: Cannot start slot, no token.');
      throw Exception('Токен не установлен');
    }

    final File imageFile = File(selfie.path);
    _isStartingSlot = true;
    notifyListeners(); // UI может показать лоадер

    try {
      await _apiService.startSlot(
        token: _token!,
        slotTimeRange: slotTimeRange,
        position: position,
        zone: zone,
        selfieImage: imageFile,
      );
      debugPrint('ShiftProvider: Slot started successfully.');

      // Сразу перезагружаем данные
      await loadShifts();
    } catch (e) {
      debugPrint('ShiftProvider.startSlot error: $e');
      rethrow;
    } finally {
      _isStartingSlot = false;
      notifyListeners();
    }
  }

  /// Завершение текущей смены
  Future<void> endSlot() async {
    if (_isEndingSlot) {
      debugPrint('ShiftProvider: End slot already in progress.');
      return;
    }
    if (_token == null) {
      debugPrint('ShiftProvider: Cannot end slot, no token.');
      throw Exception('Токен не установлен');
    }
    if (_activeShift == null) {
      debugPrint('ShiftProvider: No active shift to end.');
      return;
    }

    _isEndingSlot = true;
    notifyListeners(); // Покажем лоадер

    try {
      await _apiService.endSlot(_token!);
      debugPrint('✅ Slot ended successfully.');

      // ✅ Сразу сбрасываем активную смену, username и таймер
      _activeShift = null;
      _currentUsername = null; // Сбрасываем username
      _timer?.cancel();

      // ✅ Перезагружаем историю (асинхронно)
      unawaited(loadShifts());

      // ✅ Уведомляем UI немедленно
      notifyListeners();
    } catch (e) {
      debugPrint('❌ ShiftProvider.endSlot error: $e');

      // На всякий случай — перезагружаем данные
      await loadShifts();
      rethrow;
    } finally {
      _isEndingSlot = false;
      notifyListeners();
    }
  }

  // === ДОБАВЛЕНО: Метод для получения статистики бота ===
  /// Получает статистику из Telegram-бота.
  /// Кэширует данные на 30 секунд, чтобы избежать частых запросов.
  Future<void> fetchBotStats() async {
    // Не запрашиваем, если уже идёт запрос
    if (_isLoadingBotStats) {
      debugPrint('ShiftProvider: Bot stats fetch already in progress.');
      return;
    }

    // Не запрашиваем, если прошло менее 30 секунд с последнего запроса
    if (_lastBotStatsFetchTime != null) {
      final now = DateTime.now();
      final difference = now.difference(_lastBotStatsFetchTime!);
      if (difference < const Duration(seconds: 30)) {
        debugPrint('ShiftProvider: Bot stats fetch skipped (cache hit).');
        // Даже если кэш "действителен", мы можем уведомить UI, что данные готовы
        if (_botStatsData != null) {
          notifyListeners();
        }
        return;
      }
    }

    if (_token == null) {
      debugPrint('ShiftProvider: Cannot fetch bot stats, no token.');
      // Очищаем данные, если токена нет
      _botStatsData = null;
      notifyListeners();
      return;
    }

    _isLoadingBotStats = true;
    notifyListeners();

    try {
      debugPrint('ShiftProvider: Fetching bot stats...');
      final stats = await _apiService.getScooterStatsForShift(_token!);
      _botStatsData = stats;
      _lastBotStatsFetchTime = DateTime.now();
      debugPrint('ShiftProvider: Bot stats fetched successfully.');
    } catch (e) {
      debugPrint('ShiftProvider.fetchBotStats error: $e');
      // В случае ошибки оставляем старые данные или null
      // Можно показать уведомление пользователю
    } finally {
      _isLoadingBotStats = false;
      notifyListeners();
    }
  }

  // === ДОБАВЛЕНО: Метод для принудительного обновления статистики ===
  /// Принудительно обновляет статистику бота, игнорируя кэш.
  Future<void> forceRefreshBotStats() async {
    _lastBotStatsFetchTime = null; // Сбрасываем время последнего запроса
    await fetchBotStats();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
