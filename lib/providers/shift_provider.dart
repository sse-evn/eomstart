// lib/providers/shift_provider.dart

import 'dart:async';
import 'dart:io';
import 'dart:convert'; // ✅ Обязательно для jsonEncode / jsonDecode

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart'; // 🔄 Мониторинг сети
import 'package:jwt_decode/jwt_decode.dart'; // 🔐 Проверка JWT

import 'package:timezone/timezone.dart' as tz;
import 'package:micro_mobility_app/models/active_shift.dart' as model;
import '../models/shift_data.dart';
import '../services/api_service.dart';
import '../config.dart';

class ShiftProvider with ChangeNotifier {
  final ApiService _apiService;
  final FlutterSecureStorage _storage;
  final SharedPreferences _prefs;

  String? _token;
  model.ActiveShift? _activeShift;
  List<ShiftData> _shiftHistory = [];
  DateTime _selectedDate = _toAlmatyTime(DateTime.now());

  Timer? _timer;
  bool _isEndingSlot = false;
  bool _isStartingSlot = false;

  // === Статистика бота ===
  Map<String, dynamic>? _botStatsData;
  bool _isLoadingBotStats = false;
  DateTime? _lastBotStatsFetchTime;

  // === Пользователь ===
  String? _currentUsername;

  // 🔄 Сетевое состояние — ✅ ИСПРАВЛЕНО: теперь List<ConnectivityResult>
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _isOnline = true;

  // 📱 Кэширование
  static const String _shiftsCacheKey = 'shifts_cache';
  static const String _lastCacheTimeKey = 'shifts_cache_time';

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
    _setupConnectivityListener();
  }

  // === Вспомогательные функции времени (Almaty) ===
  static DateTime _toAlmatyTime(DateTime dateTime) {
    final almatyLocation = tz.getLocation('Asia/Almaty');
    final tzDateTime = tz.TZDateTime.from(dateTime, almatyLocation);
    return tzDateTime.toLocal();
  }

  static DateTime _nowInAlmaty() {
    final almatyLocation = tz.getLocation('Asia/Almaty');
    return tz.TZDateTime.now(almatyLocation).toLocal();
  }

  void _startTimer() {
    _timer?.cancel();
    if (_activeShift?.startTime != null) {
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        notifyListeners();
      });
    }
  }

  // 🔐 Проверка срока действия токена
  bool _isTokenValid(String token) {
    try {
      final payload = Jwt.parseJwt(token);
      final exp = payload['exp'] as int?;
      if (exp == null) return false;
      final expiryDate = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
      return expiryDate.isAfter(DateTime.now());
    } catch (e) {
      return false;
    }
  }

  // 🔄 Подписка на изменение сети
  void _setupConnectivityListener() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
      (List<ConnectivityResult> results) {
        final ConnectivityResult result =
            results.isNotEmpty ? results.last : ConnectivityResult.none;
        final bool isCurrentlyOnline = result != ConnectivityResult.none;

        if (isCurrentlyOnline && !_isOnline) {
          debugPrint('🌐 Интернет восстановлен. Перезагрузка смен...');
          loadShifts();
        }
        _isOnline = isCurrentlyOnline;
      },
      onError: (error) {
        debugPrint('❌ Ошибка мониторинга сети: $error');
      },
    );
  }

  // 📱 Сохранение в кэш (SharedPreferences)
  Future<void> _saveToCache() async {
    try {
      final data = {
        'shifts': _shiftHistory.map((s) => s.toJson()).toList(),
        'activeShift': _activeShift?.toJson(),
        'username': _currentUsername,
        'botStatsData': _botStatsData,
        'timestamp': DateTime.now().toIso8601String(),
      };
      await _prefs.setString(_shiftsCacheKey, jsonEncode(data));
    } catch (e) {
      debugPrint('❌ Ошибка сохранения в кэш: $e');
    }
  }

  // 📱 Загрузка из кэша
  Future<void> _loadFromCache() async {
    try {
      final cached = _prefs.getString(_shiftsCacheKey);
      if (cached == null) return;

      final data = jsonDecode(cached) as Map<String, dynamic>;
      final timestamp = DateTime.parse(data['timestamp']);
      if (DateTime.now().difference(timestamp) > const Duration(hours: 24)) {
        await _prefs.remove(_shiftsCacheKey);
        return;
      }

      final List<dynamic> shifts = data['shifts'];
      _shiftHistory = shifts.map((json) => ShiftData.fromJson(json)).toList();

      final activeShiftData = data['activeShift'];
      _activeShift = activeShiftData != null
          ? model.ActiveShift.fromJson(activeShiftData)
          : null;

      _currentUsername = data['username'] as String?;
      _botStatsData = data['botStatsData'] as Map<String, dynamic>?;

      if (_activeShift != null) {
        _startTimer();
      }

      debugPrint('✅ Данные загружены из кэша');
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Ошибка загрузки из кэша: $e');
    }
  }

  // === Геттеры ===
  model.ActiveShift? get activeShift => _activeShift;
  List<ShiftData> get shiftHistory => _shiftHistory;
  List<ShiftData> get activeShifts =>
      _shiftHistory.where((shift) => shift.isActive).toList();
  DateTime get selectedDate => _selectedDate;

  // ✅ Для BotStatsCard
  Map<String, dynamic>? get botStatsData => _botStatsData;
  bool get isLoadingBotStats => _isLoadingBotStats;
  String? get currentUsername => _currentUsername;

  String get formattedWorkTime {
    if (_activeShift?.startTime == null) return '0ч 0мин 0с';
    final time = _activeShift!.startTime!;
    return '${time.hour}ч ${time.minute}мин ${time.second}с';
  }

  Future<void> setToken(String token) async {
    _token = token;
    await _storage.write(key: 'jwt_token', value: token);
    await _initializeShiftProvider();
  }

  Future<void> _initializeShiftProvider() async {
    if (_token == null) {
      _token = await _storage.read(key: 'jwt_token');
    }

    if (_token != null && !_isTokenValid(_token!)) {
      debugPrint('🔐 Токен просрочен. Выполняем выход...');
      await logout();
      return;
    }

    await _loadFromCache();

    if (_isOnline && _token != null) {
      await loadShifts();
    }
  }

  Future<void> loadShifts() async {
    if (_token == null) {
      _shiftHistory = [];
      _activeShift = null;
      _currentUsername = null;
      _timer?.cancel();
      notifyListeners();
      return;
    }

    if (!_isTokenValid(_token!)) {
      debugPrint('🔐 Токен истёк. Выход...');
      await logout();
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

      if (activeShift != null) {
        _currentUsername = activeShift.username;
        _startTimer();
      } else {
        _currentUsername = null;
        _timer?.cancel();
      }

      await _saveToCache();
      notifyListeners();
    } catch (e) {
      debugPrint('ShiftProvider.loadShifts error: $e');

      if (!_isOnline) {
        await _loadFromCache();
      } else {
        _shiftHistory = [];
        _activeShift = null;
        _currentUsername = null;
        _timer?.cancel();
      }
      notifyListeners();
    }
  }

  void selectDate(DateTime date) {
    _selectedDate = _toAlmatyTime(DateTime(date.year, date.month, date.day));
    notifyListeners();
  }

  Future<void> startSlot({
    required String slotTimeRange,
    required String position,
    required String zone,
    required XFile selfie,
  }) async {
    if (_isStartingSlot || _activeShift != null || _token == null) return;

    final File imageFile = File(selfie.path);
    _isStartingSlot = true;
    notifyListeners();

    try {
      await _apiService.startSlot(
        token: _token!,
        slotTimeRange: slotTimeRange,
        position: position,
        zone: zone,
        selfieImage: imageFile,
      );
      debugPrint('✅ Смена начата');
      await loadShifts();
    } catch (e) {
      debugPrint('❌ Ошибка старта смены: $e');
      rethrow;
    } finally {
      _isStartingSlot = false;
      notifyListeners();
    }
  }

  Future<void> endSlot() async {
    if (_isEndingSlot || _token == null || _activeShift == null) return;

    _isEndingSlot = true;
    notifyListeners();

    try {
      await _apiService.endSlot(_token!);
      debugPrint('✅ Смена завершена');
      _activeShift = null;
      _currentUsername = null;
      _timer?.cancel();
      unawaited(loadShifts());
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Ошибка завершения смены: $e');
      await loadShifts();
      rethrow;
    } finally {
      _isEndingSlot = false;
      notifyListeners();
    }
  }

  // ✅ Публичный метод для UI
  Future<void> fetchBotStats() async {
    if (_isLoadingBotStats) {
      debugPrint('ShiftProvider: Bot stats fetch already in progress.');
      return;
    }

    if (_lastBotStatsFetchTime != null) {
      final now = DateTime.now();
      final difference = now.difference(_lastBotStatsFetchTime!);
      if (difference < const Duration(seconds: 30)) {
        debugPrint('ShiftProvider: Bot stats fetch skipped (cache hit).');
        if (_botStatsData != null) notifyListeners();
        return;
      }
    }

    if (_token == null) {
      debugPrint('ShiftProvider: Cannot fetch bot stats, no token.');
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
      debugPrint('✅ Bot stats fetched successfully.');
      await _saveToCache();
    } catch (e) {
      debugPrint('❌ ShiftProvider.fetchBotStats error: $e');
    } finally {
      _isLoadingBotStats = false;
      notifyListeners();
    }
  }

  // 🔐 Выход из аккаунта
  Future<void> logout() async {
    _token = null;
    _activeShift = null;
    _currentUsername = null;
    _botStatsData = null;
    _timer?.cancel();
    await _storage.delete(key: 'jwt_token');
    await _prefs.remove(_shiftsCacheKey);
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _connectivitySubscription?.cancel(); // ✅ Отписываемся от сети
    super.dispose();
  }
}
