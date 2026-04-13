import 'package:equatable/equatable.dart';
import 'package:image_picker/image_picker.dart';

abstract class ShiftEvent extends Equatable {
  const ShiftEvent();

  @override
  List<Object?> get props => [];
}

class LoadShift extends ShiftEvent {}

class StartShiftRequested extends ShiftEvent {
  final String slotTimeRange;
  final String position;
  final String zone;
  final XFile selfie;

  const StartShiftRequested({
    required this.slotTimeRange,
    required this.position,
    required this.zone,
    required this.selfie,
  });

  @override
  List<Object?> get props => [slotTimeRange, position, zone, selfie];
}

class EndShiftRequested extends ShiftEvent {}

class CheckShiftExpiry extends ShiftEvent {}
