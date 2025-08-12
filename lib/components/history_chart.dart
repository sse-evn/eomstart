// // components/history_chart.dart
// import 'package:flutter/material.dart';
// import 'package:intl/intl.dart' show DateFormat;
// import 'package:syncfusion_flutter_charts/charts.dart';
// import '../../models/shift_data.dart';

// class HistoryChart extends StatelessWidget {
//   final List<ShiftData> shifts;

//   const HistoryChart({super.key, required this.shifts});

//   @override
//   Widget build(BuildContext context) {
//     final filteredShifts =
//         shifts.reversed.take(7).toList(); // Показываем последние 7 дней

//     return Card(
//       child: Padding(
//         padding: const EdgeInsets.all(16),
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             // Заголовок
//             Text(
//               'Ваша активность',
//               style: Theme.of(context)
//                   .textTheme
//                   .titleMedium
//                   ?.copyWith(fontWeight: FontWeight.bold),
//             ),
//             const SizedBox(height: 4),
//             Text(
//               'Последние 7 дней',
//               style: TextStyle(fontSize: 12, color: Colors.grey),
//             ),
//             const SizedBox(height: 12),

//             // График
//             SizedBox(
//               height: 200,
//               child: SfCartesianChart(
//                 plotAreaBorderWidth: 0,
//                 primaryXAxis: CategoryAxis(
//                   majorGridLines: const MajorGridLines(width: 0),
//                   labelStyle:
//                       const TextStyle(fontSize: 10, color: Colors.black54),
//                   labelPlacement: LabelPlacement.betweenTicks,
//                   edgeLabelPlacement: EdgeLabelPlacement.shift,
//                 ),
//                 primaryYAxis: NumericAxis(
//                   minimum: 0,
//                   axisLine: const AxisLine(width: 0),
//                   majorTickLines: const MajorTickLines(size: 0),
//                   labelStyle:
//                       const TextStyle(fontSize: 10, color: Colors.black54),
//                   title: AxisTitle(
//                     text: 'Часы',
//                     textStyle:
//                         const TextStyle(fontSize: 10, color: Colors.grey),
//                   ),
//                 ),
//                 series: <CartesianSeries<ShiftData, String>>[
//                   ColumnSeries<ShiftData, String>(
//                     dataSource: filteredShifts,
//                     xValueMapper: (data, _) =>
//                         DateFormat('dd MMM').format(data.date),
//                     yValueMapper: (data, _) => _parseHours(data.workedTime),
//                     name: 'Отработано',
//                     color: Colors.green[700],
//                     borderRadius: BorderRadius.circular(8),
//                     spacing: 0.4,
//                     // Подсказка при нажатии
//                     // trackballSettings: TrackballSettings(
//                     //   enable: true,
//                     //   tooltipSettings: const InteractiveTooltip(
//                     //     format: 'point.x: point.y ч',
//                     //     textStyle: TextStyle(fontSize: 12),
//                     //   ),
//                     // ),
//                   ),
//                 ],
//                 tooltipBehavior: TooltipBehavior(
//                   enable: true,
//                   format: 'point.x\npoint.y ч',
//                   textStyle: const TextStyle(fontSize: 12),
//                 ),
//               ),
//             ),

//             // Легенда и пояснение
//             const SizedBox(height: 12),
//             Text(
//               'Совет: чем выше столбец — тем больше вы проработали в этот день.',
//               style:
//                   TextStyle(fontSize: 12, color: Colors.grey[700], height: 1.4),
//             ),
//           ],
//         ),
//       ),
//     );
//   }

//   double _parseHours(String workedTime) {
//     final match = RegExp(r'(\d+)ч\s*(\d*)мин').firstMatch(workedTime);
//     if (match != null) {
//       final hours = int.tryParse(match.group(1)!) ?? 0;
//       final minutes = int.tryParse(match.group(2) ?? '0') ?? 0;
//       return hours + minutes / 60;
//     }
//     return 0;
//   }
// }
