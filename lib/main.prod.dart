// lib/main.prod.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;

import 'package:micro_mobility_app/settings_provider.dart';
import 'package:micro_mobility_app/services/api_service.dart';
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

import 'providers/shift_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz_data.initializeTimeZones();
  await initializeDateFormatting('ru', null);

  final _storage = const FlutterSecureStorage();
  final _apiService = ApiService();
  final _prefs = await SharedPreferences.getInstance();

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
      ],
      child: MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Оператор микромобильности',
      theme: ThemeData(
        primarySwatch: Colors.green,
        scaffoldBackgroundColor: Colors.grey[100],
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
        ),
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      debugShowCheckedModeBanner: false,
      initialRoute: '/splash',
      routes: {
        '/splash': (context) => const SplashScreen(),
        '/': (context) => const LoginScreen(),
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
