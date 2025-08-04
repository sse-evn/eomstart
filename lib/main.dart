import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:micro_mobility_app/screens/operator_home_page.dart'; // Предполагаемый главный экран
import 'package:micro_mobility_app/settings_provider.dart'; // Импортируем наш Provider

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ru', null);
  runApp(
    // Оборачиваем все приложение в ChangeNotifierProvider
    ChangeNotifierProvider(
      create: (context) => SettingsProvider(),
      child: const MicroMobilityApp(),
    ),
  );
}

class MicroMobilityApp extends StatelessWidget {
  const MicroMobilityApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Получаем состояние из провайдера
    final settingsProvider = Provider.of<SettingsProvider>(context);

    return MaterialApp(
      title: 'Оператор микромобильности',
      // Используем состояние из провайдера для определения темы
      theme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: settingsProvider.currentBrightness,
        scaffoldBackgroundColor:
            settingsProvider.currentBrightness == Brightness.light
                ? Colors.grey[100]
                : Colors.grey[900],
        appBarTheme: AppBarTheme(
          backgroundColor:
              settingsProvider.currentBrightness == Brightness.light
                  ? Colors.white
                  : Colors.grey[800],
          foregroundColor:
              settingsProvider.currentBrightness == Brightness.light
                  ? Colors.black
                  : Colors.white,
          elevation: 0,
        ),
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const DashboardScreen(),
    );
  }
}
