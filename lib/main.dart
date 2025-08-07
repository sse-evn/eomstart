// lib/main.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:micro_mobility_app/settings_provider.dart';
import 'package:micro_mobility_app/screens/auth_screen/login_screen.dart';
import 'package:micro_mobility_app/screens/dashboard_screen.dart';
import 'package:micro_mobility_app/screens/profile_screens.dart';
import 'package:micro_mobility_app/screens/settings_screen.dart';
import 'package:micro_mobility_app/screens/about_screen.dart';
import 'package:micro_mobility_app/screens/map_screen/map_screens.dart';
import 'package:micro_mobility_app/screens/qr_scanner_screen/qr_scanner_screen.dart';
import 'package:micro_mobility_app/screens/positions_screen.dart';
import 'package:micro_mobility_app/screens/map_screen/zones_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ru', null);
  final _storage = const FlutterSecureStorage();
  final String? token = await _storage.read(key: 'jwt_token');

  runApp(
    ChangeNotifierProvider(
      create: (context) => SettingsProvider(),
      child: MicroMobilityApp(
          initialRoute: token != null && token.isNotEmpty ? '/dashboard' : '/'),
    ),
  );
}

class MicroMobilityApp extends StatelessWidget {
  final String initialRoute;
  const MicroMobilityApp({super.key, required this.initialRoute});

  @override
  Widget build(BuildContext context) {
    final settingsProvider = Provider.of<SettingsProvider>(context);

    return MaterialApp(
      title: 'Оператор микромобильности',
      theme: ThemeData(
        primarySwatch: Colors.green,
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
      initialRoute: initialRoute,
      routes: {
        '/': (context) => const LoginScreen(),
        '/dashboard': (context) => const DashboardScreen(),
        '/profile': (context) => const ProfileScreen(),
        '/settings': (context) => const SettingsScreen(),
        '/about': (context) => const AboutScreen(),
        '/map': (context) => const MapScreen(),
        '/qr_scanner': (context) => const QrScannerScreen(),
        '/positions': (context) => const PositionsScreen(),
        '/zones': (context) => ZonesScreen(
              onZoneSelected: (zone) {},
            ),
      },
    );
  }
}
