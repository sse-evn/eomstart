// lib/components/bot_stats_card.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'info_row.dart';
import '../../providers/shift_provider.dart';
// import 'dart:math' as math;

class BotStatsCard extends StatelessWidget {
  const BotStatsCard({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ShiftProvider>();

    // Проверяем, есть ли данные от бота
    if (provider.botStatsData == null) {
      // Если данных нет, показываем индикатор загрузки или сообщение
      if (provider.isLoadingBotStats) {
        return _buildLoadingState();
      } else {
        // Пытаемся загрузить данные, если они еще не были загружены
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!provider.isLoadingBotStats) {
            provider.fetchBotStats();
          }
        });
        return _buildNoDataState();
      }
    }

    final botStats = provider.botStatsData!;
    final shiftName = botStats['shift_name'] as String? ?? 'Неизвестная смена';
    final totals = Map<String, dynamic>.from(botStats['totals'] as Map? ?? {});
    final totalAll = botStats['total_all'] as int? ?? 0;
    final stats = Map<String, dynamic>.from(botStats['stats'] as Map? ?? {});

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Статистика из Telegram-бота',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
              // Кнопка обновления
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.green),
                onPressed:
                    provider.isLoadingBotStats ? null : provider.fetchBotStats,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'За $shiftName',
            style: const TextStyle(
              fontSize: 14,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, thickness: 1, color: Colors.grey),

          // Общая статистика
          const SizedBox(height: 12),
          const Text(
            'Общий итог',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          InfoRow(label: 'Всего принято', value: '$totalAll шт.'),

          // Итоги по сервисам
          const SizedBox(height: 12),
          const Text(
            'По сервисам',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          ..._buildServiceRows(totals),

          // Статистика по пользователям (если есть)
          if (stats.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Divider(height: 1, thickness: 1, color: Colors.grey),
            const SizedBox(height: 12),
            const Text(
              'По пользователям',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            ..._buildUserStatsRows(stats),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildServiceRows(Map<String, dynamic> totals) {
    if (totals.isEmpty) {
      return [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8.0),
          child: Text(
            'Нет данных',
            style: TextStyle(color: Colors.grey),
          ),
        )
      ];
    }

    // Сортируем сервисы по количеству
    final sortedServices = totals.entries.toList()
      ..sort((a, b) => (b.value as int).compareTo(a.value as int));

    return sortedServices.map((entry) {
      final serviceName = entry.key;
      final count = entry.value as int;
      return InfoRow(
        label: serviceName,
        value: '$count шт.',
      );
    }).toList();
  }

  List<Widget> _buildUserStatsRows(Map<String, dynamic> stats) {
    // Преобразуем данные и сортируем по общему количеству
    final userStatsList = stats.entries.map((entry) {
      final userId = entry.key;
      final userData = Map<String, dynamic>.from(entry.value as Map);
      final total = userData['total'] as int? ?? 0;
      return {
        'userId': userId,
        'userData': userData,
        'total': total,
      };
    }).toList();

    userStatsList
        .sort((a, b) => (b['total'] as int).compareTo(a['total'] as int));

    return userStatsList.asMap().entries.expand((entry) {
      final index = entry.key;
      final item = entry.value;
      final userData = Map<String, dynamic>.from(item['userData'] as Map);
      final username =
          userData['username'] as String? ?? 'Неизвестный пользователь';
      final fullName = userData['full_name'] as String? ?? '';
      final displayName = username.isNotEmpty
          ? '@$username'
          : (fullName.isNotEmpty ? fullName : 'ID: ${item['userId']}');
      final total = item['total'] as int;
      final services =
          Map<String, dynamic>.from(userData['services'] as Map? ?? {});

      // Цвет для пользователя (чередуем для лучшей визуализации)
      final colors = [Colors.blue, Colors.purple, Colors.orange, Colors.teal];
      final color = colors[index % colors.length];

      return [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 30,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Статистика по сервисам для пользователя
                    ...services.entries.map((serviceEntry) {
                      final serviceName = serviceEntry.key;
                      final serviceCount = serviceEntry.value as int;
                      return Padding(
                        padding: const EdgeInsets.only(left: 8.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              serviceName,
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.grey,
                              ),
                            ),
                            Text(
                              '$serviceCount шт.',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ],
                ),
              ),
              Text(
                '$total',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        if (index < userStatsList.length - 1)
          const Divider(height: 1, thickness: 0.5, color: Colors.grey),
      ];
    }).toList();
  }

  Widget _buildLoadingState() {
    return Container(
      height: 200,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              'Загрузка статистики...',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoDataState() {
    return Container(
      height: 200,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Center(
        child: Text(
          'Нет данных от Telegram-бота',
          style: TextStyle(color: Colors.grey),
        ),
      ),
    );
  }
}
