// lib/screens/profile/promo_code_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:micro_mobility_app/services/user_promo_service.dart';

class PromoCodeScreen extends StatefulWidget {
  const PromoCodeScreen({super.key});

  @override
  State<PromoCodeScreen> createState() => _PromoCodeScreenState();
}

class _PromoCodeScreenState extends State<PromoCodeScreen> {
  final UserPromoService _promoService = UserPromoService();

  List<Map<String, dynamic>> _dailyPromos = [];
  Set<String> _claimedCodes = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPromoCodes();
  }

  Future<void> _loadPromoCodes() async {
    try {
      final data = await _promoService.fetchDailyPromoCodes();

      final promosRaw = data['promos'];
      final claimedRaw = data['claimed'];

      List<Map<String, dynamic>> promos = [];
      if (promosRaw is List) {
        promos = promosRaw
            .where((e) => e is Map<String, dynamic>)
            .map((e) => e as Map<String, dynamic>)
            .toList();
      }

      Set<String> claimed = {};
      if (claimedRaw is List) {
        claimed = claimedRaw
            .where((e) => e is String)
            .map((e) => e as String)
            .toSet();
      }

      if (mounted) {
        setState(() {
          _dailyPromos = promos;
          _claimedCodes = claimed;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка загрузки промокодов: $e'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _claimPromo(String promoId, DateTime date) async {
    try {
      await _promoService.claimPromoCode(promoId);

      if (mounted) {
        setState(() {
          _claimedCodes.add(promoId);
        });

        final formattedDate = DateFormat('dd.MM.yyyy').format(date);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Промокод за $formattedDate получен!'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
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
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ежедневные промокоды')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _dailyPromos.isEmpty
              ? const Center(child: Text('Нет доступных промокодов'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _dailyPromos.length,
                  itemBuilder: (context, index) {
                    final promo = _dailyPromos[index];
                    final promoId = promo['id']?.toString() ?? '';
                    final dateString = promo['date']?.toString() ?? '';
                    final title = promo['title']?.toString() ?? 'Бонус';
                    final description = promo['description']?.toString() ?? '';
                    final isClaimed = _claimedCodes.contains(promoId);

                    final date = DateTime.tryParse(dateString);
                    final formattedDate = date != null
                        ? DateFormat('EEEE, dd MMMM', 'ru_RU').format(date)
                        : dateString;

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              formattedDate,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(title, style: const TextStyle(fontSize: 18)),
                            if (description.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                description,
                                style: const TextStyle(color: Colors.grey),
                              ),
                            ],
                            const SizedBox(height: 12),
                            Align(
                              alignment: Alignment.centerRight,
                              child: ElevatedButton(
                                onPressed: isClaimed
                                    ? null
                                    : () => _claimPromo(
                                        promoId, date ?? DateTime.now()),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                      isClaimed ? Colors.grey : Colors.green,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 20, vertical: 8),
                                ),
                                child: Text(
                                  isClaimed ? 'Получено' : 'Получить',
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
