import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:micro_mobility_app/models/active_shift.dart' as model;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/shift_data.dart';
import '../services/api_service.dart';

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
        notifyListeners();
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
    if (_token == null) return;

    try {
      final dynamic shiftsData = await _apiService.getShifts(_token!);
      if (shiftsData is List) {
        _shiftHistory = shiftsData
            .map((item) => item as ShiftData)
            .toList()
            .cast<ShiftData>();
      } else {
        _shiftHistory = [];
      }

      final activeShift = await _apiService.getActiveShift(_token!);
      _activeShift = activeShift;

      if (activeShift != null) {
        _startTimer();
      } else {
        _timer?.cancel();
      }

      notifyListeners();
    } catch (e) {
      _shiftHistory = [];
      _activeShift = null;
      _timer?.cancel();
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
    if (_activeShift != null) return;
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

      unawaited(loadShifts());
    } catch (e) {
      rethrow;
    }
  }

  Future<void> endSlot() async {
    if (_token == null) throw Exception('Токен не установлен');
    if (_activeShift == null) return;

    try {
      await _apiService.endSlot(_token!);
      unawaited(loadShifts());
    } catch (e) {
      rethrow;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

// Удалены SlotState, setActiveShift, clearActiveShift
// Вместо них теперь используется `_activeShift` напрямую
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
