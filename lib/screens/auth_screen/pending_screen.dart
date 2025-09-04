import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:micro_mobility_app/config/config.dart';

class PendingApprovalScreen extends StatefulWidget {
  const PendingApprovalScreen({super.key});

  @override
  State<PendingApprovalScreen> createState() => _PendingApprovalScreenState();
}

class _PendingApprovalScreenState extends State<PendingApprovalScreen>
    with TickerProviderStateMixin {
  late final AnimationController _controller;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  bool _isChecking = false;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(duration: const Duration(seconds: 3), vsync: this)
          ..repeat();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkUserStatus();
    });
    _startPeriodicCheck();
  }

  void _startPeriodicCheck() {
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted && !_isChecking) {
        _checkUserStatus();
        _startPeriodicCheck();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _checkUserStatus() async {
    if (_isChecking || !mounted) return;
    setState(() {
      _isChecking = true;
    });

    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token == null) {
        _navigateToLogin();
        return;
      }

      final response = await http.get(
        Uri.parse(AppConfig.profileUrl),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json'
        },
      );

      if (response.statusCode == 200) {
        final userData = jsonDecode(response.body) as Map<String, dynamic>;
        final status = userData['status'] as String?;
        final isActive = userData['is_active'] as bool?;
        debugPrint('User status: $status, is_active: $isActive');
        if (status == 'active' && isActive == true) {
          _navigateToDashboard();
          return;
        } else {
          _showStillPendingMessage();
        }
      } else if (response.statusCode == 401) {
        _navigateToLogin();
        return;
      } else {
        _showError('Ошибка проверки статуса: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error checking user status: $e');
      _showError('Ошибка соединения: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isChecking = false;
        });
      }
    }
  }

  void _navigateToDashboard() {
    Navigator.pushNamedAndRemoveUntil(context, '/dashboard', (route) => false);
  }

  void _navigateToLogin() {
    Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
  }

  void _showStillPendingMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content:
              Text('Ваш аккаунт всё ещё ожидает подтверждения администратором'),
          duration: Duration(seconds: 2)),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 3),
          backgroundColor: Colors.red),
    );
  }

  Future<void> _logout() async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token != null) {
        await http.post(
          Uri.parse(AppConfig.logoutUrl),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json'
          },
        );
      }
    } catch (e) {
      debugPrint('Error during logout: $e');
    } finally {
      await _storage.delete(key: 'jwt_token');
      await _storage.delete(key: 'refresh_token');
      _navigateToLogin();
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Colors.green[700]!;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Лого или анимация
              SizedBox(
                height: 150,
                child: Lottie.asset(
                  'assets/icons/wired-lineal-884-electric-scooter-loop-cycle.json', // Замени на свою анимацию
                  controller: _controller,
                  onLoaded: (composition) {
                    _controller.duration = composition.duration;
                  },
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 20),

              // Заголовок
              Text(
                'Ожидание подтверждения',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: primaryColor,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),

              // Подзаголовок
              const Text(
                'Ваш аккаунт находится на рассмотрении у администратора. Мы свяжемся с вами в ближайшее время.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 24),

              // Информация о времени
              Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: primaryColor.withOpacity(0.3)),
                ),
                child: const Text(
                  'Проверка обычно занимает не более 24 часов',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.green,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
              const SizedBox(height: 30),

              // Кнопка "Проверить статус"
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _isChecking ? null : _checkUserStatus,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: _isChecking
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(Colors.white),
                          ),
                        )
                      : const Icon(Icons.refresh,
                          size: 18, color: Colors.white),
                  label: _isChecking
                      ? const Text('Проверка...',
                          style: TextStyle(color: Colors.white))
                      : const Text('Проверить статус',
                          style: TextStyle(color: Colors.white)),
                ),
              ),
              const SizedBox(height: 12),

              // Выход из системы
              TextButton(
                onPressed: _isChecking ? null : _logout,
                child: const Text(
                  'Выйти из системы',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              const SizedBox(height: 12),

              // Автопроверка
              if (_isChecking)
                const Text(
                  'Автопроверка каждые 5 секунд...',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
