// lib/screens/profile_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:micro_mobility_app/services/api_service.dart';
import 'package:micro_mobility_app/screens/auth_screen/login_screen.dart';
import 'package:micro_mobility_app/screens/admin/admin_panel_screen.dart';
// 1. Импортируем TasksScreen
// import 'package:micro_mobility_app/screens/tasks/tasks_screen.dart'; // Убедитесь, что путь правильный

// 2. Импорты для OTA обновления
import 'package:upgrader/upgrader.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io' show Platform;
import 'package:package_info_plus/package_info_plus.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final ApiService _apiService = ApiService();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  late Future<Map<String, dynamic>> _profileFuture;
  String _userRole = 'user'; // 2. Храним роль пользователя
  bool _isCheckingForUpdates = false; // 3. Состояние проверки обновлений

  @override
  void initState() {
    super.initState();
    _profileFuture = _loadProfile();
  }

  Future<Map<String, dynamic>> _loadProfile() async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token == null) throw Exception('Токен не найден');
      final profile = await _apiService.getUserProfile(token);
      // Сохраняем роль для UI
      final role = (profile['role'] ?? 'user').toString().toLowerCase();
      if (mounted) {
        setState(() {
          _userRole = role; // 3. Обновляем состояние с ролью
        });
      }
      return profile;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return {};
    }
  }

  Future<void> _refresh() async {
    if (mounted) {
      setState(() {
        _profileFuture = _loadProfile();
      });
    }
  }

  Future<void> _logout() async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token != null) {
        await _apiService.logout(token);
      }
      await _storage.delete(key: 'jwt_token');
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ошибка выхода'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // 4. Функция проверки обновлений
  Future<void> _checkForUpdates() async {
    if (_isCheckingForUpdates) return;

    setState(() {
      _isCheckingForUpdates = true;
    });

    try {
      // Получаем информацию о текущей версии
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      // Здесь можно добавить логику проверки новой версии
      // Например, запрос к API сервера
      final hasUpdate = await _checkServerForUpdate(currentVersion);

      if (hasUpdate && mounted) {
        _showUpdateDialog(currentVersion);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('У вас установлена последняя версия'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка проверки обновлений: $e'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCheckingForUpdates = false;
        });
      }
    }
  }

  // 5. Проверка обновлений на сервере (заглушка)
  Future<bool> _checkServerForUpdate(String currentVersion) async {
    // Здесь должна быть логика проверки новой версии на сервере
    // Пока возвращаем false для примера
    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token != null) {
        // Пример запроса к API для проверки версии
        // final response = await _apiService.checkAppVersion(token);
        // return response['has_update'] == true;
      }
    } catch (e) {
      debugPrint('Ошибка проверки версии: $e');
    }
    return false; // Пока без автоматической проверки
  }

  // 6. Показ диалога обновления
  void _showUpdateDialog(String currentVersion) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Доступно обновление'),
          content: const Text(
              'Доступна новая версия приложения. Рекомендуем обновить для получения последних улучшений и исправлений.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Позже'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _downloadUpdate();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green[700],
              ),
              child: const Text('Обновить'),
            ),
          ],
        );
      },
    );
  }

  // 7. Загрузка обновления
  Future<void> _downloadUpdate() async {
    try {
      String downloadUrl = '';

      if (Platform.isAndroid) {
        // Ссылка на APK файл или Google Play
        downloadUrl =
            'https://example.com/app-release.apk'; // Замените на реальную ссылку
      } else if (Platform.isIOS) {
        // Ссылка на App Store
        downloadUrl =
            'https://apps.apple.com/app/your-app'; // Замените на реальную ссылку
      }

      if (await canLaunchUrl(Uri.parse(downloadUrl))) {
        await launchUrl(Uri.parse(downloadUrl));
      } else {
        throw 'Не удалось открыть ссылку для загрузки';
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка загрузки обновления: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Профиль'),
        centerTitle: true,
        backgroundColor: Colors.green[700],
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // === Заголовок профиля ===
                    FutureBuilder<Map<String, dynamic>>(
                      future: _profileFuture,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const _ProfileHeaderShimmer();
                        }
                        if (snapshot.hasError ||
                            !snapshot.hasData ||
                            snapshot.data!.isEmpty) {
                          return const _ProfileErrorCard();
                        }
                        return _ProfileHeader(user: snapshot.data!);
                      },
                    ),
                    const SizedBox(height: 24),
                    // === Мои задания (только для скаутов) ===
                    // 4. Добавляем новый пункт меню, видимый только для скаутов
                    // if (_userRole == 'scout') ...[
                    //   _buildSectionHeader('Задания'),
                    //   _SettingsItem(
                    //     icon: Icons.assignment, // Иконка заданий
                    //     title: 'Мои задания',
                    //     // Переход к экрану заданий
                    //     onTap: () {
                    //       Navigator.push(
                    //         context,
                    //         MaterialPageRoute(
                    //           builder: (context) => const TasksScreen(),
                    //         ),
                    //       );
                    //     },
                    //   ),
                    //   const Divider(height: 1),
                    // ],
                    // === Настройки ===
                    _buildSectionHeader('Настройки'),
                    _SettingsItem(
                      icon: Icons.settings,
                      title: 'Настройки',
                      route:
                          '/settings', // Убедитесь, что маршрут существует или реализуйте onTap
                    ),
                    const Divider(height: 1),
                    // === Обновление приложения ===
                    _buildSectionHeader('Приложение'),
                    _SettingsItem(
                      icon: _isCheckingForUpdates
                          ? Icons.downloading
                          : Icons.system_update,
                      title: _isCheckingForUpdates
                          ? 'Проверка обновлений...'
                          : 'Проверить обновления',
                      onTap: _checkForUpdates,
                      color:
                          _isCheckingForUpdates ? Colors.orange : Colors.blue,
                    ),
                    const Divider(height: 1),
                    // === Другое ===
                    _buildSectionHeader('Другое'),
                    _SettingsItem(
                      icon: Icons.info,
                      title: 'О приложении',
                      route:
                          '/about', // Убедитесь, что маршрут существует или реализуйте onTap
                    ),
                    // === Админ-панель (только для superadmin) ===
                    if (_userRole == 'superadmin') ...[
                      const Divider(height: 1),
                      _SettingsItem(
                        icon: Icons.admin_panel_settings,
                        title: 'Админ-панель',
                        route:
                            '/admin', // Убедитесь, что маршрут существует или реализуйте onTap
                      ),
                    ],
                    const Divider(height: 1),
                    _SettingsItem(
                      icon: Icons.logout,
                      title: 'Выйти',
                      color: Colors.red,
                      onTap: _logout,
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: Colors.green[700],
        ),
      ),
    );
  }
}

// === Заголовок профиля ===
class _ProfileHeader extends StatelessWidget {
  final Map<String, dynamic> user;
  const _ProfileHeader({required this.user});

  @override
  Widget build(BuildContext context) {
    final firstName = _safeString(user['firstName'] ?? user['first_name']);
    final lastName = _safeString(user['lastName'] ?? user['last_name']);
    final username = _safeString(user['username']);
    final role = _safeString(user['role']).toLowerCase();
    final fullName = (lastName.isNotEmpty || firstName.isNotEmpty)
        ? '$lastName $firstName'.trim()
        : (username.isNotEmpty ? username : 'Пользователь');
    final avatarUrl = _safeString(user['avatarUrl']);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.green[700]!,
            Colors.green[600]!,
          ],
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(30),
          bottomRight: Radius.circular(30),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.3),
            spreadRadius: 2,
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 60,
            backgroundColor: Colors.white.withOpacity(0.9),
            backgroundImage:
                avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
            child: avatarUrl.isEmpty
                ? Icon(
                    Icons.person,
                    size: 60,
                    color: Colors.green[700],
                  )
                : null,
          ),
          const SizedBox(height: 20),
          Text(
            fullName,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _formatRole(role),
              style: const TextStyle(
                fontSize: 16,
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _safeString(dynamic value) {
    if (value == null) return '';
    return value.toString().trim();
  }

  String _formatRole(String role) {
    return {
          'user': 'Пользователь',
          'scout': 'Скаут',
          'supervisor': 'Супервайзер',
          'coordinator': 'Координатор',
          'superadmin': 'Суперадмин',
        }[role] ??
        role.toUpperCase();
  }
}

// === Заглушка при загрузке ===
class _ProfileHeaderShimmer extends StatelessWidget {
  const _ProfileHeaderShimmer();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.green[700]!.withOpacity(0.7),
            Colors.green[600]!.withOpacity(0.5),
          ],
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(30),
          bottomRight: Radius.circular(30),
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.3),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.person,
              size: 60,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 20),
          Container(
            width: 200,
            height: 28,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.3),
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: 120,
            height: 24,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ],
      ),
    );
  }
}

// === Ошибка загрузки ===
class _ProfileErrorCard extends StatelessWidget {
  const _ProfileErrorCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.1),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(30),
          bottomRight: Radius.circular(30),
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: Colors.red,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.error,
              color: Colors.white,
              size: 48,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Не удалось загрузить профиль',
            style: TextStyle(
              color: Colors.red,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Повторяем...'),
                  backgroundColor: Colors.green,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Повторить'),
          ),
        ],
      ),
    );
  }
}

// === Пункт меню ===
// Убедитесь, что этот класс существует в вашем файле
class _SettingsItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color? color;
  final String? route;
  final VoidCallback? onTap; // Добавлено onTap

  const _SettingsItem({
    required this.icon,
    required this.title,
    this.color,
    this.route,
    this.onTap, // Добавлено onTap
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        // Используем onTap, если он передан, иначе пытаемся использовать route
        onTap: onTap ??
            (route != null
                ? () {
                    // Проверка на существование маршрута или реализация навигации
                    Navigator.pushNamed(context, route!);
                  }
                : null),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (color ?? Colors.green[700]!).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: color ?? Colors.green[700],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    color: color ?? Colors.black87,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: Colors.grey[400],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
