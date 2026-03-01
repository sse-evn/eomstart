// lib/screens/profile_screen.dart
import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:micro_mobility_app/src/core/themes/theme.dart';
import 'package:micro_mobility_app/src/core/providers/theme_provider.dart';
import 'package:micro_mobility_app/src/core/providers/shift_provider.dart';
import 'package:micro_mobility_app/src/features/auth_screen/login_screen.dart';
import 'package:micro_mobility_app/src/core/config/app_config.dart';
import 'package:micro_mobility_app/src/core/services/api_service.dart' show ApiService;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Импортируем функции трекинга (предполагается, что они экспортированы)
import '../../core/services/geo_tracking_service.dart'
    show startBackgroundTracking, stopBackgroundTracking;

const String _SHARED_PREFS_BG_RUNNING_KEY = 'is_bg_geo_tracking_running';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _ProfileScreenBody();
  }
}

class _ProfileScreenBody extends StatefulWidget {
  const _ProfileScreenBody();

  @override
  State<_ProfileScreenBody> createState() => _ProfileScreenBodyState();
}

class _ProfileScreenBodyState extends State<_ProfileScreenBody> {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  bool _isCheckingForUpdates = false;
  final _promoCodeController = TextEditingController();

  bool _isGeoTrackingEnabled = false;
  bool _isLoadingGeoStatus = true;
  bool _hasLoadedGeoStatusOnce = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final provider = context.read<ShiftProvider>();
      if (!provider.hasLoadedProfile) {
        await provider.loadProfile();
      }
      // Загружаем статус геотрекинга один раз при инициализации
      await _loadGeoTrackingStatus();
    });
  }

  // Убрали didChangeDependencies — лишние перерисовки вызывали странное поведение

  Future<void> _loadGeoTrackingStatus() async {
    // Запускаем индикатор
    if (mounted) {
      setState(() {
        _isLoadingGeoStatus = true;
      });
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final isRunning = prefs.getBool(_SHARED_PREFS_BG_RUNNING_KEY) ?? false;

      if (mounted) {
        setState(() {
          _isGeoTrackingEnabled = isRunning;
          _isLoadingGeoStatus = false;
          _hasLoadedGeoStatusOnce = true;
        });
      }
    } catch (e) {
      debugPrint('Ошибка загрузки статуса геотрекинга: $e');
      if (mounted) {
        setState(() {
          _isLoadingGeoStatus = false;
        });
      }
    }
  }

  Future<void> _toggleGeoTracking(bool newValue) async {
    // Блокируем переключатель на время операции
    if (_isLoadingGeoStatus) return;

    // Оптимистично меняем положение переключателя (UX)
    if (mounted) {
      setState(() {
        _isGeoTrackingEnabled = newValue;
        _isLoadingGeoStatus = true;
      });
    }

    try {
      if (newValue) {
        int? activeShiftId = context.read<ShiftProvider>().activeShift?.id;
        if (activeShiftId != null && activeShiftId > 0) {
          await startBackgroundTracking(shiftId: activeShiftId);
        } else {
          // Нельзя включить — нет смены
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content:
                    Text('Невозможно включить трекинг: нет активной смены'),
                backgroundColor: Colors.orange,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
          // Откатываем переключатель
          if (mounted) {
            setState(() {
              _isGeoTrackingEnabled = false;
            });
          }
        }
      } else {
        await stopBackgroundTracking();
      }
    } catch (e) {
      debugPrint('Ошибка переключения геотрекинга: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка при изменении статуса трекинга: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      // Всегда перечитываем статус из SharedPreferences, чтобы синхронизировать состояние
      await _loadGeoTrackingStatus();
    }
  }

  @override
  void dispose() {
    _promoCodeController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final provider = context.read<ShiftProvider>();
    await provider.loadProfile(force: true);
  }

  Future<void> _logout() async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token != null) {
        final apiService = ApiService();
        await apiService.logout(token);
      }
      await _storage.delete(key: 'jwt_token');
      await _storage.delete(key: 'refresh_token');
      context.read<ShiftProvider>().logout();
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
      if (token != null) {
        // TODO: запросите актуальную версию с вашего API и сравните
      }
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







  ///
  /// UI
  ///

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Профиль'),
        automaticallyImplyLeading: false,
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: Consumer<ShiftProvider>(
          builder: (context, provider, child) {
            final colorScheme = Theme.of(context).colorScheme;
            final themeProvider = Provider.of<ThemeProvider>(context);
            final isDarkMode =
                themeProvider.themeData.brightness == Brightness.dark;

            if (!provider.hasLoadedProfile) {
              return const Center(child: CircularProgressIndicator());
            }

            final profile = provider.profile ?? {};
            final userRole =
                (profile['role'] ?? 'user').toString().toLowerCase();

            return LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: ConstrainedBox(
                    constraints:
                        BoxConstraints(minHeight: constraints.maxHeight),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ProfileHeader(user: profile),
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
                                    .contains(userRole)) ...[
                                  const _SettingsItem(
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
                                          color: (Colors.green[700]!)
                                              .withOpacity(0.1),
                                          borderRadius:
                                              BorderRadius.circular(12),
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
                                if (!_isLoadingGeoStatus) ...[
                                  Material(
                                    color: Colors.transparent,
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: (Colors.blue[700]!)
                                                .withOpacity(0.1),
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                          child: Icon(
                                            Icons.location_on,
                                            color: Colors.blue[700],
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        const Expanded(
                                          child: Text(
                                            'Отправка геоданных',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                        Switch(
                                          value: _isGeoTrackingEnabled,
                                          onChanged: (val) =>
                                              _toggleGeoTracking(val),
                                        ),
                                      ],
                                    ),
                                  ),
                                ] else ...[
                                  Material(
                                    color: Colors.transparent,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 16.0),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Загрузка статуса...',
                                            style: TextStyle(
                                              color: Colors.grey[600],
                                              fontSize: 14,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 10),
                                const _SettingsItem(
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
                                const _SettingsItem(
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
            );
          },
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
          'superadmin': 'Суперадмин'
        }[role] ??
        role.toUpperCase();
  }
}

class _SettingsItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color? color;
  final String? route;
  final VoidCallback? onTap;

  const _SettingsItem(
      {required this.icon,
      required this.title,
      this.color,
      this.route,
      this.onTap});

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
