
// --- Экран главной страницы ---
import 'package:flutter/material.dart';
import 'package:micro_mobility_app/screens/home/widgets/report_card.dart';
import 'package:micro_mobility_app/screens/home/widgets/slot_card.dart';
import 'package:micro_mobility_app/providers/shift_provider.dart';
import 'package:provider/provider.dart';

class DashboardHome extends StatefulWidget {
  const DashboardHome();

  @override
  State<DashboardHome> createState() => _DashboardHomeState();
}

class _DashboardHomeState extends State<DashboardHome> {
  late Future<void> _loadDataFuture;

  // 🔥 УДАЛЕНО: StreamSubscription и _listenToConnectionChanges()

  @override
  void initState() {
    super.initState();
    _loadDataFuture = _loadData();
  }

  Future<void> _loadData() async {
    final provider = context.read<ShiftProvider>();
    await provider.loadShifts();
  }

  Future<void> _refresh() async {
    setState(() {
      _loadDataFuture = _loadData(); // Явный запрос — уместен
    });
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
              return SingleChildScrollView(
                physics: AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    SlotCard(),
                    SizedBox(height: 10),


                    Row(
                      children: [
                        Text(
                          'Статистика',
                          style: TextStyle(
                            fontSize: 22,
                            
                          ),
                        ),
                        const SizedBox(width: 10,),
                        Icon(
                          Icons.stacked_line_chart_rounded
                        )
                      ],
                    ),

                    const SizedBox(
                      height: 10,
                    ),
                    
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16.0),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16.0),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withOpacity(0.15),
                            spreadRadius: 1,
                            blurRadius: 12,
                            offset: Offset(0, 6),
                          ),
                        ],
                      ),

                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Всего:',
                                style: TextStyle(
                                  fontSize: 20
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '100',
                                style: TextStyle(
                                  fontSize: 20
                                ),
                              ),
                            ],
                          ),
                      
                          const Divider(
                            color: Colors.grey,
                          ),
                      
                          Row(
                            children: [
                              Text(
                                'Jet',
                                style: TextStyle(
                                  fontSize: 16
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '100',
                                style: TextStyle(
                                  fontSize: 16
                                ),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              Text(
                                'Yandex',
                                style: TextStyle(
                                  fontSize: 16
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '100',
                                style: TextStyle(
                                  fontSize: 16
                                ),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              Text(
                                'Whoosh',
                                style: TextStyle(
                                  fontSize: 16
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '100',
                                style: TextStyle(
                                  fontSize: 16
                                ),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              Text(
                                'Bolt',
                                style: TextStyle(
                                  fontSize: 16
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '100',
                                style: TextStyle(
                                  fontSize: 16
                                ),
                              ),
                            ],
                          ),
                      
                      
                      
                        ],
                      ),
                    ),

                    SizedBox(height: 10),
                  
                    ReportCard(),
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
                  color: Colors.black87),
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
