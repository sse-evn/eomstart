// lib/screens/auth_screen/pending_screen.dart
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

class PendingApprovalScreen extends StatefulWidget {
  const PendingApprovalScreen({super.key});

  @override
  State<PendingApprovalScreen> createState() => _PendingApprovalScreenState();
}

class _PendingApprovalScreenState extends State<PendingApprovalScreen>
    with TickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF388E3C); // Ваш основной цвет

    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: Center(
        child: Card(
          elevation: 10,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          margin: const EdgeInsets.symmetric(horizontal: 32),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Lottie Анимация — часы / ожидание
                SizedBox(
                  height: 120,
                  child: Lottie.asset(
                    'assets/icons/Insider-loading.json', // ← Путь к вашему Lottie-файлу
                    controller: _controller,
                    onLoaded: (composition) {
                      _controller.duration = composition.duration;
                    },
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Ожидание подтверждения',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: primaryColor,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Ваш аккаунт находится на рассмотрении у администратора. Пожалуйста, подождите — мы свяжемся с вами в ближайшее время.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Проверка обычно занимает не более 24 часов',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[500],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
