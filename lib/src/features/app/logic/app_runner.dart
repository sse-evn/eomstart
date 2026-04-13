import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:hive_flutter/hive_flutter.dart' show Hive, HiveX;
import 'package:micro_mobility_app/src/features/app/app.dart';
import 'package:micro_mobility_app/src/core/providers/theme_provider.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;

// Геолокация и разрешения
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

// Providers
import 'package:micro_mobility_app/src/core/providers/settings_provider.dart';
import 'package:micro_mobility_app/src/core/providers/shift_provider.dart';

// Services
import 'package:micro_mobility_app/src/core/services/api_service.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:micro_mobility_app/src/features/home/bloc/shift_bloc.dart';
import 'package:micro_mobility_app/src/features/home/bloc/shift_event.dart';


final class AppRunner {
  const AppRunner();

  Future<void> initializeAndRun() async {
    WidgetsFlutterBinding.ensureInitialized();
    await setup();
    await Hive.initFlutter();
    await FMTCObjectBoxBackend().initialise();
    tz_data.initializeTimeZones();
    await initializeDateFormatting('ru', null);
    final storage = const FlutterSecureStorage();
    final apiService = ApiService();
    final prefs = await SharedPreferences.getInstance();

    await _requestAllPermissions();

    runApp(
      MultiBlocProvider(
        providers: [
          BlocProvider(
            create: (_) => ShiftBloc(apiService: apiService)..add(LoadShift()),
          ),
        ],
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => SettingsProvider()),
            ChangeNotifierProvider(
              create: (_) => ShiftProvider(
                apiService: apiService,
                storage: storage,
                prefs: prefs,
              ),
            ),
            ChangeNotifierProvider(
              create: (_) => ThemeProvider(),
            )
          ],
          child: const App(),
        ),
      ),
    );
  }

  Future<void> setup() async {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);

  }
}



/// 🔒 Запрос всех нужных разрешений
Future<void> _requestAllPermissions() async {
  // Проверяем, включена ли геолокация вообще
  bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    await Geolocator.openLocationSettings();
  }

  // Проверяем и запрашиваем права на доступ к геопозиции
  LocationPermission permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }

  if (permission == LocationPermission.deniedForever) {
    await openAppSettings();
  }

  // Запрашиваем также права на камеру и уведомления
  await [
    Permission.camera,
    Permission.notification,
  ].request();
}

