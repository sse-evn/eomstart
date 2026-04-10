import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';
import 'package:micro_mobility_app/src/core/providers/shift_provider.dart';
import 'package:micro_mobility_app/src/core/services/api_service.dart';
import 'package:micro_mobility_app/src/core/services/promo_api_service.dart';

class PromoCodeScreen extends StatefulWidget {
  const PromoCodeScreen({super.key});

  @override
  State<PromoCodeScreen> createState() => _PromoCodeScreenState();
}

class _PromoCodeScreenState extends State<PromoCodeScreen> {
  final PromoApiService _promoService = PromoApiService();
  final ApiService _apiService = ApiService();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  String? _activeBrand;
  bool? _isShiftActive;
  final Map<String, List<String>> _claimedToday = {};
  final Map<String, bool> _isLoading = {
    'JET': false,
    'YANDEX': false,
    'WHOOSH': false,
    'BOLT': false,
  };
  final Map<String, bool> _hasClaimedToday = {
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
    final shiftProvider = Provider.of<ShiftProvider>(context, listen: false);
    if (!shiftProvider.hasLoadedProfile) {
      await shiftProvider.loadProfile();
    }
    _syncWithProfile();
    await _checkShiftStatus();
    await _loadActiveBrand();
  }

  void _syncWithProfile() {
    final profile = Provider.of<ShiftProvider>(context, listen: false).profile;
    if (profile != null && profile['promo_codes'] != null) {
      final promos = profile['promo_codes'] as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _claimedToday.clear();
          _hasClaimedToday.updateAll((key, value) => false);
          promos.forEach((brand, codes) {
            if (codes is List) {
              final brandUp = brand.toUpperCase();
              _claimedToday[brandUp] = codes.cast<String>();
              _hasClaimedToday[brandUp] = true;
            }
          });
        });
      }
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
      if (mounted) {
        setState(() {
          _activeBrand = null;
        });
      }
    }
  }

  Future<void> _claimPromo(String brand) async {
    if (_isShiftActive != true) return;
    if (_hasClaimedToday[brand] == true) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Вы уже получали промокод этого бренда сегодня'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    setState(() {
      _isLoading[brand] = true;
    });

    try {
      final response = await _promoService.claimPromoByBrand(brand);
      final codes = (response['promo_codes'] as List).cast<String>();
      final alreadyClaimedToday = response['already_claimed'] ?? false;

      if (mounted) {
        setState(() {
          _hasClaimedToday[brand] = true;
          _claimedToday[brand] = codes;
        });

        final shiftProvider = Provider.of<ShiftProvider>(context, listen: false);
        await shiftProvider.loadProfile();
        _syncWithProfile();

        final codeText = codes.length == 1 ? codes[0] : codes.join(', ');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(alreadyClaimedToday
                ? 'Вы уже получали промокод для $brand сегодня: $codeText'
                : 'Получено: $codeText'),
            backgroundColor: alreadyClaimedToday ? Colors.orange : Colors.green,
          ),
        );
      }
    } on PromoApiServiceException catch (e) {
      if (mounted) {
        if (e.statusCode == 401) {
          _handleUnauthorized();
        } else if (e.statusCode == 409) {
          setState(() {
            _hasClaimedToday[brand] = true;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Вы уже получали промокод этого бренда сегодня'),
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
      body: RefreshIndicator(
        onRefresh: () async {
          await Provider.of<ShiftProvider>(context, listen: false).loadProfile();
          _syncWithProfile();
          await _loadActiveBrand();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
                      const Icon(Icons.star, color: Colors.amber),
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
              ...[
                'JET',
                'YANDEX',
                'WHOOSH',
                'BOLT',
              ].map((brand) {
                if (_activeBrand != null && brand != _activeBrand) {
                  return const SizedBox.shrink();
                }

                final isClaimedToday = _hasClaimedToday[brand] ?? false;
                final isLoading = _isLoading[brand] ?? false;
                final canClaim = _isShiftActive == true && !isClaimedToday && !isLoading;

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
                } else if (isClaimedToday) {
                  final codes = _claimedToday[brand];
                  subtitleText = 'Получено сегодня: ${codes != null && codes.isNotEmpty ? codes.join(", ") : "Коды"}';
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
              }),
            ],
          ),
        ),
      ),
    );
  }

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
