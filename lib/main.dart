import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;

// Providers
import 'package:micro_mobility_app/settings_provider.dart';
import 'package:micro_mobility_app/providers/shift_provider.dart';

// Services
import 'package:micro_mobility_app/services/api_service.dart';
import 'package:micro_mobility_app/services/websocket/global_websocket_service.dart';
import 'package:micro_mobility_app/services/websocket/location_tracking_service.dart';

// Screens
import 'package:micro_mobility_app/screens/auth_screen/login_screen.dart';
import 'package:micro_mobility_app/screens/auth_screen/pending_screen.dart';
import 'package:micro_mobility_app/screens/dashboard_screen.dart';
import 'package:micro_mobility_app/screens/profile_screens.dart';
import 'package:micro_mobility_app/screens/settings_screen.dart';
import 'package:micro_mobility_app/screens/about_screen.dart';
import 'package:micro_mobility_app/screens/map_screen/map_screens.dart';
import 'package:micro_mobility_app/screens/qr_scanner_screen/qr_scanner_screen.dart';
import 'package:micro_mobility_app/screens/admin/admin_panel_screen.dart';
import 'package:micro_mobility_app/screens/splash/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz_data.initializeTimeZones();
  await initializeDateFormatting('ru', null);

  final _storage = const FlutterSecureStorage();
  final _apiService = ApiService();
  final _prefs = await SharedPreferences.getInstance();

  // Инициализация сервисов
  // final _globalWebSocketService = GlobalWebSocketService(); //снять для подключение wss
  final _locationTrackingService = LocationTrackingService();

  // 🔗 СВЯЗКА: при обновлении локации — отправляем в WebSocket
  _locationTrackingService.setLocationUpdateCallback((location) {
    // _globalWebSocketService.updateCurrentLocation(location); //снять для подключение wss
  });

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
        // Предоставляем сервисы как singleton'ы
        // Provider.value(value: _globalWebSocketService), //снять для подключение wss
        Provider.value(value: _locationTrackingService),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  static const Color appColor = Color(0xff1AB54E);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Оператор микромобильности',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
            seedColor: appColor, brightness: Brightness.light),
        scaffoldBackgroundColor: Colors.grey[100],
        appBarTheme: AppBarTheme(
          foregroundColor: Colors.white,
          elevation: 1,
          titleTextStyle: const TextStyle(
            color: Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: appColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        cardTheme: const CardThemeData(
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: appColor),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: appColor),
          ),
        ),
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      debugShowCheckedModeBanner: false,
      initialRoute: '/splash',
      routes: {
        '/splash': (context) => const SplashScreen(),
        '/login': (context) => const LoginScreen(),
        '/dashboard': (context) => const DashboardScreen(),
        '/profile': (context) => const ProfileScreen(),
        '/settings': (context) => const SettingsScreen(),
        '/about': (context) => const AboutScreen(),
        '/map': (context) => const MapScreen(),
        '/qr_scanner': (context) => const QrScannerScreen(),
        '/admin': (context) => const AdminPanelScreen(),
        '/pending': (context) => const PendingApprovalScreen(),
      },
    );
  }
}
