// lib/providers/shift_provider.dart
import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:math' show e;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:micro_mobility_app/models/active_shift.dart' as model;
import '../models/shift_data.dart';
import '../services/api_service.dart';
import '../config/app_config.dart';
import '../services/geo_tracking_service.dart'
    show
        startBackgroundTracking,
        stopBackgroundTracking,
        syncBufferedData,
        isBackgroundTrackingRunning;

class ShiftProvider with ChangeNotifier {
  final ApiService _apiService;
  final FlutterSecureStorage _storage;
  final SharedPreferences _prefs;
  String? _token;
  model.ActiveShift? _activeShift;
  List<ShiftData> _shiftHistory = [];
  DateTime _selectedDate = DateTime.now().toLocal();
  bool _isEndingSlot = false;
  bool _isStartingSlot = false;
  Map<String, dynamic>? _botStatsData;
  bool _isLoadingBotStats = false;
  DateTime? _lastBotStatsFetchTime;
  String? _currentUsername;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _isOnline = true;
  static const String _shiftsCacheKey = 'shifts_cache';
  static const String _lastCacheTimeKey = 'shifts_cache_time';
  bool _isLoadingActiveShift = false;
  DateTime? _lastActiveShiftFetchTime;
  bool _hasLoadedShifts = false;
  Map<String, dynamic>? _profile;
  DateTime? _lastProfileFetchTime;
  bool _hasLoadedProfile = false;
  bool _isLoadingProfile = false;

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

  void _setupConnectivityListener() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
      (List<ConnectivityResult> results) {
        final ConnectivityResult result =
            results.isNotEmpty ? results.last : ConnectivityResult.none;
        final bool isCurrentlyOnline = result != ConnectivityResult.none;

        if (isCurrentlyOnline && !_isOnline) {
          if (!_hasLoadedShifts && _token != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              loadShifts();
            });
          }
          WidgetsBinding.instance.addPostFrameCallback((_) {
            syncBufferedData();
          });
        }

        _isOnline = isCurrentlyOnline;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          notifyListeners();
        });
      },
      onError: (error) {
        debugPrint('❌ Ошибка мониторинга сети: $e');
      },
    );
  }

  Future<void> _saveToCache() async {
    try {
      final data = {
        'shifts': _shiftHistory.map((s) => s.toJson()).toList(),
        'activeShift': _activeShift?.toJson(),
        'username': _currentUsername,
        'botStatsData': _botStatsData,
        'profile': _profile,
        'hasLoadedProfile': _hasLoadedProfile,
        'timestamp': DateTime.now().toIso8601String(),
      };
      await _prefs.setString(_shiftsCacheKey, jsonEncode(data));
    } catch (e) {
      debugPrint('❌ Ошибка сохранения в кэш: $e');
    }
  }

  Future<void> loadFromCache() async {
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
      _profile = data['profile'] as Map<String, dynamic>?;
      _hasLoadedProfile = data['hasLoadedProfile'] as bool? ?? false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notifyListeners();
      });
    } catch (e) {
      debugPrint('❌ Ошибка загрузки из кэша: $e');
    }
  }

  model.ActiveShift? get activeShift => _activeShift;
  List<ShiftData> get shiftHistory => _shiftHistory;
  List<ShiftData> get activeShifts =>
      _shiftHistory.where((shift) => shift.isActive).toList();
  DateTime get selectedDate => _selectedDate;
  Map<String, dynamic>? get botStatsData => _botStatsData;
  bool get isLoadingBotStats => _isLoadingBotStats;
  String? get currentUsername => _currentUsername;
  bool get hasLoadedShifts => _hasLoadedShifts;
  bool get hasLoadedProfile => _hasLoadedProfile;
  bool get isLoadingProfile => _isLoadingProfile;
  Map<String, dynamic>? get profile => _profile;

  String get formattedWorkTime {
    if (_activeShift?.startTime == null) return '0ч 0мин 0с';
    final now = DateTime.now().toLocal();
    final duration = now.difference(_activeShift!.startTime!);
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;
    return '${hours}ч ${minutes}мин ${seconds}с';
  }

  Future<void> setToken(String token) async {
    _token = token;
    await _storage.write(key: 'jwt_token', value: token);
  }

  Future<void> _initializeShiftProvider() async {
    if (_token == null) {
      _token = await _storage.read(key: 'jwt_token');
    }
    await loadFromCache();
    if (_isOnline && _token != null && !_hasLoadedShifts) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        loadShifts();
      });
    }
  }

  Future<model.ActiveShift?> getActiveShift() async {
    if (_token == null || _isLoadingActiveShift) return _activeShift;
    if (_lastActiveShiftFetchTime != null) {
      final now = DateTime.now();
      final difference = now.difference(_lastActiveShiftFetchTime!);
      if (difference < const Duration(seconds: 30) && _activeShift != null) {
        debugPrint('ShiftProvider: getActiveShift skipped (cache hit).');
        return _activeShift;
      }
    }
    try {
      _isLoadingActiveShift = true;
      final response = await _apiService.getActiveShift(_token!);

      if (response == null) {
        _activeShift = null;
      } else {
        _activeShift = response;
      }

      _lastActiveShiftFetchTime = DateTime.now();
      if (_activeShift != null) {
        _currentUsername = _activeShift!.username;
      } else {
        _currentUsername = null;
      }
      await _saveToCache();
      return _activeShift;
    } catch (e) {
      debugPrint('❌ Ошибка получения активной смены: $e');
      final storedToken = await _storage.read(key: 'jwt_token');
      if (storedToken == null) {
        debugPrint('Token was cleared during getActiveShift.');
        await logout();
        return null;
      }
      _activeShift = null;
      return _activeShift;
    } finally {
      _isLoadingActiveShift = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notifyListeners();
      });
    }
  }

  Future<void> loadShifts() async {
    final isFirstLoad = !_hasLoadedShifts;
    _hasLoadedShifts = true;

    if (_token == null) {
      _shiftHistory = [];
      _activeShift = null;
      _currentUsername = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notifyListeners();
      });
      return;
    }
    try {
      final shiftsData = await _apiService.getShifts(_token!);
      _shiftHistory = shiftsData;

      await getActiveShift();
      await _saveToCache();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notifyListeners();
      });
    } catch (e) {
      debugPrint('ShiftProvider.loadShifts error: $e');
      final storedToken = await _storage.read(key: 'jwt_token');
      if (storedToken == null) {
        debugPrint('Token was cleared during loadShifts.');
        await logout();
        return;
      }
      if (isFirstLoad && !_isOnline) {
        await loadFromCache();
      } else {
        _shiftHistory = [];
        _activeShift = null;
        _currentUsername = null;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notifyListeners();
      });
    }
  }

  void selectDate(DateTime date) {
    _selectedDate = DateTime(date.year, date.month, date.day).toLocal();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      notifyListeners();
    });
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      notifyListeners();
    });
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

      await syncGeoTrackingWithShiftState();
    } catch (e) {
      debugPrint('❌ Ошибка старта смены: $e');
      final storedToken = await _storage.read(key: 'jwt_token');
      if (storedToken == null) {
        debugPrint('Token was cleared during startSlot.');
        await logout();
      }
      rethrow;
    } finally {
      _isStartingSlot = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notifyListeners();
      });
    }
  }

  Future<void> endSlot() async {
    if (_isEndingSlot || _token == null || _activeShift == null) return;
    _isEndingSlot = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      notifyListeners();
    });
    try {
      await _apiService.endSlot(_token!);
      debugPrint('✅ Смена завершена');
      _lastActiveShiftFetchTime = null;
      _activeShift = null;
      _currentUsername = null;
      await loadShifts();

      await syncGeoTrackingWithShiftState();
    } catch (e) {
      debugPrint('❌ Ошибка завершения смены: $e');
      final storedToken = await _storage.read(key: 'jwt_token');
      if (storedToken == null) {
        debugPrint('Token was cleared during endSlot.');
        await logout();
      }
      await loadShifts();
      rethrow;
    } finally {
      _isEndingSlot = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notifyListeners();
      });
    }
  }

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
        if (_botStatsData != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            notifyListeners();
          });
        }
        return;
      }
    }
    if (_token == null) {
      debugPrint('ShiftProvider: Cannot fetch bot stats, no token.');
      _botStatsData = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notifyListeners();
      });
      return;
    }
    _isLoadingBotStats = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      notifyListeners();
    });
    try {
      debugPrint('ShiftProvider: Fetching bot stats...');
      final stats = await _apiService.getScooterStatsForShift(_token!);
      _botStatsData = stats;
      _lastBotStatsFetchTime = DateTime.now();
      debugPrint('✅ Bot stats fetched successfully.');
      await _saveToCache();
    } catch (e) {
      debugPrint('❌ ShiftProvider.fetchBotStats error: $e');
      final storedToken = await _storage.read(key: 'jwt_token');
      if (storedToken == null) {
        debugPrint('Token was cleared during fetchBotStats.');
        await logout();
      }
    } finally {
      _isLoadingBotStats = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notifyListeners();
      });
    }
  }

  Future<void> syncGeoTrackingWithShiftState() async {
    try {
      await getActiveShift();

      final bool isTrackingRunning = await isBackgroundTrackingRunning();
      final bool hasActiveShift =
          _activeShift != null && _activeShift!.id != null;

      if (hasActiveShift && !isTrackingRunning) {
        debugPrint(
            'SyncGeoTracking: Запуск трекинга для активной смены ${_activeShift!.id}');
        await _prefs.setInt('active_shift_id_for_bg_service', _activeShift!.id);
        await startBackgroundTracking(shiftId: _activeShift!.id);
      } else if (!hasActiveShift && isTrackingRunning) {
        debugPrint(
            'SyncGeoTracking: Остановка трекинга, так как нет активной смены.');
        await stopBackgroundTracking();
        await _prefs.remove('active_shift_id_for_bg_service');
      } else {
        debugPrint(
            'SyncGeoTracking: Состояние трекинга и смены согласовано. Трекинг запущен: $isTrackingRunning, Активная смена: $hasActiveShift');
      }
    } catch (e) {
      debugPrint('Ошибка синхронизации геотрекинга: $e');
    }
  }

  Future<void> logout() async {
    _token = null;
    _activeShift = null;
    _currentUsername = null;
    _botStatsData = null;
    _profile = null;
    _hasLoadedProfile = false;
    _hasLoadedShifts = false;
    _isLoadingProfile = false;
    await _storage.delete(key: 'jwt_token');
    await _storage.delete(key: 'refresh_token');
    await _prefs.remove(_shiftsCacheKey);
    await syncGeoTrackingWithShiftState();
    await _prefs.remove('active_shift_id_for_bg_service');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  Future<Map<String, dynamic>?> loadProfile({bool force = false}) async {
    if (_isLoadingProfile) {
      debugPrint('🔄 LoadProfile already in progress. Skipping.');
      return _profile;
    }

    if (_token == null) {
      debugPrint('❌ Нет токена для загрузки профиля.');
      return null;
    }

    if (!force &&
        _lastProfileFetchTime != null &&
        DateTime.now().difference(_lastProfileFetchTime!) <
            const Duration(minutes: 10)) {
      debugPrint('ShiftProvider: Загрузка профиля пропущена (кеширование).');
      _hasLoadedProfile = true;
      return _profile;
    }

    _isLoadingProfile = true;
    notifyListeners();

    try {
      debugPrint('🔄 Загружаем профиль с сервера...');
      final profile = await _apiService.getUserProfile(_token!);
      if (profile != null) {
        _profile = profile;
        _lastProfileFetchTime = DateTime.now();
        _hasLoadedProfile = true;
        await _saveToCache();
        notifyListeners();
        debugPrint('✅ Профиль успешно загружен.');
        return profile;
      } else {
        debugPrint(
            '❌ Не удалось загрузить профиль. Токен мог быть недействителен и не обновлен.');
        final storedToken = await _storage.read(key: 'jwt_token');
        if (storedToken == null) {
          debugPrint('Token was cleared during loadProfile.');
          await logout();
        }
        return null;
      }
    } catch (e) {
      debugPrint('❌ Ошибка загрузки профиля: $e');
      final storedToken = await _storage.read(key: 'jwt_token');
      if (storedToken == null) {
        debugPrint('Token was cleared during loadProfile.');
        await logout();
      }
      return null;
    } finally {
      _isLoadingProfile = false;
      notifyListeners();
    }
  }

  void setCurrentUsername(String? username) {
    if (_currentUsername != username) {
      _currentUsername = username;
      _saveToCache();
      notifyListeners();
    }
  }

  Future<void> syncBufferedData() async {
    try {
      // TODO: реализовать синхронизацию буфера
      debugPrint('syncBufferedData() called — but not implemented');
    } catch (e) {
      debugPrint('Ошибка syncBufferedData: $e');
    }
  }
}
