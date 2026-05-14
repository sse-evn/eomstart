import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    _loadCachedPromos(); // Сначала грузим из кэша для мгновенного показа
    _loadData();
  }

  Future<void> _loadCachedPromos() async {
    try {
      final cached = await _storage.read(key: 'cached_promos_json_v2');
      if (cached != null) {
        final Map<String, dynamic> data = jsonDecode(cached);
        final cachedDate = data['date'];
        final today = DateTime.now().toIso8601String().split('T')[0];

        if (cachedDate == today && data['promos'] != null) {
          final promos = data['promos'] as Map<String, dynamic>;
          if (mounted) {
            setState(() {
              promos.forEach((brand, codes) {
                if (codes is List && codes.isNotEmpty) {
                  final b = brand.toUpperCase();
                  _claimedToday[b] = codes.cast<String>();
                  _hasClaimedToday[b] = true;
                }
              });
            });
          }
        } else {
          // Кэш устарел (другой день), удаляем
          await _storage.delete(key: 'cached_promos_json_v2');
        }
      }
    } catch (e) {
      debugPrint('Error loading cached promos: $e');
    }
  }

  Future<void> _savePromosToCache() async {
    try {
      final dataToSave = {
        'date': DateTime.now().toIso8601String().split('T')[0],
        'promos': _claimedToday,
      };
      await _storage.write(key: 'cached_promos_json_v2', value: jsonEncode(dataToSave));
    } catch (e) {
      debugPrint('Error saving promos to cache: $e');
    }
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
    debugPrint('Syncing with profile: $profile');
    if (profile != null && profile['promo_codes'] != null) {
      final promos = profile['promo_codes'] as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          promos.forEach((brand, codes) {
            if (codes is List && codes.isNotEmpty) {
              final brandUp = brand.toUpperCase();
              _claimedToday[brandUp] = codes.cast<String>();
              _hasClaimedToday[brandUp] = true;
            }
          });
          _savePromosToCache(); 
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
          // Запрашиваем обновление профиля, если бэк говорит, что уже брали
          final shiftProvider = Provider.of<ShiftProvider>(context, listen: false);
          await shiftProvider.loadProfile();
          _syncWithProfile();

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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Промокоды', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await Provider.of<ShiftProvider>(context, listen: false).loadProfile();
          _syncWithProfile();
          await _loadActiveBrand();
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildStatusHeader(theme),
            const SizedBox(height: 16),
            ...['JET', 'YANDEX', 'WHOOSH', 'BOLT'].map((brand) {
              final isClaimed = _hasClaimedToday[brand] ?? false;
              final hasActiveBrand = _activeBrand != null && _activeBrand!.isNotEmpty;
              
              // 1. Если админ не указал бренд, и мы его не брали - скрываем
              if (!hasActiveBrand && !isClaimed) {
                return const SizedBox.shrink();
              }
              
              // 2. Если админ указал ДРУГОЙ бренд, и мы его не брали - скрываем
              if (hasActiveBrand && brand != _activeBrand && !isClaimed) {
                return const SizedBox.shrink();
              }
              
              return _buildSimpleBrandCard(brand, theme, isDark);
            }),

          ],
        ),
      ),
    );
  }

  Widget _buildStatusHeader(ThemeData theme) {
    bool hasActiveBrand = _activeBrand != null && _activeBrand!.isNotEmpty;
    bool alreadyClaimed = hasActiveBrand && (_hasClaimedToday[_activeBrand!] ?? false);
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: alreadyClaimed 
            ? Colors.green.withOpacity(0.1)
            : (hasActiveBrand 
                ? Colors.orange.withOpacity(0.15) 
                : Colors.red.withOpacity(0.1)),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: alreadyClaimed 
              ? Colors.green 
              : (hasActiveBrand ? Colors.orange : Colors.red.withOpacity(0.5)),
        ),
      ),
      child: Row(
        children: [
          Icon(
            alreadyClaimed 
                ? Icons.check_circle 
                : (hasActiveBrand ? Icons.stars_rounded : Icons.block),
            color: alreadyClaimed 
                ? Colors.green 
                : (hasActiveBrand ? Colors.orange : Colors.red),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              alreadyClaimed
                  ? 'Промокод для $_activeBrand успешно получен!'
                  : (hasActiveBrand 
                      ? 'Сегодня работаем с $_activeBrand' 
                      : 'Промокоды на сегодня не назначены'),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSimpleBrandCard(String brand, ThemeData theme, bool isDark) {
    final isClaimed = _hasClaimedToday[brand] ?? false;
    final isLoading = _isLoading[brand] ?? false;
    final codes = _claimedToday[brand] ?? [];
    final brandColor = _getBrandColor(brand);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isClaimed 
            ? brandColor.withOpacity(isDark ? 0.15 : 0.05) 
            : theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isClaimed ? brandColor : Colors.transparent,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: brandColor.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(_getBrandIcon(brand), color: brandColor, size: 28),
            ),
            title: Text(
              brand,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
            ),
            subtitle: Text(
              isClaimed 
                  ? 'ВАШ ПРОМОКОД ПОЛУЧЕН' 
                  : 'Доступен 1 раз за смену',
              style: TextStyle(
                color: isClaimed ? Colors.green : Colors.grey,
                fontWeight: isClaimed ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            trailing: isLoading
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                : (isClaimed 
                    ? const Icon(Icons.stars_rounded, color: Colors.green, size: 32)
                    : (_isShiftActive == true 
                        ? ElevatedButton(
                            onPressed: () => _claimPromo(brand),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: brandColor,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text('ПОЛУЧИТЬ'),
                          )
                        : const Icon(Icons.lock_outline, size: 24, color: Colors.grey))),
          ),
          if (isClaimed && codes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                children: [
                  const Divider(height: 24),
                  const Text(
                    'СКОПИРУЙТЕ И ИСПОЛЬЗУЙТЕ:',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1),
                  ),
                  const SizedBox(height: 12),
                  ...codes.map((code) => _buildProminentCodeRow(code, brandColor, isDark)).toList(),
                  const SizedBox(height: 8),
                  const Text(
                    'Действует до конца смены',
                    style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.grey),
                  ),
                ],
              ),
            ),
          if (_isShiftActive == false && !isClaimed)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: const Center(
                child: Text(
                  'НУЖНО ОТКРЫТЬ СМЕНУ',
                  style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildProminentCodeRow(String code, Color brandColor, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: brandColor.withOpacity(0.5), width: 1),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              code,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: brandColor,
                letterSpacing: 2,
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.copy_rounded, color: brandColor, size: 28),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Промокод $code скопирован!'),
                  backgroundColor: brandColor,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Color _getBrandColor(String brand) {
    switch (brand) {
      case 'JET': return Colors.purple;
      case 'YANDEX': return const Color(0xFFFFB300);
      case 'WHOOSH': return const Color(0xFFFFD100);
      case 'BOLT': return const Color(0xFF32BB78);
      default: return Colors.blue;
    }
  }

  IconData _getBrandIcon(String brand) {
    switch (brand) {
      case 'JET': return Icons.electric_scooter;
      case 'YANDEX': return Icons.local_taxi;
      case 'WHOOSH': return Icons.directions_bike;
      case 'BOLT': return Icons.bolt;
      default: return Icons.help_outline;
    }
  }
}
