// // services/shift_scheduler.dart
// import 'dart:convert';
// import 'package:shared_preferences/shared_preferences.dart';

// class ShiftScheduler {
//   List<Employee> employees = [];
//   List<Preference> preferences = [];
//   Map<int, Map<String, List<String?>>> schedule = {};
//   int maxDayShifts = 22;
//   int maxNightShifts = 22;
//   List<int> days = List.generate(31, (i) => i + 1);

//   static const String _localStorageKey = 'shiftSchedulerData';

//   ShiftScheduler() {
//     initSchedule();
//     loadFromLocalStorage();
//   }

//   void initSchedule() {
//     schedule = {};
//     for (var day in days) {
//       schedule[day] = {
//         'day': List.filled(maxDayShifts, null),
//         'night': List.filled(maxNightShifts, null),
//       };
//     }
//   }

//   void addOrUpdateEmployee(String name, String? scoutData, String shift) {
//     if (name.trim().isEmpty) return;

//     final existingIndex = employees.indexWhere((e) => e.name == name);
//     if (existingIndex >= 0) {
//       employees[existingIndex] = employees[existingIndex].copyWith(
//         scoutData: scoutData,
//         preferredShift: shift,
//       );
//     } else {
//       employees.add(Employee(
//         name: name,
//         scoutData: scoutData,
//         preferredShift: shift,
//       ));
//     }
//     saveToLocalStorage();
//   }

//   void removeEmployee(String name) {
//     employees.removeWhere((e) => e.name == name);
//     preferences.removeWhere((p) => p.employee == name);
//     saveToLocalStorage();
//   }

//   void addPreference(String employee, int day, String shift) {
//     if (day < 1 || day > 31) return;

//     final existingIndex =
//         preferences.indexWhere((p) => p.employee == employee && p.day == day);
//     if (existingIndex >= 0) {
//       preferences[existingIndex] = Preference(
//         employee: employee,
//         day: day,
//         shift: shift,
//       );
//     } else {
//       preferences.add(Preference(
//         employee: employee,
//         day: day,
//         shift: shift,
//       ));
//     }
//     saveToLocalStorage();
//   }

//   void removePreference(String employee, int day) {
//     preferences.removeWhere((p) => p.employee == employee && p.day == day);
//     saveToLocalStorage();
//   }

//   void updateShiftLimits(int dayShifts, int nightShifts) {
//     maxDayShifts = dayShifts > 0 ? dayShifts : 22;
//     maxNightShifts = nightShifts > 0 ? nightShifts : 22;
//     initSchedule();
//     saveToLocalStorage();
//   }

//   void generateSchedule() {
//     initSchedule();

//     // Сначала расставляем предпочтения
//     for (var pref in preferences) {
//       if (pref.shift == 'off') continue;
//       var shiftArray = schedule[pref.day]?[pref.shift];
//       if (shiftArray != null) {
//         final emptyIndex = shiftArray.indexWhere((e) => e == null);
//         if (emptyIndex != -1) {
//           shiftArray[emptyIndex] = pref.employee;
//         }
//       }
//     }

//     // Распределяем оставшиеся смены
//     distributeRemainingShifts();
//     saveToLocalStorage();
//   }

//   void distributeRemainingShifts() {
//     // Считаем текущие смены
//     Map<String, Map<String, int>> employeeShifts = {};
//     for (var emp in employees) {
//       employeeShifts[emp.name] = {'day': 0, 'night': 0};
//     }

//     for (var day in days) {
//       for (var shiftType in ['day', 'night']) {
//         final shifts = schedule[day]?[shiftType] ?? [];
//         for (var emp in shifts) {
//           if (emp != null) {
//             employeeShifts[emp]?[shiftType] =
//                 (employeeShifts[emp]?[shiftType] ?? 0) + 1;
//           }
//         }
//       }
//     }

//     // Заполняем пустые слоты
//     for (var day in days) {
//       for (var shiftType in ['day', 'night']) {
//         final max = shiftType == 'day' ? maxDayShifts : maxNightShifts;
//         final shiftArray = schedule[day]?[shiftType] ?? [];
//         for (int i = 0; i < max; i++) {
//           if (shiftArray[i] == null) {
//             final available =
//                 getAvailableEmployees(day, shiftType, employeeShifts);
//             if (available.isNotEmpty) {
//               final selected =
//                   selectEmployeeForShift(available, shiftType, employeeShifts);
//               shiftArray[i] = selected;
//               employeeShifts[selected]?[shiftType] =
//                   (employeeShifts[selected]?[shiftType] ?? 0) + 1;
//             }
//           }
//         }
//       }
//     }
//   }

//   List<String> getAvailableEmployees(
//     int day,
//     String shiftType,
//     Map<String, Map<String, int>> employeeShifts,
//   ) {
//     return employees
//         .where((emp) {
//           final pref = preferences
//               .firstWhereOrNull((p) => p.employee == emp.name && p.day == day);
//           if (pref != null && pref.shift != shiftType && pref.shift != 'any')
//             return false;

//           final currentShifts = employeeShifts[emp.name]?[shiftType] ?? 0;
//           final maxShifts = shiftType == 'day' ? maxDayShifts : maxNightShifts;

//           return currentShifts < maxShifts &&
//               (emp.preferredShift == 'any' || emp.preferredShift == shiftType);
//         })
//         .map((e) => e.name)
//         .toList();
//   }

//   String selectEmployeeForShift(
//     List<String> available,
//     String shiftType,
//     Map<String, Map<String, int>> employeeShifts,
//   ) {
//     return available.reduce((a, b) {
//       final aShifts = employeeShifts[a]?[shiftType] ?? 0;
//       final bShifts = employeeShifts[b]?[shiftType] ?? 0;
//       return aShifts < bShifts ? a : b;
//     });
//   }

//   // === Local Storage ===
//   Future<void> saveToLocalStorage() async {
//     final prefs = await SharedPreferences.getInstance();
//     final data = {
//       'employees': employees
//           .map((e) => {
//                 'name': e.name,
//                 'scoutData': e.scoutData,
//                 'preferredShift': e.preferredShift,
//               })
//           .toList(),
//       'preferences': preferences
//           .map((p) => {
//                 'employee': p.employee,
//                 'day': p.day,
//                 'shift': p.shift,
//               })
//           .toList(),
//       'schedule': schedule.map((day, shifts) => MapEntry(
//           day.toString(),
//           shifts.map((type, emps) =>
//               MapEntry(type, emps.map((e) => e ?? '').toList())))),
//       'maxDayShifts': maxDayShifts,
//       'maxNightShifts': maxNightShifts,
//     };
//     await prefs.setString(_localStorageKey, jsonEncode(data));
//   }

//   Future<void> loadFromLocalStorage() async {
//     final prefs = await SharedPreferences.getInstance();
//     final dataStr = prefs.getString(_localStorageKey);
//     if (dataStr == null) return;

//     try {
//       final data = jsonDecode(dataStr) as Map<String, dynamic>;

//       employees = (data['employees'] as List)
//           .map((e) => Employee(
//                 name: e['name'],
//                 scoutData: e['scoutData'],
//                 preferredShift: e['preferredShift'] ?? 'any',
//               ))
//           .toList();

//       preferences = (data['preferences'] as List)
//           .map((p) => Preference(
//                 employee: p['employee'],
//                 day: p['day'],
//                 shift: p['shift'],
//               ))
//           .toList();

//       final scheduleData = data['schedule'] as Map<String, dynamic>;
//       schedule = scheduleData.map((dayStr, shifts) {
//         final day = int.parse(dayStr);
//         return MapEntry(
//           day,
//           (shifts as Map<String, dynamic>).map((type, emps) {
//             return MapEntry(
//               type,
//               (emps as List).map((e) => e == '' ? null : e as String?).toList(),
//             );
//           }),
//         );
//       });

//       maxDayShifts = data['maxDayShifts'] ?? 22;
//       maxNightShifts = data['maxNightShifts'] ?? 22;
//       initSchedule(); // пересоздаём структуру
//     } catch (e) {
//       print('Error loading scheduler data: $e');
//     }
//   }
// }
