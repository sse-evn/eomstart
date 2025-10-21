// lib/screens/profile_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:micro_mobility_app/core/themes/theme.dart';
import 'package:micro_mobility_app/providers/theme_provider.dart';
import 'package:micro_mobility_app/services/api_service.dart';
import 'package:micro_mobility_app/screens/auth_screen/login_screen.dart';
import 'package:micro_mobility_app/screens/admin/admin_panel_screen.dart';
import 'package:micro_mobility_app/config/app_config.dart';
import 'package:provider/provider.dart';
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
  String _userRole = 'user';
  bool _isCheckingForUpdates = false;
  final _promoCodeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _profileFuture = _loadProfile();
  }

  @override
  void dispose() {
    _promoCodeController.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _loadProfile() async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token == null) throw Exception('Токен не найден');
      final profile = await _apiService.getUserProfile(token);
      final role = (profile['role'] ?? 'user').toString().toLowerCase();
      if (mounted) {
        setState(() {
          _userRole = role;
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

  Future<void> _checkForUpdates() async {
    if (_isCheckingForUpdates) return;

    setState(() {
      _isCheckingForUpdates = true;
    });

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
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

  Future<bool> _checkServerForUpdate(String currentVersion) async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token != null) {}
    } catch (e) {
      debugPrint('Ошибка проверки версии: $e');
    }
    return false;
  }

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

  Future<void> _downloadUpdate() async {
    try {
      String downloadUrl = '';

      if (Platform.isAndroid) {
        downloadUrl = AppConfig.apkDownloadUrl;
      } else if (Platform.isIOS) {
        downloadUrl = AppConfig.iosAppUrl;
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
    final colorScheme = Theme.of(context).colorScheme;
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkMode = themeProvider.themeData.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Профиль'),
        automaticallyImplyLeading: false,
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
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: colorScheme.secondary,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: colorScheme.shadow,
                              spreadRadius: 1,
                              blurRadius: 12,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          children: [
                            if (['superadmin', 'coordinator', 'supervisor']
                                .contains(_userRole)) ...[
                              _SettingsItem(
                                icon: Icons.admin_panel_settings,
                                title: 'Админ-панель',
                                route: '/admin',
                              ),
                            ],
                            const SizedBox(height: 10),
                            Material(
                              color: Colors.transparent,
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color:
                                          (Colors.green[700]!).withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      isDarkMode
                                          ? Icons.dark_mode
                                          : Icons.light_mode,
                                      color: const Color.fromARGB(
                                          255, 134, 136, 33),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Text(
                                      isDarkMode
                                          ? 'Темная тема'
                                          : 'Светлая тема',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  Switch(
                                    value: isDarkMode,
                                    onChanged: (value) =>
                                        themeProvider.setTheme(
                                            theme: isDarkMode
                                                ? lightMode
                                                : darkMode),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                            _SettingsItem(
                              icon: Icons.card_giftcard,
                              title: 'Промокод',
                              route: '/promo',
                              color: const Color(0xFFAA81AA),
                            ),
                            const SizedBox(height: 10),
                            _SettingsItem(
                              icon: _isCheckingForUpdates
                                  ? Icons.downloading
                                  : Icons.system_update,
                              title: _isCheckingForUpdates
                                  ? 'Проверка обновлений...'
                                  : 'Проверить обновления',
                              onTap: _checkForUpdates,
                              color: _isCheckingForUpdates
                                  ? Colors.orange
                                  : Colors.blue,
                            ),
                            const SizedBox(height: 10),
                            _SettingsItem(
                              icon: Icons.info,
                              title: 'О приложении',
                              route: '/about',
                            ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: colorScheme.secondary,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: colorScheme.shadow,
                              spreadRadius: 1,
                              blurRadius: 12,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(10),
                        child: _SettingsItem(
                          icon: Icons.logout,
                          title: 'Выйти',
                          color: Colors.red,
                          onTap: _logout,
                        ),
                      ),
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
      padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 24),
      child: Column(
        children: [
          CircleAvatar(
            radius: 60,
            backgroundColor: Colors.blueGrey,
            backgroundImage:
                avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
            child: avatarUrl.isEmpty
                ? SvgPicture.asset('assets/images/no_avatar.svg')
                : null,
          ),
          const SizedBox(height: 15),
          Text(
            fullName,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.blueGrey,
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

class _ProfileHeaderShimmer extends StatelessWidget {
  const _ProfileHeaderShimmer();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      child: Column(
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: const Color.fromARGB(255, 240, 242, 243),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.person,
              size: 60,
              color: Color.fromARGB(255, 206, 214, 218),
            ),
          ),
          const SizedBox(height: 20),
          Container(
            width: 200,
            height: 28,
            decoration: BoxDecoration(
              color: const Color.fromARGB(255, 206, 214, 218),
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: 120,
            height: 24,
            decoration: BoxDecoration(
              color: const Color.fromARGB(255, 206, 214, 218),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ],
      ),
    );
  }
}

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

class _SettingsItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color? color;
  final String? route;
  final VoidCallback? onTap;

  const _SettingsItem({
    required this.icon,
    required this.title,
    this.color,
    this.route,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap ??
            (route != null
                ? () {
                    Navigator.pushNamed(context, route!);
                  }
                : null),
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
                style: const TextStyle(
                  fontSize: 16,
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
    );
  }
}
