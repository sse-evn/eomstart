// lib/screens/profile/promo_code_screen.dart
import 'package:flutter/material.dart';
import 'package:micro_mobility_app/services/promo_api_service.dart';
import 'package:micro_mobility_app/main.dart' as app;
import 'package:micro_mobility_app/utils/auth_utils.dart';
import 'package:micro_mobility_app/utils/auth_utils.dart' as app show logout;

class PromoCodeScreen extends StatefulWidget {
  const PromoCodeScreen({super.key});

  @override
  State<PromoCodeScreen> createState() => _PromoCodeScreenState();
}

class _PromoCodeScreenState extends State<PromoCodeScreen> {
  final PromoApiService _service = PromoApiService();
  final Map<String, bool> _isLoading = {
    'JET': false,
    'YANDEX': false,
    'WHOOSH': false,
    'BOLT': false,
  };
  final Map<String, List<String>> _claimed = {};

  @override
  void initState() {
    super.initState();
    _loadClaimedPromos();
  }

  Future<void> _loadClaimedPromos() async {
    // Здесь можно загрузить сохраненные промокоды из профиля
    // Пока просто оставим пустым - они будут загружаться при первом запросе
  }

  Future<void> _claimPromo(String brand) async {
    setState(() {
      _isLoading[brand] = true;
    });

    try {
      final response = await _service.claimPromoByBrand(brand);
      final codes = (response['promo_codes'] as List).cast<String>();
      final alreadyClaimed = response['already_claimed'] ?? false;

      if (mounted) {
        setState(() {
          _claimed[brand] = codes;
        });

        final codeText = codes.length == 1 ? codes[0] : codes.join(', ');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(alreadyClaimed
                ? 'У вас уже есть промокод: $codeText'
                : 'Получено: $codeText'),
            backgroundColor: alreadyClaimed ? Colors.blue : Colors.green,
          ),
        );
      }
    } on PromoApiServiceException catch (e) {
      if (mounted) {
        if (e.statusCode == 401) {
          _handleUnauthorized();
        } else if (e.statusCode == 400 && e.message.contains('нет доступных')) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: const Text('Нет доступных промокодов'),
                backgroundColor: Colors.orange),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Ошибка: ${e.message}'),
                backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red),
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
          backgroundColor: Colors.red),
    );
    // Выход из аккаунта
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
    final isClaimed = _claimed.containsKey(brand);
    final isLoading = _isLoading[brand] ?? false;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: ListTile(
        leading: Icon(icon, size: 32),
        title: Text(brand, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: isClaimed
            ? Text('Получено: ${_claimed[brand]!.join(", ")}')
            : const Text('Нажмите, чтобы получить промокод'),
        trailing: isLoading
            ? const CircularProgressIndicator()
            : Icon(isClaimed ? Icons.check_circle : Icons.arrow_forward_ios),
        onTap: isClaimed || isLoading ? null : () => _claimPromo(brand),
      ),
    );
  }
}
// // lib/screens/profile/promo_code_screen.dart
// import 'package:flutter/material.dart';
// import 'package:micro_mobility_app/services/promo_api_service.dart';
// import 'package:micro_mobility_app/main.dart' as app;
// import 'package:micro_mobility_app/utils/auth_utils.dart';
// import 'package:micro_mobility_app/utils/auth_utils.dart' as app show logout;

// class PromoCodeScreen extends StatefulWidget {
//   const PromoCodeScreen({super.key});

//   @override
//   State<PromoCodeScreen> createState() => _PromoCodeScreenState();
// }

// class _PromoCodeScreenState extends State<PromoCodeScreen> {
//   final PromoApiService _service = PromoApiService();
//   final Map<String, bool> _isLoading = {
//     'JET': false,
//     'YANDEX': false,
//     'WHOOSH': false,
//     'BOLT': false,
//   };
//   final Map<String, List<String>> _claimed = {};

//   @override
//   void initState() {
//     super.initState();
//     _loadClaimedPromos();
//   }

//   Future<void> _loadClaimedPromos() async {
//     try {
//       // Получаем профиль пользователя, который теперь содержит promo_codes
//       final profile = await _getProfile();
      
//       if (profile.containsKey('promo_codes') && profile['promo_codes'] != null) {
//         final promoCodes = profile['promo_codes'] as Map<String, dynamic>;
//         setState(() {
//           _claimed['JET'] = promoCodes['JET']?.cast<String>() ?? [];
//           _claimed['YANDEX'] = promoCodes['YANDEX']?.cast<String>() ?? [];
//           _claimed['WHOOSH'] = promoCodes['WHOOSH']?.cast<String>() ?? [];
//           _claimed['BOLT'] = promoCodes['BOLT']?.cast<String>() ?? [];
//         });
//       }
//     } catch (e) {
//       // Игнорируем ошибки загрузки - промокоды будут загружены при первом запросе
//       if (mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(content: Text('Не удалось загрузить сохраненные промокоды: $e'), backgroundColor: Colors.orange),
//         );
//       }
//     }
//   }

//   // Вспомогательный метод для получения профиля
//   Future<Map<String, dynamic>> _getProfile() async {
//     final token = await _getToken();
//     if (token == null) {
//       throw Exception('Не авторизован');
//     }

//     final response = await http.get(
//       Uri.parse('${AppConfig.apiBaseUrl}/profile'),
//       headers: {'Authorization': 'Bearer $token'},
//     );

//     if (response.statusCode == 200) {
//       return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
//     } else {
//       throw Exception('Ошибка загрузки профиля');
//     }
//   }

//   // Вспомогательные методы (скопируйте из вашего auth_utils или promo_api_service)
//   Future<String?> _getToken() async {
//     final storage = const FlutterSecureStorage();
//     return await storage.read(key: 'jwt_token');
//   }

//   Future<void> _claimPromo(String brand) async {
//     setState(() {
//       _isLoading[brand] = true;
//     });

//     try {
//       final response = await _service.claimPromoByBrand(brand);
//       final codes = (response['promo_codes'] as List).cast<String>();
//       final alreadyClaimed = response['already_claimed'] ?? false;
      
//       if (mounted) {
//         setState(() {
//           _claimed[brand] = codes;
//         });
        
//         final codeText = codes.length == 1 ? codes[0] : codes.join(', ');
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(
//             content: Text(alreadyClaimed 
//                 ? 'У вас уже есть промокод: $codeText' 
//                 : 'Получено: $codeText'),
//             backgroundColor: alreadyClaimed ? Colors.blue : Colors.green,
//           ),
//         );
//       }
//     } on PromoApiServiceException catch (e) {
//       if (mounted) {
//         if (e.statusCode == 401) {
//           _handleUnauthorized();
//         } else if (e.statusCode == 400 && e.message.contains('нет доступных')) {
//           ScaffoldMessenger.of(context).showSnackBar(
//             SnackBar(
//                 content: const Text('Нет доступных промокодов'),
//                 backgroundColor: Colors.orange),
//           );
//         } else {
//           ScaffoldMessenger.of(context).showSnackBar(
//             SnackBar(
//                 content: Text('Ошибка: ${e.message}'),
//                 backgroundColor: Colors.red),
//           );
//         }
//       }
//     } catch (e) {
//       if (mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red),
//         );
//       }
//     } finally {
//       if (mounted) {
//         setState(() {
//           _isLoading[brand] = false;
//         });
//       }
//     }
//   }

//   void _handleUnauthorized() {
//     ScaffoldMessenger.of(context).showSnackBar(
//       const SnackBar(
//           content: Text('Сессия истекла. Требуется вход'),
//           backgroundColor: Colors.red),
//     );
//     // Выход из аккаунта
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(title: const Text('Получить промокод')),
//       body: Padding(
//         padding: const EdgeInsets.all(16),
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.stretch,
//           children: [
//             _buildBrandCard('JET', Icons.electric_scooter),
//             _buildBrandCard('YANDEX', Icons.map),
//             _buildBrandCard('WHOOSH', Icons.directions_bike),
//             _buildBrandCard('BOLT', Icons.bolt),
//           ],
//         ),
//       ),
//     );
//   }

//   Widget _buildBrandCard(String brand, IconData icon) {
//     final isClaimed = _claimed.containsKey(brand) && _claimed[brand]!.isNotEmpty;
//     final isLoading = _isLoading[brand] ?? false;
//     final codes = _claimed[brand] ?? [];

//     return Card(
//       margin: const EdgeInsets.only(bottom: 16),
//       child: ListTile(
//         leading: Icon(icon, size: 32),
//         title: Text(brand, style: const TextStyle(fontWeight: FontWeight.bold)),
//         subtitle: isClaimed
//             ? Text('Получено: ${codes.join(", ")}')
//             : const Text('Нажмите, чтобы получить промокод'),
//         trailing: isLoading
//             ? const CircularProgressIndicator()
//             : Icon(isClaimed ? Icons.check_circle : Icons.arrow_forward_ios),
//         onTap: isClaimed || isLoading ? null : () => _claimPromo(brand),
//       ),
//     );
//   }
// }

// // Импорты для вспомогательных методов
// import 'dart:convert';
// import 'package:http/http.dart' as http;
// import 'package:flutter_secure_storage/flutter_secure_storage.dart';
// import 'package:micro_mobility_app/config/app_config.dart';