// lib/screens/profile_screen.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:http/http.dart' as http;

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:micro_mobility_app/src/core/themes/theme.dart';
import 'package:micro_mobility_app/src/core/providers/theme_provider.dart';
import 'package:micro_mobility_app/src/core/providers/language_provider.dart';
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
    show startBackgroundTracking, stopBackgroundTracking, isBackgroundTrackingRunning;

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
      final isRunning = await isBackgroundTrackingRunning();

      if (mounted) {
        setState(() {
          _isGeoTrackingEnabled = isRunning;
          _isLoadingGeoStatus = false;
          _hasLoadedGeoStatusOnce = true;
        });
      }
    } catch (e) {
      debugPrint(tr(context, 'Ошибка загрузки статуса геотрекинга: $e', 'Геотрекинг мәртебесін жүктеу қатесі: $e'));
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
        final activeShift = await context.read<ShiftProvider>().getActiveShift();
        int? activeShiftId = activeShift?.id;
        if (activeShiftId != null && activeShiftId > 0) {
          final success = await startBackgroundTracking(shiftId: activeShiftId);
          if (!success) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(tr(context, 'Для работы геотрекинга необходим доступ к геолокации. Пожалуйста, разрешите его в настройках.', 'Геотрекинг жұмыс істеуі үшін геолокация рұқсаты қажет. Баптаулардан рұқсат беріңіз.')),
                  backgroundColor: Colors.orange,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          }
        } else {
          // Нельзя включить — нет смены
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content:
                    Text(tr(context, 'Невозможно включить трекинг: нет активной смены', 'Трекинг қосу мүмкін емес: белсенді ауысым жоқ')),
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
        final activeShift = await context.read<ShiftProvider>().getActiveShift();
        if (activeShift != null && activeShift.id > 0) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(tr(context, 'Невозможно отключить геотрекинг во время активной смены', 'Белсенді ауысым кезінде геотрекингті өшіру мүмкін емес')),
                backgroundColor: Colors.red,
                behavior: SnackBarBehavior.floating,
              ),
            );
            setState(() {
              _isGeoTrackingEnabled = true;
            });
          }
        } else {
          await stopBackgroundTracking();
        }
      }
    } catch (e) {
      debugPrint(tr(context, 'Ошибка переключения геотрекинга: $e', 'Геотрекингті ауыстыру қатесі: $e'));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tr(context, 'Ошибка при изменении статуса трекинга: $e', 'Трекинг мәртебесін өзгерту қатесі: $e')),
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

  Future<void> _restartGeoTracking() async {
    if (_isLoadingGeoStatus) return;
    
    if (mounted) {
      setState(() {
        _isLoadingGeoStatus = true;
      });
    }

    try {
      final activeShift = await context.read<ShiftProvider>().getActiveShift();
      int? activeShiftId = activeShift?.id;
      
      await stopBackgroundTracking();
      
      if (activeShiftId != null && activeShiftId > 0) {
        await Future.delayed(const Duration(milliseconds: 500)); // give it time to fully stop
        final success = await startBackgroundTracking(shiftId: activeShiftId);
        
        if (mounted) {
          if (success) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(tr(context, 'Геотрекинг успешно перезапущен', 'Геотрекинг сәтті қайта іске қосылды')),
                backgroundColor: Colors.green,
                behavior: SnackBarBehavior.floating,
              ),
            );
          } else {
             ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(tr(context, 'Ошибка при перезапуске геотрекинга', 'Геотрекингті қайта іске қосу қатесі')),
                backgroundColor: Colors.red,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(tr(context, 'Нет активной смены для перезапуска', 'Қайта іске қосу үшін белсенді ауысым жоқ')),
              backgroundColor: Colors.orange,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Restart geo error: $e');
    } finally {
      final isRunning = await isBackgroundTrackingRunning();
      if (mounted) {
        setState(() {
          _isGeoTrackingEnabled = isRunning;
          _isLoadingGeoStatus = false;
        });
      }
    }
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
          SnackBar(
            content: Text(tr(context, 'Ошибка выхода', 'Шығу қатесі')),
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
          SnackBar(
            content: Text(tr(context, 'У вас установлена последняя версия', 'Сізде соңғы нұсқа орнатылған')),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tr(context, 'Ошибка проверки обновлений: $e', 'Жаңартуларды тексеру қатесі: $e')),
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
      if (Platform.isIOS) {
        // Так как приложение скрыто (unlisted) в App Store, iTunes Lookup API всегда возвращает пустые результаты.
        // Поэтому мы проверяем версию исключительно через наш собственный защищенный бэкенд.
        try {
          final token = await _storage.read(key: 'jwt_token');
          String? serverVersion;

          // 1. Проверяем специализированный файл версии для iOS
          final iosResponse = await http.get(
            Uri.parse('${AppConfig.backendHost}/uploads/app/version_ios.txt'),
            headers: token != null ? {'Authorization': 'Bearer $token'} : {},
          ).timeout(const Duration(seconds: 5));

          if (iosResponse.statusCode == 200) {
            serverVersion = iosResponse.body.trim();
          } else {
            // 2. Если его нет, используем общий version.txt
            final generalResponse = await http.get(
              Uri.parse('${AppConfig.backendHost}/uploads/app/version.txt'),
              headers: token != null ? {'Authorization': 'Bearer $token'} : {},
            ).timeout(const Duration(seconds: 5));
            if (generalResponse.statusCode == 200) {
              serverVersion = generalResponse.body.trim();
            }
          }

          if (serverVersion != null && serverVersion.isNotEmpty) {
            return _isNewerVersion(serverVersion, currentVersion);
          }
        } catch (e) {
          debugPrint(tr(context, 'Ошибка проверки версии iOS на бэкенде: $e', 'Серверде iOS нұсқасын тексеру қатесі: $e'));
        }
      } else if (Platform.isAndroid) {
        // Для Android пробуем запросить актуальную версию с бэкенда
        try {
          final token = await _storage.read(key: 'jwt_token');
          final response = await http.get(
            Uri.parse('${AppConfig.backendHost}/uploads/app/version.txt'),
            headers: token != null ? {'Authorization': 'Bearer $token'} : {},
          ).timeout(const Duration(seconds: 5));

          if (response.statusCode == 200) {
            final serverVersion = response.body.trim();
            return _isNewerVersion(serverVersion, currentVersion);
          }
        } catch (_) {
          // Если нет эндпоинта версии — не показываем ошибку,
          // но предлагаем скачать APK (считаем что есть обновление)
          return false;
        }
      }
    } catch (e) {
      debugPrint(tr(context, 'Ошибка проверки версии: $e', 'Нұсқаны тексеру қатесі: $e'));
    }
    return false;
  }

  /// Сравнивает версии формата "1.2.3"
  bool _isNewerVersion(String serverVersion, String currentVersion) {
    try {
      final cleanServer = serverVersion.split('+')[0];
      final cleanCurrent = currentVersion.split('+')[0];
      final server = cleanServer.split('.').map(int.parse).toList();
      final current = cleanCurrent.split('.').map(int.parse).toList();
      for (int i = 0; i < server.length && i < current.length; i++) {
        if (server[i] > current[i]) return true;
        if (server[i] < current[i]) return false;
      }
      return server.length > current.length;
    } catch (_) {
      return false;
    }
  }


  void _showUpdateDialog(String currentVersion) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(tr(context, 'Доступно обновление', 'Жаңарту қолжетімді')),
          content: Text(
              tr(context, 'Доступна новая версия приложения. Рекомендуем обновить для получения последних улучшений и исправлений.', 'Қосымшаның жаңа нұсқасы қолжетімді. Соңғы өзгерістерді алу үшін жаңартуды ұсынамыз.')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(tr(context, 'Позже', 'Кейінірек')),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _downloadUpdate();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green[700],
              ),
              child: Text(tr(context, 'Обновить', 'Жаңарту')),
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
        await launchUrl(
          Uri.parse(downloadUrl),
          mode: LaunchMode.externalApplication,
        );
      } else {
        throw tr(context, 'Не удалось открыть ссылку для загрузки', 'Жүктеу сілтемесін ашу мүмкін болмады');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tr(context, 'Ошибка загрузки обновления: $e', 'Жаңартуды жүктеу қатесі: $e')),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }







  void _showSettingsModal() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Настройки / Баптаулар',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 20),
              ListTile(
                leading: Icon(Icons.language, color: Colors.purple),
                title: Text('Язык / Тіл'),
                trailing: Consumer<LanguageProvider>(
                  builder: (context, languageProvider, child) {
                    return DropdownButton<String>(
                      value: languageProvider.locale,
                      underline: SizedBox(),
                      items: const [
                        DropdownMenuItem(value: 'ru', child: Text('Русский')),
                        DropdownMenuItem(value: 'kk', child: Text('Қазақша')),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          languageProvider.setLocale(val);
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(tr(context, 'Язык изменен', tr(context, 'Тіл ауыстырылды', 'Тіл ауыстырылды'))),
                              backgroundColor: Colors.blue,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      },
                    );
                  },
                ),
              ),
              ListTile(
                leading: Icon(_isCheckingForUpdates ? Icons.downloading : Icons.system_update, color: Colors.blue),
                title: Text(_isCheckingForUpdates ? tr(context, 'Проверка обновлений...', 'Жаңартуларды тексеру...') : tr(context, 'Проверить обновления / Жаңартуларды тексеру', 'Жаңартуларды тексеру')),
                onTap: () {
                  Navigator.pop(context);
                  _checkForUpdates();
                },
              ),
              ListTile(
                leading: Icon(Icons.info, color: Colors.grey),
                title: Text(tr(context, 'О приложении / Қосымша туралы', 'Қосымша туралы')),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.pushNamed(context, '/about');
                },
              ),
            ],
          ),
        );
      },
    );
  }

  ///
  /// UI
  ///

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'Профиль', 'Профиль')),
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
              return Center(child: CircularProgressIndicator());
            }

            final profile = provider.profile ?? {};
            final userRole =
                (profile['role'] ?? 'user').toString().toLowerCase();

            return LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  physics: AlwaysScrollableScrollPhysics(),
                  child: ConstrainedBox(
                    constraints:
                        BoxConstraints(minHeight: constraints.maxHeight),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ProfileHeader(user: profile),
                        SizedBox(height: 10),
                        Padding(
                          padding: EdgeInsets.all(16.0),
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
                                  offset: Offset(0, 6),
                                ),
                              ],
                            ),
                            padding: EdgeInsets.all(10),
                            child: Column(
                              children: [
                                if (['superadmin', 'coordinator', 'supervisor']
                                    .contains(userRole)) ...[
                                  _SettingsItem(
                                    icon: Icons.admin_panel_settings,
                                    title: tr(context, 'Админ-панель', 'Админ-панель'),
                                    route: '/admin',
                                  ),
                                ],
                                SizedBox(height: 10),
                                Material(
                                  color: Colors.transparent,
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: EdgeInsets.all(12),
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
                                          color: Color.fromARGB(
                                              255, 134, 136, 33),
                                        ),
                                      ),
                                      SizedBox(width: 16),
                                      Expanded(
                                        child: Text(
                                          isDarkMode
                                              ? tr(context, 'Темная тема', 'Қараңғы тақырып')
                                              : tr(context, 'Светлая тема', 'Жарық тақырып'),
                                          style: TextStyle(
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
                                SizedBox(height: 10),
                                if (!_isLoadingGeoStatus) ...[
                                  Material(
                                    color: Colors.transparent,
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: EdgeInsets.all(12),
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
                                        SizedBox(width: 16),
                                        Expanded(
                                          child: Text(
                                            tr(context, 'Отправка геоданных', 'Геодеректерді жіберу'),
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                        if (_isGeoTrackingEnabled)
                                          IconButton(
                                            icon: Icon(Icons.refresh, color: Colors.blue[700]),
                                            tooltip: tr(context, 'Перезапустить геотрекинг', 'Геотрекингті қайта қосу'),
                                            onPressed: _restartGeoTracking,
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
                                      padding: EdgeInsets.symmetric(
                                          vertical: 16.0),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2),
                                          ),
                                          SizedBox(width: 8),
                                          Text(
                                            tr(context, 'Загрузка статуса...', 'Мәртебені жүктеу...'),
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
                                SizedBox(height: 10),
                                _SettingsItem(
                                  icon: Icons.card_giftcard,
                                  title: tr(context, 'Промокод', 'Промокод'),
                                  route: '/promo',
                                  color: Color(0xFFAA81AA),
                                ),
                                _SettingsItem(
                                  icon: Icons.settings,
                                  title: 'Настройки / Баптаулар',
                                  color: Colors.grey[700],
                                  onTap: _showSettingsModal,
                                ),
                              ],
                            ),
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
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
                                  offset: Offset(0, 6),
                                ),
                              ],
                            ),
                            padding: EdgeInsets.all(10),
                            child: _SettingsItem(
                              icon: Icons.logout,
                              title: tr(context, 'Выйти', 'Шығу'),
                              color: Colors.red,
                              onTap: _logout,
                            ),
                          ),
                        ),
                        SizedBox(height: 32),
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
        : (username.isNotEmpty ? username : tr(context, 'Пользователь', 'Қолданушы'));
    final avatarUrl = _safeString(user['avatarUrl']);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(vertical: 30, horizontal: 24),
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
          SizedBox(height: 15),
          Text(
            fullName,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 8),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.blueGrey,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _formatRole(context, role),
              style: TextStyle(
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

  String _formatRole(BuildContext context, String role) {
    return {
          'user': tr(context, 'Пользователь', 'Қолданушы'),
          'scout': tr(context, 'Скаут', 'Скаут'),
          'supervisor': tr(context, 'Супервайзер', 'Супервайзер'),
          'coordinator': tr(context, 'Координатор', 'Координатор'),
          'superadmin': tr(context, 'Суперадмин', 'Суперадмин')
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
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (color ?? Colors.green[700]!).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: color ?? Colors.green[700],
              ),
            ),
            SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
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
