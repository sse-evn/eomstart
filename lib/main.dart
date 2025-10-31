import 'package:flutter/material.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart'
    show FMTCObjectBoxBackend, FMTCRoot, FMTCStore;
import 'package:hive_flutter/hive_flutter.dart' show Hive, HiveX;
import 'package:micro_mobility_app/providers/theme_provider.dart';
import 'package:micro_mobility_app/screens/profile/promo_code_screen.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;

// Геолокация и разрешения
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

// Providers
import 'package:micro_mobility_app/settings_provider.dart';
import 'package:micro_mobility_app/providers/shift_provider.dart';

// Services
import 'package:micro_mobility_app/services/api_service.dart';

// Screens
import 'package:micro_mobility_app/screens/auth_screen/login_screen.dart';
import 'package:micro_mobility_app/screens/auth_screen/pending_screen.dart';
import 'package:micro_mobility_app/screens/bottom_navigation/bottom_navigation.dart';
import 'package:micro_mobility_app/screens/profile/profile_screens.dart';
import 'package:micro_mobility_app/screens/profile/settings_screen.dart';
import 'package:micro_mobility_app/screens/about_screen.dart';
import 'package:micro_mobility_app/screens/map_screen/map_screens.dart';
import 'package:micro_mobility_app/screens/qr_scanner_screen/qr_scanner_screen.dart';
import 'package:micro_mobility_app/screens/admin/admin_panel_screen.dart';
import 'package:micro_mobility_app/screens/splash/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  // Остальная инициализация
  await FMTCObjectBoxBackend().initialise();
  tz_data.initializeTimeZones();
  await initializeDateFormatting('ru', null);
  final _storage = const FlutterSecureStorage();
  final _apiService = ApiService();
  final _prefs = await SharedPreferences.getInstance();

  await _requestAllPermissions();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(
          create: (_) => ShiftProvider(
            apiService: _apiService,
            storage: _storage,
            prefs: _prefs,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => ThemeProvider(),
        )
      ],
      child: const MyApp(),
    ),
  );
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

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  static const Color appColor = Color(0xff1AB54E);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Оператор микромобильности',
      theme: Provider.of<ThemeProvider>(context).themeData,
      debugShowCheckedModeBanner: false,
      initialRoute: '/splash',
      routes: {
        '/splash': (context) => const SplashScreen(),
        '/login': (context) => const LoginScreen(),
        '/dashboard': (context) => const DashboardScreen(),
        '/profile': (context) => const ProfileScreen(),
        '/settings': (context) => const SettingsScreen(),
        '/about': (context) => const AboutScreen(),
        '/promo': (context) => const PromoCodeScreen(),
        '/map': (context) => const MapScreen(),
        '/qr_scanner': (context) => const QrScannerScreen(),
        '/admin': (context) => const AdminPanelScreen(),
        '/pending': (context) => const PendingApprovalScreen(),
      },
    );
  }
}
