import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:jwt_decode/jwt_decode.dart';
import 'package:micro_mobility_app/models/active_shift.dart' as model;
import '../models/shift_data.dart';
import '../services/api_service.dart';
import '../config/app_config.dart';

class ShiftProvider with ChangeNotifier {
  final ApiService _apiService;
  final FlutterSecureStorage _storage;
  final SharedPreferences _prefs;
  String? _token;
  model.ActiveShift? _activeShift;
  List<ShiftData> _shiftHistory = [];
  DateTime _selectedDate = DateTime.now().toLocal(); // ← Локальное время
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
  static const Duration _cacheDuration = Duration(minutes: 5);
  Map<String, dynamic>? _profile;
  DateTime? _lastProfileFetchTime;
  bool _hasLoadedProfile = false;

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
        }

        _isOnline = isCurrentlyOnline;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          notifyListeners();
        });
      },
      onError: (error) {
        debugPrint('❌ Ошибка мониторинга сети: $error');
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
  Map<String, dynamic>? get profile => _profile;

  String get formattedWorkTime {
    if (_activeShift?.startTime == null) return '0ч 0мин 0с';
    final now = DateTime.now().toLocal(); // ← Локальное время
    final duration = now.difference(_activeShift!.startTime!);
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;
    return '${hours}ч ${minutes}мин ${seconds}с';
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
      final response =
          await _retryApiCall(() => _apiService.getActiveShift(_token!));

      if (response == null ||
          response.toString() == 'null' ||
          response.toString() == '[]' ||
          response.toString() == '{}') {
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
      _activeShift = null;
      return _activeShift;
    } finally {
      _isLoadingActiveShift = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notifyListeners();
      });
    }
  }

  Future<T> _retryApiCall<T>(Future<T> Function() apiCall) async {
    const maxRetries = 3;
    const retryDelay = Duration(seconds: 2);
    for (var i = 0; i < maxRetries; i++) {
      try {
        return await apiCall();
      } catch (e) {
        if (e.toString().contains('502') && i < maxRetries - 1) {
          await Future.delayed(retryDelay);
          continue;
        }
        rethrow;
      }
    }
    throw Exception('API call failed after $maxRetries retries');
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
    if (!_isTokenValid(_token!)) {
      debugPrint('🔐 Токен истёк. Выход...');
      await logout();
      return;
    }
    try {
      final dynamic shiftsData =
          await _retryApiCall(() => _apiService.getShifts(_token!));
      if (shiftsData is List) {
        _shiftHistory = shiftsData
            .whereType<Map<String, dynamic>>()
            .map((json) => ShiftData.fromJson(json))
            .toList();
      } else {
        _shiftHistory = [];
      }
      await getActiveShift();
      await _saveToCache();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notifyListeners();
      });
    } catch (e) {
      debugPrint('ShiftProvider.loadShifts error: $e');
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
    _selectedDate =
        DateTime(date.year, date.month, date.day).toLocal(); // ← Локальная дата
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
      await _retryApiCall(() => _apiService.startSlot(
            token: _token!,
            slotTimeRange: slotTimeRange,
            position: position,
            zone: zone,
            selfieImage: imageFile,
          ));
      debugPrint('✅ Смена начата');
      await loadShifts();
    } catch (e) {
      debugPrint('❌ Ошибка старта смены: $e');
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
      await _retryApiCall(() => _apiService.endSlot(_token!));
      debugPrint('✅ Смена завершена');
      _lastActiveShiftFetchTime = null;
      _activeShift = null;
      _currentUsername = null;
      await loadShifts();
    } catch (e) {
      debugPrint('❌ Ошибка завершения смены: $e');
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
      final stats = await _retryApiCall(
          () => _apiService.getScooterStatsForShift(_token!));
      _botStatsData = stats;
      _lastBotStatsFetchTime = DateTime.now();
      debugPrint('✅ Bot stats fetched successfully.');
      await _saveToCache();
    } catch (e) {
      debugPrint('❌ ShiftProvider.fetchBotStats error: $e');
    } finally {
      _isLoadingBotStats = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notifyListeners();
      });
    }
  }

  Future<void> logout() async {
    _token = null;
    _activeShift = null;
    _currentUsername = null;
    _botStatsData = null;
    _hasLoadedShifts = false;
    await _storage.delete(key: 'jwt_token');
    await _prefs.remove(_shiftsCacheKey);
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
    if (_token == null) return null;

    if (!force &&
        _lastProfileFetchTime != null &&
        DateTime.now().difference(_lastProfileFetchTime!) <
            const Duration(minutes: 10)) {
      return _profile;
    }

    try {
      final profile = await _apiService.getUserProfile(_token!);
      _profile = profile;
      _lastProfileFetchTime = DateTime.now();
      _hasLoadedProfile = true;
      await _saveToCache();
      notifyListeners();
      return profile;
    } catch (e) {
      debugPrint('Ошибка загрузки профиля: $e');
      return null;
    }
  }

  void setCurrentUsername(String? username) {
    if (_currentUsername != username) {
      _currentUsername = username;
      _saveToCache();
      notifyListeners();
    }
  }
}
