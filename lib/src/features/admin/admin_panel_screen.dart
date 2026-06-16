import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:micro_mobility_app/src/core/config/app_config.dart';
import 'package:micro_mobility_app/src/core/services/api_service.dart';
import 'package:micro_mobility_app/src/features/admin/admin_map_screens.dart';
import 'package:micro_mobility_app/src/features/admin/generator_shifts.dart';
import 'package:micro_mobility_app/src/features/admin/promo_codes_admin_screen.dart';
import 'package:micro_mobility_app/src/features/admin/scooter_reports_screen.dart';
import 'package:micro_mobility_app/src/features/admin/shift_history_screen.dart';
import 'package:micro_mobility_app/src/features/admin/shift_monitoring_screen.dart';
import 'package:micro_mobility_app/src/features/admin/tabs/daily_reports_tab.dart';
import 'package:micro_mobility_app/src/features/admin/tabs/slot_management_tab.dart';
import 'package:micro_mobility_app/src/features/admin/widgets/admin_users_list.dart';

class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key});

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  int _currentIndex = 0;

  List<String> get _titles => [
        'Пользователи',
        'Карта',
        'Смены',
        'Управление',
      ];

  Widget? _subScreen;
  String? _subTitle;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Widget _buildSettingsMenu() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ListTile(
            leading:
                const Icon(Icons.calendar_today_outlined, color: Colors.blue),
            title: const Text('Генератор смен',
                style: TextStyle(fontWeight: FontWeight.bold)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => setState(() {
              _subScreen = const GeneratorShiftScreen();
              _subTitle = 'Генератор смен';
            }),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ListTile(
            leading:
                const Icon(Icons.local_offer_outlined, color: Colors.orange),
            title: const Text('Промокоды',
                style: TextStyle(fontWeight: FontWeight.bold)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => setState(() {
              _subScreen = const AdminPromoScreen();
              _subTitle = 'Промокоды';
            }),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ListTile(
            leading: const Icon(Icons.av_timer_outlined, color: Colors.green),
            title: const Text('Слоты времени',
                style: TextStyle(fontWeight: FontWeight.bold)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => setState(() {
              _subScreen = const SlotManagementTab();
              _subTitle = 'Управление слотами';
            }),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ListTile(
            leading: const Icon(Icons.analytics_outlined, color: Colors.purple),
            title: const Text('Отчеты по сменам',
                style: TextStyle(fontWeight: FontWeight.bold)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => setState(() {
              _subScreen = const DailyReportsTab();
              _subTitle = 'Отчеты по сменам';
            }),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ListTile(
            leading:
                const Icon(Icons.campaign_outlined, color: Colors.redAccent),
            title: const Text('Массовая рассылка',
                style: TextStyle(fontWeight: FontWeight.bold)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              _showMassNotificationDialog(context);
            },
          ),
        ),
        const SizedBox(height: 8),
        Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: const _SettingsQrToggle(),
        ),
        const SizedBox(height: 8),
        Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: const _MinAppVersionSetting(),
        ),
      ],
    );
  }

  void _showMassNotificationDialog(BuildContext context) {
    final TextEditingController msgController = TextEditingController();
    bool isSending = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(builder: (context, setDialogState) {
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.campaign, color: Colors.redAccent),
                SizedBox(width: 8),
                Text('Рассылка скаутам', style: TextStyle(fontSize: 18)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Сообщение получат все скауты, находящиеся сейчас на смене (через Telegram-бота).',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: msgController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'Начался дождь, будьте аккуратнее...',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: isSending ? null : () => Navigator.pop(ctx),
                child: const Text('Отмена'),
              ),
              ElevatedButton(
                onPressed: isSending
                    ? null
                    : () async {
                        final msg = msgController.text.trim();
                        if (msg.isEmpty) return;

                        setDialogState(() => isSending = true);
                        try {
                          final token = await const FlutterSecureStorage()
                              .read(key: 'jwt_token');
                          if (token != null) {
                            await ApiService()
                                .sendAdminNotification(token, msg);
                            if (mounted) {
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(this.context).showSnackBar(
                                const SnackBar(
                                    content:
                                        Text('Уведомления успешно отправлены!'),
                                    backgroundColor: Colors.green),
                              );
                            }
                          }
                        } catch (e) {
                          setDialogState(() => isSending = false);
                          if (mounted) {
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              SnackBar(
                                  content: Text('Ошибка: $e'),
                                  backgroundColor: Colors.red),
                            );
                          }
                        }
                      },
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white),
                child: isSending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Text('Отправить всем'),
              ),
            ],
          );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    Widget currentBody;

    if (_subScreen != null) {
      currentBody = _subScreen!;
    } else {
      switch (_currentIndex) {
        case 0:
          currentBody = const AdminUsersList();
          break;
        case 1:
          currentBody = const MapAndZoneScreen();
          break;
        case 2:
          currentBody = DefaultTabController(
            length: 3,
            child: Column(
              children: [
                Material(
                  color: primaryColor,
                  child: const TabBar(
                    tabs: [
                      Tab(
                          text: 'Активные',
                          icon: Icon(Icons.play_arrow, size: 18)),
                      Tab(text: 'История', icon: Icon(Icons.history, size: 18)),
                      Tab(
                          text: 'Надзор',
                          icon: Icon(Icons.report_problem_outlined, size: 18)),
                    ],
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white70,
                    indicator: UnderlineTabIndicator(
                      borderSide: BorderSide(color: Colors.white, width: 2.0),
                    ),
                  ),
                ),
                const Expanded(
                  child: TabBarView(
                    children: [
                      ShiftMonitoringScreen(),
                      ShiftHistoryScreen(),
                      ScooterReportsScreen(),
                    ],
                  ),
                ),
              ],
            ),
          );
          break;
        case 3:
          currentBody = _buildSettingsMenu();
          break;
        default:
          currentBody = const AdminUsersList();
      }
    }

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        extendBodyBehindAppBar: false,
        appBar: AppBar(
          elevation: 0,
          backgroundColor: theme.scaffoldBackgroundColor,
          surfaceTintColor: Colors.transparent,
          centerTitle: false,
          leading: _subScreen != null
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () {
                    setState(() {
                      _subScreen = null;
                      _subTitle = null;
                    });
                  },
                )
              : null,
          title: Text(
            _subTitle ?? _titles[_currentIndex],
            style: const TextStyle(
                fontWeight: FontWeight.w900, fontSize: 22, letterSpacing: -0.5),
          ),
          actions: [
            PopupMenuButton(
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.1),
                    shape: BoxShape.circle),
                child: const Icon(Icons.info_outline,
                    size: 18, color: Colors.grey),
              ),
              tooltip: 'Информация о среде',
              onSelected: (value) {
                if (value == 'env') {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(AppConfig.environmentInfo)),
                  );
                }
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(
                    value: 'env', child: Text('Показать среду')),
              ],
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                theme.scaffoldBackgroundColor,
                theme.scaffoldBackgroundColor.withOpacity(0.8),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: currentBody,
        ),
        bottomNavigationBar: Theme(
          data: Theme.of(context).copyWith(
            splashFactory: NoSplash.splashFactory,
            highlightColor: Colors.transparent,
            splashColor: Colors.transparent,
          ),
          child: BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: (index) {
              setState(() {
                _currentIndex = index;
                _subScreen = null;
                _subTitle = null;
              });
            },
            type: BottomNavigationBarType.fixed,
            selectedItemColor: primaryColor,
            unselectedItemColor: Colors.grey[600],
            elevation: 0,
            selectedFontSize: 13,
            selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
            unselectedLabelStyle:
                const TextStyle(fontWeight: FontWeight.normal),
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.people_outline),
                activeIcon: Icon(Icons.people),
                label: 'Пользователи',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.map_outlined),
                activeIcon: Icon(Icons.map),
                label: 'Карта',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.access_time_outlined),
                activeIcon: Icon(Icons.access_time),
                label: 'Смены',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.settings_outlined),
                activeIcon: Icon(Icons.settings),
                label: 'Управление',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsQrToggle extends StatefulWidget {
  const _SettingsQrToggle();
  @override
  State<_SettingsQrToggle> createState() => _SettingsQrToggleState();
}

class _SettingsQrToggleState extends State<_SettingsQrToggle> {
  bool _isQrEnabled = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    try {
      final settings = await ApiService().getSettings();
      if (mounted) {
        setState(() {
          _isQrEnabled = settings['is_qr_enabled'] == 'true';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _toggle(bool val) async {
    setState(() => _isLoading = true);
    try {
      await ApiService().updateSetting('is_qr_enabled', val ? 'true' : 'false');
      setState(() {
        _isQrEnabled = val;
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Настройки обновлены. Требуется перезапуск приложения у скаутов.')));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const ListTile(
        leading: CircularProgressIndicator(),
        title: Text('Загрузка настроек...'),
      );
    }
    return SwitchListTile(
      secondary: const Icon(Icons.qr_code_scanner, color: Colors.blueGrey),
      title: const Text('Вкладка QR у скаутов',
          style: TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(_isQrEnabled ? 'Включена' : 'Отключена',
          style: TextStyle(color: _isQrEnabled ? Colors.green : Colors.red)),
      value: _isQrEnabled,
      onChanged: _toggle,
    );
  }
}

class _MinAppVersionSetting extends StatefulWidget {
  const _MinAppVersionSetting();
  @override
  State<_MinAppVersionSetting> createState() => _MinAppVersionSettingState();
}

class _MinAppVersionSettingState extends State<_MinAppVersionSetting> {
  int _patchVersion = 22;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    try {
      final version = await ApiService().getMinAppVersion();
      if (mounted) {
        setState(() {
          _patchVersion = version;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _updateVersion(int newVersion) async {
    setState(() => _isLoading = true);
    try {
      await ApiService().updateMinAppVersion(newVersion);
      setState(() {
        _patchVersion = newVersion;
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Минимальная версия обновлена на $newVersion. Старые приложения будут заблокированы.'),
            backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const ListTile(
        leading: CircularProgressIndicator(),
        title: Text('Загрузка версии...'),
      );
    }
    return ListTile(
      leading: const Icon(Icons.system_update, color: Colors.blueAccent),
      title: const Text('Блокировка старых версий',
          style: TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text('Минимальный патч: $_patchVersion (например, 1.0.$_patchVersion)'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
            onPressed: () {
              if (_patchVersion > 0) _updateVersion(_patchVersion - 1);
            },
          ),
          Text('$_patchVersion', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          IconButton(
            icon: const Icon(Icons.add_circle_outline, color: Colors.green),
            onPressed: () => _updateVersion(_patchVersion + 1),
          ),
        ],
      ),
    );
  }
}
