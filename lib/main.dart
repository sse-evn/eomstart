// lib/main.dart
import 'package:flutter/material.dart';
import 'package:micro_mobility_app/screens/operator_home_page.dart';
import 'package:intl/date_symbol_data_local.dart'; // Импортируем для инициализации локали

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ru', null);
  runApp(const MicroMobilityApp());
}

class MicroMobilityApp extends StatelessWidget {
  const MicroMobilityApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Оператор микромобильности',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.light, // ЯВНО УСТАНАВЛИВАЕМ СВЕТЛУЮ ТЕМУ
        scaffoldBackgroundColor:
            Colors.grey[100], // ЯВНО СВЕТЛЫЙ ФОН ДЛЯ SCAFFOLD
        appBarTheme: AppBarTheme(
          // ЯВНО СВЕТЛАЯ ТЕМА ДЛЯ APPBAR
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
        ),
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const DashboardScreen(),
    );
  }
}
