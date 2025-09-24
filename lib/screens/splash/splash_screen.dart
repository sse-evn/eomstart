import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:micro_mobility_app/config/config.dart';
import 'package:micro_mobility_app/services/websocket/global_websocket_service.dart';
import 'package:micro_mobility_app/providers/shift_provider.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() =>
      _SplashScreenState(); // ← ИСПРАВЛЕНО: SplashScreen, не SplashScreenState
}

class _SplashScreenState extends State<SplashScreen> {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      debugPrint('Checking tokens on app start...');

      final token = await _storage.read(key: 'jwt_token');
      if (token == null) {
        if (mounted) Navigator.pushReplacementNamed(context, '/login');
        return;
      }

      final connectivityResult = await Connectivity().checkConnectivity();
      final hasInternet = connectivityResult.any(
        (result) => result != ConnectivityResult.none,
      );

      if (hasInternet) {
        debugPrint('Access token found. Validating online...');
        final response = await http.get(
          Uri.parse(AppConfig.profileUrl),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        );

        if (response.statusCode == 200) {
          final userData = jsonDecode(response.body) as Map<String, dynamic>;
          final status = userData['status'] as String?;
          final isActive = userData['is_active'] as bool?;

          if (status == 'active' && isActive == true) {
            _connectWebSocketAndNavigate();
            return;
          } else {
            if (mounted) Navigator.pushReplacementNamed(context, '/pending');
            return;
          }
        }
      }

      // Offline fallback
      debugPrint('No internet or profile check failed. Trying cache...');
      final shiftProvider = Provider.of<ShiftProvider>(context, listen: false);

      // 🔥 ВАЖНО: убедитесь, что в ShiftProvider есть публичный метод loadFromCache()
      // Если нет — временно используем loadShifts(), который сам проверит сеть и кэш
      await shiftProvider
          .loadShifts(); // ← безопасно: не делает запрос без интернета

      if (shiftProvider.currentUsername != null) {
        debugPrint('Cache hit. Navigating to dashboard offline.');
        if (mounted) Navigator.pushReplacementNamed(context, '/dashboard');
        return;
      }

      if (mounted) Navigator.pushReplacementNamed(context, '/login');
    } catch (e) {
      debugPrint('Error in splash screen: $e');
      if (mounted) Navigator.pushReplacementNamed(context, '/login');
    }
  }

  void _connectWebSocketAndNavigate() {
    try {
      final globalWebSocketService =
          Provider.of<GlobalWebSocketService>(context, listen: false);
      globalWebSocketService.init();
    } catch (e) {
      debugPrint('⚠️ WebSocket init failed (non-fatal): $e');
    }
    if (mounted) Navigator.pushReplacementNamed(context, '/dashboard');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.green[700],
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.electric_scooter, color: Colors.white, size: 80),
            const SizedBox(height: 20),
            Text(
              'Оператор микромобильности',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 40),
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
