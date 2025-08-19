import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '/services/api_service.dart';
import '/providers/shift_provider.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final _storage = const FlutterSecureStorage();
  final _apiService = ApiService();

  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
  }

  Future<void> _checkLoginStatus() async {
    try {
      final String? token = await _storage.read(key: 'jwt_token');
      if (token == null) {
        _navigateTo('/'); // Login
        return;
      }

      final profile = await _apiService.getUserProfile(token);
      final isActive = (profile['is_active'] as bool?) ?? false;
      final role = (profile['role'] ?? 'user').toString().toLowerCase();

      final shiftProvider = Provider.of<ShiftProvider>(context, listen: false);
      await shiftProvider.setToken(token);

      if (!isActive && role != 'superadmin') {
        _navigateTo('/pending');
      } else if (role == 'superadmin') {
        _navigateTo('/admin');
      } else {
        _navigateTo('/dashboard');
      }
    } catch (e) {
      await _storage.delete(key: 'jwt_token');
      _navigateTo('/');
    }
  }

  void _navigateTo(String route) {
    if (mounted) {
      Navigator.pushReplacementNamed(context, route);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.green[800],
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 100,
              height: 100,
              child: CircularProgressIndicator(
                strokeWidth: 4,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Загрузка...',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge!
                  .copyWith(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
