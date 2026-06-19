import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:micro_mobility_app/src/core/providers/language_provider.dart';
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
  Map<String, dynamic>? _boltAccount;

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
    await _loadBoltAccount();
  }

  Future<void> _loadBoltAccount() async {
    try {
      final account = await _promoService.getMyBoltAccount();
      if (mounted) setState(() => _boltAccount = account);
    } catch (_) {}
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
          SnackBar(
            content: Text(tr(context, 'Вы уже получали промокод этого бренда сегодня', 'Бұл брендтің промокодын бүгін алдыңыз')),
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
                ? tr(context, 'Вы уже получали промокод для $brand сегодня: $codeText', 'Сіз бүгін $brand үшін промокодты алдыңыз: $codeText')
                : tr(context, 'Получено: $codeText', 'Алынды: $codeText')),
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
            SnackBar(
              content: Text(tr(context, 'Вы уже получали промокод этого бренда сегодня', 'Бұл брендтің промокодын бүгін алдыңыз')),
              backgroundColor: Colors.orange,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(tr(context, 'Ошибка: ${e.message}', 'Қате: ${e.message}')),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tr(context, 'Ошибка: $e', 'Қате: $e')),
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
      SnackBar(
        content: Text(tr(context, 'Сессия истекла. Требуется вход', 'Сессия аяқталды. Кіру қажет')),
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
        title: Text(tr(context, 'Промокоды', 'Промокодтар'), style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await Provider.of<ShiftProvider>(context, listen: false).loadProfile();
          _syncWithProfile();
          await _loadActiveBrand();
          await _loadBoltAccount();
        },
        child: ListView(
          padding: EdgeInsets.all(16),
          children: [
            _buildStatusHeader(theme),
            SizedBox(height: 16),
            ...['JET', 'YANDEX', 'WHOOSH', 'BOLT'].map((brand) {
              final isClaimed = _hasClaimedToday[brand] ?? false;
              final hasActiveBrand = _activeBrand != null && _activeBrand!.isNotEmpty;
              
              // Bolt — отдельная логика (аккаунты, не промокоды)
              if (brand == 'BOLT') {
                if (_activeBrand != 'BOLT') {
                  return SizedBox.shrink();
                }
                return _buildBoltAccountCard(isDark);
              }
              
              // 1. Если админ не указал бренд, и мы его не брали - скрываем
              if (!hasActiveBrand && !isClaimed) {
                return SizedBox.shrink();
              }
              
              // 2. Если админ указал ДРУГОЙ бренд, и мы его не брали - скрываем
              if (hasActiveBrand && brand != _activeBrand && !isClaimed) {
                return SizedBox.shrink();
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
      padding: EdgeInsets.all(16),
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
          SizedBox(width: 12),
          Expanded(
            child: Text(
              alreadyClaimed
                  ? tr(context, 'Промокод для $_activeBrand успешно получен!', '$_activeBrand үшін промокод сәтті алынды!')
                  : (hasActiveBrand 
                      ? tr(context, 'Сегодня работаем с $_activeBrand', 'Бүгін $_activeBrand жұмыс істейміз') 
                      : tr(context, 'Промокоды на сегодня не назначены', 'Бүгінге промокодтар берілмеген')),
              style: TextStyle(fontWeight: FontWeight.bold),
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
      margin: EdgeInsets.only(bottom: 16),
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
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          ListTile(
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: brandColor.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(_getBrandIcon(brand), color: brandColor, size: 28),
            ),
            title: Text(
              brand,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
            ),
            subtitle: Text(
              isClaimed 
                  ? tr(context, 'ВАШ ПРОМОКОД ПОЛУЧЕН', 'СІЗДІҢ ПРОМОКОД АЛЫНДЫ') 
                  : tr(context, 'Доступен 1 раз за смену', 'Ауысымда 1 рет қолжетімді'),
              style: TextStyle(
                color: isClaimed ? Colors.green : Colors.grey,
                fontWeight: isClaimed ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            trailing: isLoading
                ? SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                : (isClaimed 
                    ? Icon(Icons.stars_rounded, color: Colors.green, size: 32)
                    : (_isShiftActive == true 
                        ? ElevatedButton(
                            onPressed: () => _claimPromo(brand),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: brandColor,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: Text(tr(context, 'ПОЛУЧИТЬ', 'АЛУ')),
                          )
                        : Icon(Icons.lock_outline, size: 24, color: Colors.grey))),
          ),
          if (isClaimed && codes.isNotEmpty)
            Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                children: [
                  const Divider(height: 24),
                  Text(
                    tr(context, 'СКОПИРУЙТЕ И ИСПОЛЬЗУЙТЕ:', 'КӨШІРІП АЛЫП ҚОЛДАНЫҢЫЗ:'),
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1),
                  ),
                  SizedBox(height: 12),
                  if (brand == 'YANDEX' && codes.length >= 2) ...[
                    _buildLabeledCodeRow(codes[0], tr(context, '🔴 Бесплатный старт', '🔴 Тегін старт'), Colors.red, isDark),
                    SizedBox(height: 4),
                    _buildLabeledCodeRow(codes[1], tr(context, '🟢 Бесплатные минуты', '🟢 Тегін минуттар'), Colors.green, isDark),
                  ] else
                    ...codes.map((code) => _buildProminentCodeRow(code, brandColor, isDark)),
                  SizedBox(height: 8),
                  Text(
                    tr(context, 'Действует до конца смены', 'Ауысым соңына дейін жарамды'),
                    style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.grey),
                  ),
                  if (_isShiftActive == true) ...[
                    SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          setState(() {
                            _hasClaimedToday[brand] = false;
                          });
                          _claimPromo(brand);
                        },
                        icon: Icon(Icons.add_circle_outline, size: 18),
                        label: Text(tr(context, 'ПОЛУЧИТЬ 2-Й ПРОМОКОД', '2-ШІ ПРОМОКОДТЫ АЛУ')),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: brandColor,
                          side: BorderSide(color: brandColor.withOpacity(0.5)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          if (_isShiftActive == false && !isClaimed)
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: Center(
                child: Text(
                  tr(context, 'НУЖНО ОТКРЫТЬ СМЕНУ', 'АУЫСЫМ АШУ КЕРЕК'),
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
      margin: EdgeInsets.only(top: 8),
      padding: EdgeInsets.all(16),
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
                  content: Text(tr(context, 'Промокод $code скопирован!', '$code промокоды көшірілді!')),
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

  Widget _buildLabeledCodeRow(String code, String label, Color color, bool isDark) {
    return Container(
      margin: EdgeInsets.only(top: 8),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.5), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color,
              letterSpacing: 1,
            ),
          ),
          SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  code,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: color,
                    letterSpacing: 2,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(Icons.copy_rounded, color: color, size: 28),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: code));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(tr(context, 'Промокод $code скопирован!', '$code промокоды көшірілді!')),
                      backgroundColor: color,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _getBrandColor(String brand) {
    switch (brand) {
      case 'JET': return Colors.purple;
      case 'YANDEX': return Color(0xFFFFB300);
      case 'WHOOSH': return Color(0xFFFFD100);
      case 'BOLT': return Color(0xFF32BB78);
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

  Widget _buildBoltAccountCard(bool isDark) {
    final hasAccount = _boltAccount != null;
    final isLocked = hasAccount && (_boltAccount!['is_locked'] == true || _isShiftActive != true);
    const brandColor = Color(0xFF32BB78);

    return Container(
      margin: EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: (hasAccount && !isLocked)
            ? brandColor.withOpacity(isDark ? 0.15 : 0.05)
            : Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: (hasAccount && !isLocked) ? brandColor : Colors.transparent,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          ListTile(
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: brandColor.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.bolt, color: brandColor, size: 28),
            ),
            title: Text(
              'BOLT',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
            ),
            subtitle: Text(
              isLocked 
                  ? tr(context, 'АККАУНТ НАЗНАЧЕН (СКРЫТ)', 'АККАУНТ БЕРІЛДІ (ЖАСЫРЫН)') 
                  : (hasAccount ? tr(context, 'АККАУНТ НАЗНАЧЕН', 'АККАУНТ БЕРІЛДІ') : tr(context, 'Аккаунт не назначен', 'Аккаунт тағайындалмаған')),
              style: TextStyle(
                color: hasAccount ? (isLocked ? Colors.orange : Colors.green) : Colors.grey,
                fontWeight: hasAccount ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            trailing: hasAccount
                ? (isLocked 
                    ? Icon(Icons.lock_clock, color: Colors.orange, size: 32)
                    : Icon(Icons.check_circle, color: Colors.green, size: 32))
                : Icon(Icons.lock_outline, size: 24, color: Colors.grey),
          ),
          if (hasAccount && !isLocked) ...[
            Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                children: [
                  const Divider(height: 24),
                  Text(
                    tr(context, 'ДАННЫЕ ДЛЯ ВХОДА:', 'КІРУ ДЕРЕКТЕРІ:'),
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1),
                  ),
                  SizedBox(height: 12),
                  // Login
                  Container(
                    padding: EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white10 : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: brandColor.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.person_outline, color: brandColor, size: 20),
                        SizedBox(width: 10),
                        Text(tr(context, 'Логин: ', 'Логин: '), style: TextStyle(fontSize: 13, color: Colors.grey)),
                        Expanded(
                          child: Text(
                            _boltAccount!['login'] ?? '',
                            style: TextStyle(fontFamily: 'monospace', fontSize: 18, fontWeight: FontWeight.w900, color: brandColor, letterSpacing: 1),
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.copy_rounded, color: brandColor, size: 22),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: _boltAccount!['login'] ?? ''));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(tr(context, 'Логин скопирован', 'Логин көшірілді')), backgroundColor: brandColor, behavior: SnackBarBehavior.floating),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 8),
                  // Password
                  Container(
                    padding: EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white10 : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: brandColor.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.lock_outline, color: brandColor, size: 20),
                        SizedBox(width: 10),
                        Text(tr(context, 'Пароль: ', 'Құпия сөз: '), style: TextStyle(fontSize: 13, color: Colors.grey)),
                        Expanded(
                          child: Text(
                            _boltAccount!['password'] ?? '',
                            style: TextStyle(fontFamily: 'monospace', fontSize: 18, fontWeight: FontWeight.w900, color: brandColor, letterSpacing: 1),
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.copy_rounded, color: brandColor, size: 22),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: _boltAccount!['password'] ?? ''));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(tr(context, 'Пароль скопирован', 'Құпия сөз көшірілді')), backgroundColor: brandColor, behavior: SnackBarBehavior.floating),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  if (_boltAccount!['description'] != null && (_boltAccount!['description'] as String).isNotEmpty) ...[
                    SizedBox(height: 8),
                    Text(
                      _boltAccount!['description'],
                      style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.grey),
                    ),
                  ],
                ],
              ),
            ),
          ] else if (isLocked)
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: Center(
                child: Text(
                  tr(context, 'СНАЧАЛА ОТКРОЙТЕ СМЕНУ', 'АЛДЫМЕН АУЫСЫМДЫ АШЫҢЫЗ'),
                  style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            )
          else
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: Center(
                child: Text(
                  tr(context, 'Обратитесь к администратору', 'Администраторға хабарласыңыз'),
                  style: TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
