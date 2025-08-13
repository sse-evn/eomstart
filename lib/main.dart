// main.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
import 'package:micro_mobility_app/screens/map_screen/zones_screen.dart';
import 'package:micro_mobility_app/screens/admin/admin_panel_screen.dart';

import 'providers/shift_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ru', null);

  // Инициализация всех зависимостей
  final _storage = const FlutterSecureStorage();
  final _apiService = ApiService();
  final _prefs = await SharedPreferences.getInstance();

  String initialRoute = '/dashboard';
  String? initialToken;

  final String? storedToken = await _storage.read(key: 'jwt_token');

  // 🔹 DEBUG: Печатаем токен для curl
  if (storedToken != null) {
    debugPrint('🔑 JWT Token: $storedToken');
  } else {
    debugPrint('⚠️ Токен не найден в SecureStorage');
  }

  if (storedToken != null && storedToken.isNotEmpty) {
    initialToken = storedToken;
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
      initialRoute = '/';
      await _storage.delete(key: 'jwt_token');
    }
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(
          create: (_) => ShiftProvider(
            apiService: _apiService,
            storage: _storage,
            prefs: _prefs,
            initialToken: initialToken,
          ),
        ),
      ],
      child: MyApp(
        initialRoute: initialRoute,
        token: initialToken,
      ),
    ),
  );
}

class MyApp extends StatefulWidget {
  final String initialRoute;
  final String? token;

  const MyApp({super.key, required this.initialRoute, this.token});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  late ShiftProvider _shiftProvider;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Получаем ShiftProvider после инициализации
    _shiftProvider = Provider.of<ShiftProvider>(context, listen: false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // При возвращении из фона — обновляем данные
      print('✅ Приложение вернулось из фона — обновляем смены');
      _shiftProvider.loadShifts();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

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
      initialRoute: widget.initialRoute,
      debugShowCheckedModeBanner: false,
      routes: {
        '/': (context) => const LoginScreen(),
        '/dashboard': (context) => const DashboardScreen(),
        '/profile': (context) => const ProfileScreen(),
        '/settings': (context) => const SettingsScreen(),
        '/about': (context) => const AboutScreen(),
        '/map': (context) => const MapScreen(),
        '/qr_scanner': (context) => const QrScannerScreen(),
        // '/positions': (context) => const PositionsScreen(),
        // '/zones': (context) => ZonesScreen(onZoneSelected: (zone) {}),
        '/admin': (context) => const AdminPanelScreen(),
        '/pending': (context) => const PendingApprovalScreen(),
      },
    );
  }
}
