import 'package:equatable/equatable.dart';
import '../../app/models/active_shift.dart';

abstract class ShiftState extends Equatable {
  const ShiftState();

  @override
  List<Object?> get props => [];
}

class ShiftInitial extends ShiftState {}

class ShiftLoading extends ShiftState {}

class ShiftActive extends ShiftState {
  final ActiveShift shift;
  const ShiftActive(this.shift);

  @override
  List<Object?> get props => [shift];
}

class ShiftInactive extends ShiftState {}

class ShiftError extends ShiftState {
  final String message;
  const ShiftError(this.message);

  @override
  List<Object?> get props => [message];
}
