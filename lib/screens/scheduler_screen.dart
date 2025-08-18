// // screens/scheduler_screen.dart
// import 'package:flutter/material.dart';
// import '../services/shift_scheduler.dart';
// import '../models/shift_scheduler.dart';

// class SchedulerScreen extends StatefulWidget {
//   @override
//   _SchedulerScreenState createState() => _SchedulerScreenState();
// }

// class _SchedulerScreenState extends State<SchedulerScreen> {
//   final ShiftScheduler scheduler = ShiftScheduler();
//   int _currentTab = 0;

//   final List<String> _tabNames = [
//     'График',
//     'Сотрудники',
//     'Предпочтения',
//     'Скауты',
//     'Админ'
//   ];

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: Text('Таблица учёта посещений'),
//         bottom: TabBar(
//           tabs: _tabNames.map((name) => Tab(text: name)).toList(),
//           controller:
//               TabController(length: 5, vsync: this, initialIndex: _currentTab),
//           onTap: (index) => setState(() => _currentTab = index),
//         ),
//       ),
//       body: _buildTabContent(),
//     );
//   }

//   Widget _buildTabContent() {
//     switch (_currentTab) {
//       case 0:
//         return _buildScheduleTab();
//       case 1:
//         return _buildEmployeesTab();
//       case 2:
//         return _buildPreferencesTab();
//       case 3:
//         return _buildScoutsTab();
//       case 4:
//         return _buildAdminTab();
//       default:
//         return Container();
//     }
//   }

//   Widget _buildScheduleTab() {
//     return Column(
//       children: [
//         ElevatedButton(
//           onPressed: () {
//             scheduler.generateSchedule();
//             setState(() {});
//           },
//           child: Text('Сгенерировать график'),
//         ),
//         Expanded(
//           child: SingleChildScrollView(
//             scrollDirection: Axis.horizontal,
//             child: Row(
//               children: scheduler.days.map((day) {
//                 return Container(
//                   width: 180,
//                   margin: EdgeInsets.all(8),
//                   child: Column(
//                     crossAxisAlignment: CrossAxisAlignment.start,
//                     children: [
//                       Text('День $day',
//                           style: TextStyle(fontWeight: FontWeight.bold)),
//                       _buildShiftColumn('day', day),
//                       SizedBox(height: 10),
//                       Text('Ночь $day',
//                           style: TextStyle(fontWeight: FontWeight.bold)),
//                       _buildShiftColumn('night', day),
//                     ],
//                   ),
//                 );
//               }).toList(),
//             ),
//           ),
//         ),
//       ],
//     );
//   }

//   Widget _buildShiftColumn(String type, int day) {
//     final shifts = scheduler.schedule[day]?[type] ?? [];
//     return Column(
//       children: shifts.map((emp) {
//         return GestureDetector(
//           onTap: () => _showEmployeeSelector(day, type, shifts.indexOf(emp)),
//           child: Container(
//             margin: EdgeInsets.symmetric(vertical: 2),
//             padding: EdgeInsets.symmetric(vertical: 8),
//             alignment: Alignment.center,
//             decoration: BoxDecoration(
//               color: emp == null ? Colors.grey[200] : Colors.green[100],
//               borderRadius: BorderRadius.circular(6),
//             ),
//             child: Text(emp ?? 'Пусто', style: TextStyle(fontSize: 14)),
//           ),
//         );
//       }).toList(),
//     );
//   }

//   void _showEmployeeSelector(int day, String type, int index) {
//     final employees = ['-', ...scheduler.employees.map((e) => e.name)];
//     final current = scheduler.schedule[day]?[type]?[index] ?? '-';
//     showDialog(
//       context: context,
//       builder: (ctx) {
//         return SimpleDialog(
//           title: Text('Выберите сотрудника'),
//           children: employees.map((name) {
//             return SimpleDialogOption(
//               onPressed: () {
//                 if (name == '-') {
//                   scheduler.schedule[day]?[type]?[index] = null;
//                 } else {
//                   scheduler.schedule[day]?[type]?[index] = name;
//                 }
//                 scheduler.saveToLocalStorage();
//                 Navigator.pop(ctx);
//                 setState(() {});
//               },
//               child: Text(name == '-' ? 'Пусто' : name),
//             );
//           }).toList(),
//         );
//       },
//     );
//   }

//   Widget _buildEmployeesTab() {
//     return Padding(
//       padding: const EdgeInsets.all(16.0),
//       child: Column(
//         children: [
//           TextField(
//               decoration: InputDecoration(labelText: 'Имя сотрудника'),
//               controller: _nameCtrl),
//           TextField(
//               decoration: InputDecoration(labelText: 'Данные скаута'),
//               controller: _scoutCtrl),
//           DropdownButtonFormField<String>(
//             value: _shiftType,
//             items: ['any', 'day', 'night']
//                 .map((s) => DropdownMenuItem(
//                     value: s,
//                     child: Text(s == 'any'
//                         ? 'Любая'
//                         : s == 'day'
//                             ? 'День'
//                             : 'Ночь')))
//                 .toList(),
//             onChanged: (v) => setState(() => _shiftType = v!),
//           ),
//           ElevatedButton(
//               onPressed: _addEmployee, child: Text('Добавить/Обновить')),
//           SizedBox(height: 20),
//           Expanded(
//             child: ListView.builder(
//               itemCount: scheduler.employees.length,
//               itemBuilder: (ctx, i) {
//                 final e = scheduler.employees[i];
//                 return ListTile(
//                   title: Text(e.name),
//                   subtitle: Text(
//                       'Скаут: ${e.scoutData ?? 'Нет данных'} | Смена: ${e.preferredShift}'),
//                   trailing: IconButton(
//                     icon: Icon(Icons.delete, color: Colors.red),
//                     onPressed: () {
//                       scheduler.removeEmployee(e.name);
//                       setState(() {});
//                     },
//                   ),
//                 );
//               },
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   final _nameCtrl = TextEditingController();
//   final _scoutCtrl = TextEditingController();
//   String _shiftType = 'any';

//   void _addEmployee() {
//     scheduler.addOrUpdateEmployee(
//       _nameCtrl.text,
//       _scoutCtrl.text.isEmpty ? null : _scoutCtrl.text,
//       _shiftType,
//     );
//     _nameCtrl.clear();
//     _scoutCtrl.clear();
//     setState(() {});
//   }

//   Widget _buildPreferencesTab() {
//     return Padding(
//       padding: const EdgeInsets.all(16.0),
//       child: Column(
//         children: [
//           DropdownButton<String>(
//             value: scheduler.employees.isEmpty
//                 ? null
//                 : scheduler.employees[0].name,
//             items: scheduler.employees
//                 .map(
//                     (e) => DropdownMenuItem(value: e.name, child: Text(e.name)))
//                 .toList(),
//             onChanged: (v) => setState(() => _prefEmployee = v!),
//             hint: Text('Сотрудник'),
//           ),
//           TextField(
//             decoration: InputDecoration(labelText: 'День (1-31)'),
//             keyboardType: TextInputType.number,
//             onChanged: (v) => _prefDay = int.tryParse(v) ?? 1,
//           ),
//           DropdownButton<String>(
//             value: _prefShift,
//             items: ['day', 'night', 'off']
//                 .map((s) => DropdownMenuItem(
//                     value: s,
//                     child: Text(s == 'off'
//                         ? 'Выходной'
//                         : s == 'day'
//                             ? 'День'
//                             : 'Ночь')))
//                 .toList(),
//             onChanged: (v) => setState(() => _prefShift = v!),
//           ),
//           ElevatedButton(
//               onPressed: _addPreference, child: Text('Добавить предпочтение')),
//           SizedBox(height: 20),
//           Expanded(
//             child: ListView.builder(
//               itemCount: scheduler.preferences.length,
//               itemBuilder: (ctx, i) {
//                 final p = scheduler.preferences[i];
//                 return ListTile(
//                   title: Text('${p.employee} — День ${p.day} (${p.shift})'),
//                   trailing: IconButton(
//                     icon: Icon(Icons.delete, color: Colors.red),
//                     onPressed: () {
//                       scheduler.removePreference(p.employee, p.day);
//                       setState(() {});
//                     },
//                   ),
//                 );
//               },
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   String _prefEmployee = '';
//   int _prefDay = 1;
//   String _prefShift = 'day';

//   void _addPreference() {
//     if (_prefEmployee.isEmpty) return;
//     scheduler.addPreference(_prefEmployee, _prefDay, _prefShift);
//     setState(() {});
//   }

//   Widget _buildScoutsTab() {
//     final scouts = scheduler.employees
//         .map((e) => e.scoutData)
//         .where((d) => d != null)
//         .toSet()
//         .map((d) => d!)
//         .toList();
//     return ListView.builder(
//       itemCount: scouts.length,
//       itemBuilder: (ctx, i) => ListTile(title: Text(scouts[i])),
//     );
//   }

//   Widget _buildAdminTab() {
//     final dayCtrl =
//         TextEditingController(text: scheduler.maxDayShifts.toString());
//     final nightCtrl =
//         TextEditingController(text: scheduler.maxNightShifts.toString());
//     return Padding(
//       padding: const EdgeInsets.all(16.0),
//       child: Column(
//         children: [
//           Text('Настройки лимитов',
//               style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
//           TextField(
//               controller: dayCtrl,
//               decoration: InputDecoration(labelText: 'Макс. дневных смен'),
//               keyboardType: TextInputType.number),
//           TextField(
//               controller: nightCtrl,
//               decoration: InputDecoration(labelText: 'Макс. ночных смен'),
//               keyboardType: TextInputType.number),
//           ElevatedButton(
//             onPressed: () {
//               scheduler.updateShiftLimits(int.tryParse(dayCtrl.text) ?? 22,
//                   int.tryParse(nightCtrl.text) ?? 22);
//               setState(() {});
//             },
//             child: Text('Сохранить'),
//           ),
//         ],
//       ),
//     );
//   }
// }
