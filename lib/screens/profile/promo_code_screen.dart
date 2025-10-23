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

  final Map<String, bool> _isLoading = {
    'JET': false,
    'YANDEX': false,
    'WHOOSH': false,
    'BOLT': false,
  };
  final Map<String, List<String>> _claimed = {};
  bool? _isShiftActive;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    await _loadClaimedPromos();
    await _checkShiftStatus();
  }

  Future<void> _loadClaimedPromos() async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token == null) return;

      final profile = await _apiService.getUserProfile(token);
      if (profile.containsKey('promo_codes') &&
          profile['promo_codes'] != null) {
        final promoCodes = profile['promo_codes'] as Map<String, dynamic>;
        setState(() {
          _claimed['JET'] = promoCodes['JET']?.cast<String>() ?? [];
          _claimed['YANDEX'] = promoCodes['YANDEX']?.cast<String>() ?? [];
          _claimed['WHOOSH'] = promoCodes['WHOOSH']?.cast<String>() ?? [];
          _claimed['BOLT'] = promoCodes['BOLT']?.cast<String>() ?? [];
        });
      }
    } catch (e) {}
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
        setState(() {
          _claimed[brand] = codes;
        });

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
            _buildBrandCard('JET', Icons.electric_scooter),
            _buildBrandCard('YANDEX', Icons.map),
            _buildBrandCard('WHOOSH', Icons.directions_bike),
            _buildBrandCard('BOLT', Icons.bolt),
          ],
        ),
      ),
    );
  }

  Widget _buildBrandCard(String brand, IconData icon) {
    final isClaimed =
        _claimed.containsKey(brand) && (_claimed[brand]?.isNotEmpty ?? false);
    final isLoading = _isLoading[brand] ?? false;
    final canClaim = _isShiftActive == true && !isClaimed && !isLoading;

    String subtitleText;
    if (_isShiftActive == null) {
      subtitleText = 'Проверка смены...';
    } else if (!_isShiftActive!) {
      subtitleText = 'Недоступно: смена не начата';
    } else if (isClaimed) {
      subtitleText = 'Получено: ${_claimed[brand]!.join(", ")}';
    } else {
      subtitleText = 'Нажмите, чтобы получить промокод';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Opacity(
        opacity: _isShiftActive == false ? 0.5 : 1.0,
        child: ListTile(
          leading: Icon(icon, size: 32),
          title:
              Text(brand, style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(subtitleText),
          trailing: isLoading
              ? const CircularProgressIndicator()
              : Icon(isClaimed ? Icons.check_circle : Icons.arrow_forward_ios),
          onTap: canClaim ? () => _claimPromo(brand) : null,
        ),
      ),
    );
  }
}
