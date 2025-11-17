// ====== PromoCodeScreen.dart ======

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:micro_mobility_app/services/promo_api_service.dart';
import 'package:micro_mobility_app/services/api_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class PromoCodeScreen extends StatefulWidget {
  const PromoCodeScreen({super.key});

  @override
  State<PromoCodeScreen> createState() => _PromoCodeScreenState();
}

class _PromoCodeScreenState extends State<PromoCodeScreen> {
  final PromoApiService _promoService = PromoApiService();
  final ApiService _apiService = ApiService();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  // Для хранения состояния активного бренда
  String? _activeBrand;
  // Для хранения состояния смены
  bool? _isShiftActive;
  // Для хранения полученных промокодов (будут сохранены в storage)
  final Map<String, List<String>> _claimed = {};

  // Для отслеживания загрузки каждого бренда
  final Map<String, bool> _isLoading = {
    'JET': false,
    'YANDEX': false,
    'WHOOSH': false,
    'BOLT': false,
  };

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    await _loadClaimedPromos(); // Загружаем сохраненные промокоды
    await _checkShiftStatus(); // Проверяем смену
    await _loadActiveBrand(); // Загружаем активный бренд
  }

  Future<void> _loadClaimedPromos() async {
    try {
      // Читаем из хранилища
      final savedClaimed = await _storage.read(key: 'claimed_promos');
      if (savedClaimed != null) {
        setState(() {
          _claimed.addAll(
            jsonDecode(savedClaimed) as Map<String, List<String>>,
          );
        });
      }
    } catch (e) {
      // Игнорируем ошибку, просто не загрузим старые данные
    }
  }

  Future<void> _checkShiftStatus() async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token == null) {
        if (mounted) setState(() => _isShiftActive = false);
        return;
      }

      final activeShift = await _apiService.getActiveShift(token);
      if (mounted) {
        setState(() {
          _isShiftActive = activeShift != null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isShiftActive = false;
        });
      }
    }
  }

  Future<void> _loadActiveBrand() async {
    try {
      final response = await _promoService.getActivePromoBrand();
      if (mounted) {
        setState(() {
          _activeBrand = response?['brand'];
        });
      }
    } catch (e) {
      // Если ошибка, считаем что активных брендов нет (все доступны)
      if (mounted) {
        setState(() {
          _activeBrand = null;
        });
      }
    }
  }

  Future<void> _claimPromo(String brand) async {
    if (_isShiftActive != true) return;

    setState(() {
      _isLoading[brand] = true;
    });

    try {
      final response = await _promoService.claimPromoByBrand(brand);
      final codes = (response['promo_codes'] as List).cast<String>();
      final alreadyClaimed = response['already_claimed'] ?? false;

      if (mounted) {
        // Обновляем состояние
        setState(() {
          _claimed[brand] = codes;
        });

        // Сохраняем в хранилище
        await _storage.write(
          key: 'claimed_promos',
          value: jsonEncode(_claimed),
        );

        // Показываем сообщение
        final codeText = codes.length == 1 ? codes[0] : codes.join(', ');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              alreadyClaimed
                  ? 'У вас уже есть промокод: $codeText'
                  : 'Получено: $codeText',
            ),
            backgroundColor: alreadyClaimed ? Colors.blue : Colors.green,
          ),
        );
      }
    } on PromoApiServiceException catch (e) {
      if (mounted) {
        if (e.statusCode == 401) {
          _handleUnauthorized();
        } else if (e.statusCode == 400 && e.message.contains('недоступны')) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(e.message),
              backgroundColor: Colors.orange,
            ),
          );
        } else if (e.statusCode == 400 && e.message.contains('нет доступных')) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Нет доступных промокодов'),
              backgroundColor: Colors.orange,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Ошибка: ${e.message}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading[brand] = false;
        });
      }
    }
  }

  void _handleUnauthorized() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Сессия истекла. Требуется вход'),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Получить промокод')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Выводим информацию об активном бренде
            if (_activeBrand != null)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.star, color: Colors.amber),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Сейчас активен бренд: $_activeBrand',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              )
            else
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: Text(
                  'Все бренды доступны',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
              ),
            // Список брендов
            ...[
              'JET',
              'YANDEX',
              'WHOOSH',
              'BOLT',
            ].map((brand) {
              // Проверяем, нужно ли показывать этот бренд
              if (_activeBrand != null && brand != _activeBrand) {
                // Не показываем, если активен другой бренд
                return const SizedBox.shrink();
              }

              final isClaimed = _claimed.containsKey(brand) &&
                  (_claimed[brand]?.isNotEmpty ?? false);
              final isLoading = _isLoading[brand] ?? false;
              final canClaim =
                  _isShiftActive == true && !isClaimed && !isLoading;

              String subtitleText;
              Color? subtitleColor;
              IconData trailingIcon = Icons.arrow_forward_ios;
              Color trailingColor = Colors.grey;

              if (_isShiftActive == null) {
                subtitleText = 'Проверка смены...';
                subtitleColor = Colors.grey;
              } else if (!_isShiftActive!) {
                subtitleText = 'Недоступно: смена не начата';
                subtitleColor = Colors.red;
              } else if (isClaimed) {
                subtitleText = 'Получено: ${_claimed[brand]!.join(", ")}';
                subtitleColor = Colors.green;
                trailingIcon = Icons.check_circle;
                trailingColor = Colors.green;
              } else {
                subtitleText = 'Нажмите, чтобы получить промокод';
                subtitleColor = Colors.blue;
              }

              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                child: ListTile(
                  leading: Icon(
                    _getBrandIcon(brand),
                    size: 32,
                    color: canClaim ? Colors.blue : Colors.grey,
                  ),
                  title: Text(
                    brand,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: canClaim ? Colors.blue : Colors.grey,
                    ),
                  ),
                  subtitle: Text(
                    subtitleText,
                    style: TextStyle(color: subtitleColor),
                  ),
                  trailing: isLoading
                      ? const CircularProgressIndicator()
                      : Icon(trailingIcon, color: trailingColor),
                  onTap: canClaim ? () => _claimPromo(brand) : null,
                  enabled: canClaim,
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  // Вспомогательная функция для иконок брендов
  IconData _getBrandIcon(String brand) {
    switch (brand) {
      case 'JET':
        return Icons.electric_scooter;
      case 'YANDEX':
        return Icons.map;
      case 'WHOOSH':
        return Icons.directions_bike;
      case 'BOLT':
        return Icons.bolt;
      default:
        return Icons.help;
    }
  }
}
