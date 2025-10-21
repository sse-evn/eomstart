import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:micro_mobility_app/config/app_config.dart';

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
  bool _disposed = false; // ← для отслеживания dispose

  // Интервал автопроверки — 30 сек
  static const Duration _checkInterval = Duration(seconds: 30);

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
    // Не запускать, если виджет уже удалён
    if (_disposed) return;

    Future.delayed(_checkInterval, () {
      if (!_disposed && mounted && !_isChecking) {
        _checkUserStatus();
        _startPeriodicCheck(); // рекурсивно продолжаем
      }
    });
  }

  @override
  void dispose() {
    _disposed = true; // ← флаг для остановки фоновых операций
    _controller.dispose();
    super.dispose();
  }

  Future<void> _checkUserStatus() async {
    if (_isChecking || _disposed || !mounted) return;

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

        // Явная проверка: только если оба условия выполнены — переходим
        if (status == 'active' && isActive == true) {
          _navigateToDashboard();
          return;
        } else {
          // Любое отклонение от активного состояния = всё ещё на рассмотрении
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
      // Автопроверка продолжится сама — не прерываем цикл
    } finally {
      if (mounted && !_disposed) {
        setState(() {
          _isChecking = false;
        });
      }
    }
  }

  void _navigateToDashboard() {
    if (_disposed || !mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/dashboard', (route) => false);
  }

  void _navigateToLogin() {
    if (_disposed || !mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
  }

  void _showStillPendingMessage() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content:
            Text('Ваш аккаунт всё ещё ожидает подтверждения администратором'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
        backgroundColor: Colors.red,
      ),
    );
  }

  Future<void> _logout() async {
    if (_disposed || !mounted) return;

    // Останавливаем дальнейшие проверки
    _disposed = true;

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
              SizedBox(
                height: 150,
                child: Lottie.asset(
                  'assets/icons/wired-lineal-884-electric-scooter-loop-cycle.json',
                  controller: _controller,
                  onLoaded: (composition) {
                    _controller.duration = composition.duration;
                  },
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 20),
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
              const Text(
                'Ваш аккаунт находится на рассмотрении у администратора. Мы свяжемся с вами в ближайшее время.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 24),
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
              TextButton(
                onPressed: _isChecking ? null : _logout,
                child: const Text(
                  'Выйти из системы',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              const SizedBox(height: 12),
              if (_isChecking)
                const Text(
                  'Проверка статуса...',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                )
              else
                Text(
                  'Следующая проверка через ${_checkInterval.inSeconds} секунд',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
