import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:micro_mobility_app/models/active_shift.dart' show ActiveShift;
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
  DateTime? _startTime;

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

    final String? savedStartTime = _prefs.getString('active_slot_start_time');
    final String? storedState = await _storage.read(key: 'slot_state');

    if (storedState == 'active' && savedStartTime != null) {
      try {
        _slotState = SlotState.active;
        _startTime = DateTime.parse(savedStartTime);
      } catch (e) {
        _slotState = SlotState.inactive;
        _startTime = null;
        await _storage.write(key: 'slot_state', value: 'inactive');
        await _prefs.remove('active_slot_start_time');
      }
    } else {
      _slotState = SlotState.inactive;
      _startTime = null;
    }

    await loadShifts();

    if (_slotState == SlotState.active && _startTime != null) {
      _startTimer();
    }
  }

  void _startTimer() {
    _timer?.cancel();
    if (_startTime != null) {
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        notifyListeners();
      });
    }
  }

  Future<void> setToken(String token) async {
    _token = token;
    await _storage.write(key: 'jwt_token', value: token);
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
    if (_token == null) return;

    try {
      // Загружаем историю смен
      final dynamic shiftsData = await _apiService.getShifts(_token!);
      if (shiftsData is List) {
        _shiftHistory = shiftsData
            .map((item) => item as ShiftData)
            .toList()
            .cast<ShiftData>();
      } else {
        _shiftHistory = [];
      }

      // Проверяем активную смену на сервере
      final activeShift = await _apiService.getActiveShift(_token!);
      debugPrint(
          '📡 Server active shift response: ${activeShift != null ? 'FOUND' : 'NOT FOUND'}');

      if (activeShift != null) {
        debugPrint('📋 Active shift data: ${activeShift.toJson()}');
        if (_slotState != SlotState.active ||
            _startTime != activeShift.startTime) {
          debugPrint('🔄 Updating provider with server active shift');
          await setActiveShift(activeShift);
        }
      } else {
        debugPrint('🧹 No active shift on server, clearing local state');
        if (_slotState == SlotState.active) {
          await clearActiveShift();
        }
      }

      debugPrint(
          'ShiftProvider: slotState = $_slotState, startTime = $_startTime');
      notifyListeners();
    } catch (e) {
      debugPrint('Error in loadShifts: $e');
      _shiftHistory = [];
      if (_slotState == SlotState.active) {
        await clearActiveShift();
      }
      notifyListeners();
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
    if (_slotState == SlotState.active) return;
    if (_token == null) throw Exception('Токен не установлен');

    final File imageFile = File(selfie.path);
    try {
      debugPrint(
          'Starting slot with: slotTimeRange=$slotTimeRange, position=$position, zone=$zone');
      await _apiService.startSlot(
        token: _token!,
        slotTimeRange: slotTimeRange,
        position: position,
        zone: zone,
        selfieImage: imageFile,
      );
      debugPrint('Slot started successfully, loading shifts...');
      _startTime = DateTime.now();
      _slotState = SlotState.active;

      await _storage.write(key: 'slot_state', value: 'active');
      await _prefs.setString(
          'active_slot_start_time', _startTime!.toIso8601String());

      _startTimer();
      await loadShifts();
      notifyListeners();
    } catch (e) {
      debugPrint('Error in startSlot: $e');
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
    } catch (e) {
      debugPrint('Error in endSlot: $e');
      rethrow;
    }
  }

  Future<void> setActiveShift(ActiveShift activeShift) async {
    debugPrint('🎯 setActiveShift called with: ${activeShift.toJson()}');

    if (activeShift.startTime != null) {
      _slotState = SlotState.active;
      _startTime = activeShift.startTime;
      try {
        await _storage.write(key: 'slot_state', value: 'active');
        await _prefs.setString(
            'active_slot_start_time', _startTime!.toIso8601String());
        debugPrint('💾 Saved active shift to storage');
      } catch (e) {
        debugPrint('Error saving active shift state: $e');
      }
      _startTimer();
      debugPrint('✅ Active shift set: startTime = $_startTime');
    } else {
      debugPrint('⚠️ Warning: activeShift.startTime is null');
    }
    notifyListeners();
  }

  Future<void> clearActiveShift() async {
    _slotState = SlotState.inactive;
    _startTime = null;
    try {
      await _storage.write(key: 'slot_state', value: 'inactive');
      await _prefs.remove('active_slot_start_time');
    } catch (e) {
      debugPrint('Error clearing active shift state: $e');
    }
    _timer?.cancel();
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

enum SlotState { inactive, active }

extension IterableFirstOrNull<T> on Iterable<T> {
  T? lastWhereOrNull(bool Function(T) test) {
    T? result;
    for (final item in this) {
      if (test(item)) result = item;
    }
    return result;
  }
}
