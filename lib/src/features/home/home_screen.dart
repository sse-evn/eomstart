import 'package:flutter/material.dart';
import 'package:micro_mobility_app/src/features/home/widgets/slot_card.dart';
import 'package:micro_mobility_app/src/features/home/widgets/dashboard_stats.dart';
import 'package:micro_mobility_app/src/core/providers/shift_provider.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io' show InternetAddress;
import 'dart:io' show SocketException;

class DashboardHome extends StatefulWidget {
  const DashboardHome({super.key});

  @override
  State<DashboardHome> createState() => _DashboardHomeState();
}

class _DashboardHomeState extends State<DashboardHome> {
  late Future<void> _loadDataFuture;
  bool _hasInternet = true; // флаг наличия интернета

  @override
  void initState() {
    super.initState();

    // Проверяем интернет и запускаем загрузку только если он есть
    _loadDataFuture = _checkInternetAndLoad();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestAllPermissionsForce();
    });
  }

  Future<void> _checkInternetAndLoad() async {
    bool internetAvailable = await _hasNetworkConnection();
    if (!internetAvailable) {
      setState(() {
        _hasInternet = false;
      });
      return; // не грузим данные
    }

    final provider = context.read<ShiftProvider>();
    if (!provider.hasLoadedShifts) {
      await provider.loadShifts();
    }
  }

  Future<bool> _hasNetworkConnection() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } on SocketException catch (_) {
      return false;
    }
  }

  Future<void> _refresh() async {
    bool internetAvailable = await _hasNetworkConnection();
    if (!internetAvailable) {
      if (mounted) {
        setState(() {
          _hasInternet = false;
        });
      }
      return;
    }

    // Сбрасываем флаг отсутствия интернета
    if (!_hasInternet && mounted) {
      setState(() {
        _hasInternet = true;
      });
    }

    await _loadData();
    if (mounted) {
      setState(() {
        _loadDataFuture = Future.value();
      });
    }
  }

  Future<void> _loadData() async {
    final provider = context.read<ShiftProvider>();
    await provider.loadShifts();
  }

  /// 🔒 Принудительный запрос всех разрешений
  Future<void> _requestAllPermissionsForce() async {
    bool allGranted = false;

    while (!allGranted && mounted) {
      allGranted = true;

      if (!await Geolocator.isLocationServiceEnabled()) {
        await Geolocator.openLocationSettings();
      }

      LocationPermission locPerm = await Geolocator.checkPermission();
      if (locPerm != LocationPermission.always) {
        locPerm = await Geolocator.requestPermission();
        if (locPerm != LocationPermission.always) {
          allGranted = false;
        }
      }

      PermissionStatus camStatus = await Permission.camera.status;
      if (!camStatus.isGranted) {
        camStatus = await Permission.camera.request();
        if (!camStatus.isGranted) allGranted = false;
      }

      PermissionStatus notifStatus = await Permission.notification.status;
      if (!notifStatus.isGranted) {
        notifStatus = await Permission.notification.request();
        if (!notifStatus.isGranted) allGranted = false;
      }

      // if (!allGranted) {
      //   await _showForcePermissionDialog();
      // }
    }
  }

  Future<void> _showForcePermissionDialog() async {
    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Необходимые разрешения'),
        content: const Text(
            'Для работы приложения необходимо разрешить все права, особенно геопозицию "Allow all the time". Без них приложение не будет работать.'),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await openAppSettings();
            },
            child: const Text('Открыть настройки'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Главная'),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<void>(
          future: _loadDataFuture,
          builder: (context, snapshot) {
            // Сначала проверяем, есть ли интернет
            if (!_hasInternet) {
              return NoInternetWidget(onRetry: _refresh);
            }

            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                  child: CircularProgressIndicator(color: Colors.green));
            } else if (snapshot.hasError) {
              final errorStr = snapshot.error.toString();
              if (errorStr.contains('SocketException') ||
                  errorStr.contains('Network') ||
                  errorStr.contains('Timeout')) {
                return NoInternetWidget(onRetry: _refresh);
              } else {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error, size: 60, color: Colors.red),
                        const SizedBox(height: 16),
                        const Text(
                          'Ошибка загрузки данных',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          errorStr,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.grey),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: _refresh,
                          child: const Text('Повторить'),
                        ),
                      ],
                    ),
                  ),
                );
              }
            } else {
              return Consumer<ShiftProvider>(
                builder: (context, provider, child) {
                  final activeShift = provider.activeShift;
                  final hasActiveShift = activeShift != null;

                  return SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16.0, vertical: 8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (hasActiveShift) ...[
                          _buildActiveShiftBanner(context),
                          const SizedBox(height: 16),
                        ],
                        const SlotCard(),
                        const SizedBox(height: 24),
                        const DashboardInterestingThings(),
                        const SizedBox(height: 32),
                      ],
                    ),
                  );
                },
              );
            }
          },
        ),
      ),
    );
  }

  Widget _buildActiveShiftBanner(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: const BoxDecoration(
              color: Colors.green,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: Colors.green, blurRadius: 4, spreadRadius: 1)
              ],
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'СМЕНА ОТКРЫТА',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: Colors.green,
                letterSpacing: 0.5,
              ),
            ),
          ),
          Icon(Icons.timer_outlined,
              color: Colors.green.withOpacity(0.7), size: 16),
        ],
      ),
    );
  }
}

/// Виджет при отсутствии интернета
class NoInternetWidget extends StatelessWidget {
  final VoidCallback onRetry;

  const NoInternetWidget({super.key, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(30),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.wifi_off, size: 80, color: Colors.grey),
            ),
            const SizedBox(height: 32),
            const Text(
              'Нет подключения к интернету',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            const Text(
              'Проверьте соединение с сетью и попробуйте снова',
              style: TextStyle(fontSize: 16, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, color: Colors.white),
                label: const Text('Повторить',
                    style: TextStyle(color: Colors.white, fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[700],
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
