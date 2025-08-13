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
      _slotState = SlotState.active;
      _startTime = DateTime.parse(savedStartTime);
    } else {
      _slotState = SlotState.inactive;
      _startTime = null;
    }

    await loadShifts();

    if (_slotState == SlotState.active) {
      _startTimer();
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      notifyListeners();
    });
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
      _shiftHistory = await _apiService.getShifts(_token!);

      final activeShift = await _apiService.getActiveShift(_token!);

      if (activeShift != null) {
        if (_slotState != SlotState.active) {
          _slotState = SlotState.active;
          _startTime = activeShift.startTime;
          await _storage.write(key: 'slot_state', value: 'active');
          await _prefs.setString(
              'active_slot_start_time', _startTime!.toIso8601String());
          _startTimer();
        }
      } else {
        if (_slotState == SlotState.active) {
          _slotState = SlotState.inactive;
          _startTime = null;
          await _storage.write(key: 'slot_state', value: 'inactive');
          await _prefs.remove('active_slot_start_time');
          _timer?.cancel();
        }
      }

      notifyListeners();
    } catch (e) {
      if (_slotState == SlotState.active) {
        _slotState = SlotState.inactive;
        _startTime = null;
        await _storage.write(key: 'slot_state', value: 'inactive');
        await _prefs.remove('active_slot_start_time');
        _timer?.cancel();
        notifyListeners();
      }
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
      await _apiService.startSlot(
        token: _token!,
        slotTimeRange: slotTimeRange,
        position: position,
        zone: zone,
        selfieImage: imageFile,
      );

      _startTime = DateTime.now();
      _slotState = SlotState.active;

      await _storage.write(key: 'slot_state', value: 'active');
      await _prefs.setString(
          'active_slot_start_time', _startTime!.toIso8601String());

      _startTimer();
      await loadShifts();
      notifyListeners();
    } catch (e) {
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
      rethrow;
    }
  }

  /// Новый метод — устанавливает активную смену вручную
  void setActiveShift(ShiftData activeShift) {
    _slotState = SlotState.active;
    _startTime = activeShift.startTime as DateTime?;
    _storage.write(key: 'slot_state', value: 'active');
    _prefs.setString('active_slot_start_time', _startTime!.toIso8601String());
    _startTimer();
    notifyListeners();
  }

  /// Новый метод — сбрасывает активную смену
  void clearActiveShift() {
    _slotState = SlotState.inactive;
    _startTime = null;
    _storage.write(key: 'slot_state', value: 'inactive');
    _prefs.remove('active_slot_start_time');
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
