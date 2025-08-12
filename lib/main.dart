// main.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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
import 'package:micro_mobility_app/screens/positions_screen.dart';
import 'package:micro_mobility_app/screens/map_screen/zones_screen.dart';
import 'package:micro_mobility_app/screens/admin/admin_panel_screen.dart';

import 'providers/shift_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ru', null);

  final _storage = const FlutterSecureStorage();
  final _apiService = ApiService();
  String initialRoute = '/';
  String?
      initialToken; // Переименовал, чтобы избежать конфликта с 'token' в MyApp

  final String? storedToken = await _storage.read(key: 'jwt_token');

  if (storedToken != null && storedToken.isNotEmpty) {
    initialToken = storedToken; // Сохраняем токен для передачи в MyApp
    try {
      final profile = await _apiService.getUserProfile(storedToken);
      final role = (profile['role'] ?? 'user').toString().toLowerCase();
      final isActive = (profile['is_active'] as bool?) ?? false;

      if (isActive) {
        if (role == 'superadmin') {
          initialRoute = '/admin';
        } else {
          initialRoute = '/dashboard';
        }
      } else {
        initialRoute = '/pending';
      }
    } catch (e) {
      debugPrint('Ошибка получения профиля при старте: $e');
      // Если токен невалиден или ошибка сети, сбрасываем маршрут на логин
      initialRoute = '/';
      await _storage.delete(key: 'jwt_token'); // Удаляем невалидный токен
    }
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        // Передаем ApiService и FlutterSecureStorage в ShiftProvider
        ChangeNotifierProvider(
            create: (_) => ShiftProvider(
                  apiService:
                      _apiService, // Передаем существующий экземпляр ApiService
                  storage:
                      _storage, // Передаем существующий экземпляр FlutterSecureStorage
                  initialToken: initialToken, // Передаем загруженный токен
                )),
      ],
      child: MyApp(initialRoute: initialRoute, token: initialToken),
    ),
  );
}

class MyApp extends StatelessWidget {
  final String initialRoute;
  final String? token;

  const MyApp({super.key, required this.initialRoute, this.token});

  @override
  Widget build(BuildContext context) {
    // ✅ Удаляем этот блок. ShiftProvider теперь сам инициализируется с токеном.
    // WidgetsBinding.instance.addPostFrameCallback((_) {
    //   if (token != null) {
    //     context.read<ShiftProvider>().setToken(token!);
    //     print('✅ Токен передан в ShiftProvider: $token');
    //   }
    // });

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
        '/zones': (context) => ZonesScreen(onZoneSelected: (zone) {}),
        '/admin': (context) => const AdminPanelScreen(),
        '/pending': (context) => const PendingApprovalScreen(),
      },
    );
  }
}
