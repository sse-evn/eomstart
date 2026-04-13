import 'dart:async';
import 'dart:io';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/foundation.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/geo_tracking_service.dart';
import '../../../core/utils/time_utils.dart';
import 'shift_event.dart';
import 'shift_state.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../app/models/active_shift.dart';

class ShiftBloc extends Bloc<ShiftEvent, ShiftState> {
  final ApiService apiService;
  final FlutterSecureStorage storage = const FlutterSecureStorage();
  Timer? _expiryTimer;

  ShiftBloc({required this.apiService}) : super(ShiftInitial()) {
    on<LoadShift>(_onLoadShift);
    on<StartShiftRequested>(_onStartShift);
    on<EndShiftRequested>(_onEndShift);
    on<CheckShiftExpiry>(_onCheckExpiry);
  }

  @override
  Future<void> close() {
    _expiryTimer?.cancel();
    return super.close();
  }

  void _startExpiryTimer(ActiveShift shift) {
    _expiryTimer?.cancel();
    // Проверяем раз в минуту
    _expiryTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      add(CheckShiftExpiry());
    });
  }

  Future<void> _onCheckExpiry(CheckShiftExpiry event, Emitter<ShiftState> emit) async {
    final currentState = state;
    if (currentState is ShiftActive) {
      if (BreakTimeUtils.isSlotExpired(
        currentState.shift.slotTimeRange,
        shiftStartTime: currentState.shift.startTime,
      )) {
        debugPrint('ShiftBloc: Обнаружено истечение времени слота. Автозавершение.');
        add(EndShiftRequested());
      }
    }
  }

  Future<void> _onLoadShift(LoadShift event, Emitter<ShiftState> emit) async {
    emit(ShiftLoading());
    try {
      final token = await storage.read(key: 'jwt_token');
      if (token == null) {
        emit(ShiftInactive());
        return;
      }

      final activeShift = await apiService.getActiveShift(token);
      if (activeShift != null) {
        // Проверяем на истечение перед активацией
        if (BreakTimeUtils.isSlotExpired(
          activeShift.slotTimeRange,
          shiftStartTime: activeShift.startTime,
        )) {
          debugPrint('ShiftBloc: Найдена активная смена, но время слота истекло.');
          emit(ShiftInactive());
          await stopBackgroundTracking();
          unawaited(apiService.endSlot(token)); 
        } else {
          emit(ShiftActive(activeShift));
          _startExpiryTimer(activeShift);
          await startBackgroundTracking(shiftId: activeShift.id);
        }
      } else {
        emit(ShiftInactive());
        await stopBackgroundTracking();
      }
    } catch (e) {
      emit(ShiftError(e.toString()));
    }
  }

  Future<void> _onStartShift(
      StartShiftRequested event, Emitter<ShiftState> emit) async {
    emit(ShiftLoading());
    try {
      final token = await storage.read(key: 'jwt_token');
      if (token == null) {
        emit(ShiftError("Unauthorized"));
        return;
      }

      final File selfieFile = File(event.selfie.path);

      await apiService.startSlot(
        token: token,
        slotTimeRange: event.slotTimeRange,
        position: event.position,
        zone: event.zone,
        selfieImage: selfieFile,
      );

      // Reload state after starting
      final activeShift = await apiService.getActiveShift(token);
      if (activeShift != null) {
        emit(ShiftActive(activeShift));
        _startExpiryTimer(activeShift);
        await startBackgroundTracking(shiftId: activeShift.id);
      } else {
        emit(ShiftInactive());
      }
    } catch (e) {
      emit(ShiftError(e.toString()));
    }
  }

  Future<void> _onEndShift(
      EndShiftRequested event, Emitter<ShiftState> emit) async {
    _expiryTimer?.cancel();
    emit(ShiftLoading());
    try {
      final token = await storage.read(key: 'jwt_token');
      if (token == null) {
        emit(ShiftError("Unauthorized"));
        return;
      }

      await apiService.endSlot(token);
      await stopBackgroundTracking();
      emit(ShiftInactive());
    } catch (e) {
      emit(ShiftError(e.toString()));
    }
  }
}
