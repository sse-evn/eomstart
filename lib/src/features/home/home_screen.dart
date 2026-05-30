import 'dart:io' show InternetAddress, SocketException;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:micro_mobility_app/src/core/providers/language_provider.dart';
import 'package:micro_mobility_app/src/core/providers/shift_provider.dart';
import 'package:micro_mobility_app/src/features/home/bloc/shift_bloc.dart';
import 'package:micro_mobility_app/src/features/home/bloc/shift_state.dart';
import 'package:micro_mobility_app/src/features/home/widgets/dashboard_stats.dart';
import 'package:micro_mobility_app/src/features/home/widgets/slot_card.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DashboardHome extends StatefulWidget {
  const DashboardHome({super.key});

  @override
  State<DashboardHome> createState() => _DashboardHomeState();
}

class _DashboardHomeState extends State<DashboardHome> {
  late Future<void> _loadDataFuture;
  bool _hasInternet = true;

  @override
  void initState() {
    super.initState();
    // Проверяем интернет и запускаем загрузку только если он есть
    _loadDataFuture = _checkInternetAndLoad();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestAllPermissionsForce();
    });
  }

  @override
  void dispose() {
    super.dispose();
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

  /// 🔒 Запрос разрешений (один раз за всё время использования)
  Future<void> _requestAllPermissionsForce() async {
    if (!mounted) return;

    final prefs = await SharedPreferences.getInstance();
    final alreadyRequested =
        prefs.getBool('permissions_requested_once') ?? false;

    if (alreadyRequested) return;
    await prefs.setBool('permissions_requested_once', true);

    // Запрашиваем геопозицию
    LocationPermission locPerm = await Geolocator.checkPermission();
    if (locPerm == LocationPermission.denied) {
      await Geolocator.requestPermission();
    }

    // Запрашиваем камеру
    PermissionStatus camStatus = await Permission.camera.status;
    if (camStatus.isDenied) {
      await Permission.camera.request();
    }

    // Запрашиваем уведомления
    PermissionStatus notifStatus = await Permission.notification.status;
    if (notifStatus.isDenied) {
      await Permission.notification.request();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(tr(context, 'Главная', 'Басты бет')),
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
              return Center(
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
                    padding: EdgeInsets.all(20),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error, size: 60, color: Colors.red),
                        SizedBox(height: 16),
                        Text(
                          tr(context, 'Ошибка загрузки данных',
                              'Деректерді жүктеу қатесі'),
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 8),
                        Text(
                          errorStr,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                        SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: _refresh,
                          child: Text(tr(context, 'Повторить', 'Қайталау')),
                        ),
                      ],
                    ),
                  ),
                );
              }
            } else {
              return Consumer<ShiftProvider>(
                builder: (context, provider, child) {
                  return BlocBuilder<ShiftBloc, ShiftState>(
                    builder: (context, shiftState) {
                      final hasActiveShift = shiftState is ShiftActive;

                      return SingleChildScrollView(
                        physics: AlwaysScrollableScrollPhysics(),
                        padding: EdgeInsets.symmetric(
                            horizontal: 16.0, vertical: 8.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (hasActiveShift) ...[
                              _buildActiveShiftBanner(context),
                              SizedBox(height: 20),
                            ],
                            Text(
                              'Ассалаумағалейкум, ${provider.profile?['firstName'] ?? 'Пользователь'}!',
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xDD61E045)),
                            ),
                            SizedBox(height: 4),
                            Text(
                              tr(context, 'Хорошего рабочего дня!',
                                  'Жұмыс күніңіз сәтті өтсін!'),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: Colors.grey[600],
                                  ),
                            ),
                            SizedBox(height: 24),
                            const SlotCard(),
                            SizedBox(height: 24),
                            const DashboardInterestingThings(),
                            SizedBox(height: 32),
                          ],
                        ),
                      );
                    },
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
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.green[700]!, Colors.green[500]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.green.withOpacity(0.3),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: Colors.white, blurRadius: 4, spreadRadius: 1)
              ],
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              tr(context, 'СМЕНА ОТКРЫТА', 'АУЫСЫМ АШЫЛДЫ'),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 1.0,
              ),
            ),
          ),
          Icon(Icons.timer_outlined, color: Colors.white, size: 18),
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
        padding: EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(30),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.wifi_off, size: 80, color: Colors.grey),
            ),
            SizedBox(height: 32),
            Text(
              tr(context, 'Нет подключения к интернету',
                  'Интернет байланысы жоқ'),
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 16),
            Text(
              tr(context, 'Проверьте соединение с сетью и попробуйте снова',
                  'Желіге қосылуды тексеріп, қайтадан байқап көріңіз'),
              style: TextStyle(fontSize: 16, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onRetry,
                icon: Icon(Icons.refresh, color: Colors.white),
                label: Text(tr(context, 'Повторить', 'Қайталау'),
                    style: TextStyle(color: Colors.white, fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[700],
                  padding: EdgeInsets.symmetric(vertical: 16),
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
