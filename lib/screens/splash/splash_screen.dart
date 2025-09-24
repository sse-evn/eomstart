import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:micro_mobility_app/config/config.dart';
import 'package:micro_mobility_app/services/websocket/global_websocket_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
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
      if (token != null) {
        debugPrint(
            'Access token found. Checking if it\'s valid or needs refresh...');

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

          debugPrint(
              'Access token is valid. Status: $status, Role: ${userData['role']}');

          if (status == 'active' && isActive == true) {
            // ✅ Пользователь активен — подключаем WebSocket
            try {
              final globalWebSocketService =
                  Provider.of<GlobalWebSocketService>(context, listen: false);
              await globalWebSocketService
                  .init(); // ← Подключение с токеном из secure storage
            } catch (e) {
              debugPrint('⚠️ WebSocket init failed (non-fatal): $e');
              // Не критично — можно продолжить без карты в реальном времени
            }

            if (mounted) {
              Navigator.pushReplacementNamed(context, '/dashboard');
            }
            return;
          } else {
            if (mounted) {
              Navigator.pushReplacementNamed(context, '/pending');
            }
            return;
          }
        }
      }

      if (mounted) {
        Navigator.pushReplacementNamed(context, '/login');
      }
    } catch (e) {
      debugPrint('Error in splash screen: $e');
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/login');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.green[700],
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.electric_scooter,
              color: Colors.white,
              size: 80,
            ),
            SizedBox(height: 20),
            Text(
              'Оператор микромобильности',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 40),
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
