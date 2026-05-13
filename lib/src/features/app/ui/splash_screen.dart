import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:micro_mobility_app/src/core/providers/shift_provider.dart';
import 'package:micro_mobility_app/src/core/services/api_service.dart';

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
      if (token == null) {
        if (mounted) Navigator.pushReplacementNamed(context, '/login');
        return;
      }

      final connectivityResult = await Connectivity().checkConnectivity();
      final hasInternet = connectivityResult.any(
        (result) => result != ConnectivityResult.none,
      );

      final shiftProvider = Provider.of<ShiftProvider>(context, listen: false);
      final apiService = ApiService(); // Временный экземпляр

      if (hasInternet) {
        debugPrint(
            'Access token found. Validating online with refresh support...');
        try {
          final profile = await apiService.getUserProfile(token);
          final username = profile['username'] as String?;
          if (username != null) {
            shiftProvider.setCurrentUsername(
                username); // ← Должен быть реализован в ShiftProvider
            debugPrint('Online profile validated. Navigating to dashboard.');
            if (mounted) Navigator.pushReplacementNamed(context, '/dashboard');
            return;
          }
        } catch (e) {
          debugPrint('Profile validation failed (even after refresh): $e');
          // Продолжаем с offline-проверкой
        }
      }

      // Offline fallback: попробуем загрузить смены из кэша
      debugPrint('Trying offline cache...');
      await shiftProvider.loadShifts();

      if (shiftProvider.currentUsername != null) {
        debugPrint('Offline cache valid. Navigating to dashboard.');
        if (mounted) Navigator.pushReplacementNamed(context, '/dashboard');
        return;
      }

      // Если ни онлайн, ни оффлайн — логин
      debugPrint('No valid session found. Redirecting to login.');
      if (mounted) Navigator.pushReplacementNamed(context, '/login');
    } catch (e) {
      debugPrint('Critical error in splash screen: $e');
      if (mounted) Navigator.pushReplacementNamed(context, '/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1B5E20), // Глубокий зеленый, без лишних градиентов
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Чистый и четкий логотип
            const Icon(
              Icons.electric_scooter_rounded,
              color: Colors.white,
              size: 100,
            ),
            const SizedBox(height: 24),
            const Text(
              'EOM START',
              style: TextStyle(
                color: Colors.white,
                fontSize: 36,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 48),
            // Минималистичный лоадер
            const SizedBox(
              width: 30,
              height: 30,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
