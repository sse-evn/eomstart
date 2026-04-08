import 'package:flutter/material.dart';
import 'package:micro_mobility_app/src/features/home/widgets/slot_card.dart';
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
              return const SingleChildScrollView(
                physics: AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    SlotCard(),
                    SizedBox(height: 10),
                    // ReportCard(),
                  ],
                ),
              );
            }
          },
        ),
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
