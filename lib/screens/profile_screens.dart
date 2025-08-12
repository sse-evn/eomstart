import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:micro_mobility_app/services/api_service.dart';
import 'auth_screen/login_screen.dart';
import 'admin/admin_panel_screen.dart';
import 'package:micro_mobility_app/services/api_service.dart';
import 'auth_screen/login_screen.dart'; // ← Импортирует и ApiService тоже

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final ApiService _apiService = ApiService();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  late Future<Map<String, dynamic>> _profileFuture;
  String _userRole = 'user';

  @override
  void initState() {
    super.initState();
    _profileFuture = _loadProfile();
  }

  Future<Map<String, dynamic>> _loadProfile() async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token == null) throw Exception('Токен не найден');

      final profile = await _apiService.getUserProfile(token);

      // Сохраняем роль для UI
      final role = (profile['role'] ?? 'user').toString().toLowerCase();
      if (mounted) {
        setState(() {
          _userRole = role;
        });
      }

      return profile;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
      return {};
    }
  }

  Future<void> _refresh() async {
    if (mounted) {
      setState(() {
        _profileFuture = _loadProfile();
      });
    }
  }

  Future<void> _logout() async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token != null) {
        await _apiService.logout(token);
      }
      await _storage.delete(key: 'jwt_token');

      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Ошибка выхода')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Профиль'),
        centerTitle: true,
        backgroundColor: Colors.green[700],
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              // === Заголовок профиля ===
              FutureBuilder<Map<String, dynamic>>(
                future: _profileFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const _ProfileHeaderShimmer();
                  }

                  if (snapshot.hasError ||
                      !snapshot.hasData ||
                      snapshot.data!.isEmpty) {
                    return const _ProfileErrorCard();
                  }

                  return _ProfileHeader(user: snapshot.data!);
                },
              ),

              // === Настройки ===
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Настройки',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const _SettingsItem(
                icon: Icons.settings,
                title: 'Настройки',
                route: '/settings',
              ),

              const Divider(),

              // === Другое ===
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Другое',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const _SettingsItem(
                icon: Icons.info,
                title: 'О приложении',
                route: '/about',
              ),

              // === Админ-панель (только для superadmin) ===
              if (_userRole == 'superadmin')
                const _SettingsItem(
                  icon: Icons.admin_panel_settings,
                  title: 'Админ-панель',
                  route: '/admin',
                ),

              _SettingsItem(
                icon: Icons.logout,
                title: 'Выйти',
                color: Colors.red,
                onTap: _logout,
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

// === Заголовок профиля ===
class _ProfileHeader extends StatelessWidget {
  final Map<String, dynamic> user;

  const _ProfileHeader({required this.user});

  @override
  Widget build(BuildContext context) {
    final firstName = _safeString(user['firstName'] ?? user['first_name']);
    final lastName = _safeString(user['lastName'] ?? user['last_name']);
    final username = _safeString(user['username']);
    final role = _safeString(user['role']).toLowerCase();

    final fullName = (lastName.isNotEmpty || firstName.isNotEmpty)
        ? '$lastName $firstName'.trim()
        : (username.isNotEmpty ? username : 'Пользователь');

    final avatarUrl = _safeString(user['avatarUrl']);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.green[50],
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(30),
          bottomRight: Radius.circular(30),
        ),
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 60,
            backgroundColor: Colors.white,
            backgroundImage:
                avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
            child: avatarUrl.isEmpty
                ? const Icon(Icons.person, size: 60, color: Colors.grey)
                : null,
          ),
          const SizedBox(height: 16),
          Text(
            fullName,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _formatRole(role),
            style: const TextStyle(
              fontSize: 18,
              color: Colors.green,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  String _safeString(dynamic value) {
    if (value == null) return '';
    return value.toString().trim();
  }

  String _formatRole(String role) {
    return {
          'user': 'Пользователь',
          'scout': 'Скаут',
          'supervisor': 'Супервайзер',
          'coordinator': 'Координатор',
          'superadmin': 'Суперадмин',
        }[role] ??
        role.toUpperCase();
  }
}

// === Заглушка при загрузке ===
class _ProfileHeaderShimmer extends StatelessWidget {
  const _ProfileHeaderShimmer();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      color: Colors.green[50],
      child: Column(
        children: [
          const CircleAvatar(radius: 60, child: Icon(Icons.person, size: 60)),
          const SizedBox(height: 16),
          Container(
            width: 150,
            height: 20,
            color: Colors.white,
          ),
          const SizedBox(height: 8),
          Container(
            width: 100,
            height: 16,
            color: Colors.white,
          ),
        ],
      ),
    );
  }
}

// === Ошибка загрузки ===
class _ProfileErrorCard extends StatelessWidget {
  const _ProfileErrorCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 60),
      color: Colors.red[50],
      child: Column(
        children: [
          const Icon(Icons.error, color: Colors.red, size: 48),
          const SizedBox(height: 8),
          const Text(
            'Не удалось загрузить профиль',
            style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Повторяем...')),
              );
            },
            child: const Text('Повторить'),
          ),
        ],
      ),
    );
  }
}

// === Пункт меню ===
class _SettingsItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color? color;
  final String? route;
  final VoidCallback? onTap;

  const _SettingsItem({
    required this.icon,
    required this.title,
    this.color,
    this.route,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: color ?? Colors.grey[700]),
      title: Text(title, style: TextStyle(color: color ?? Colors.black87)),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: onTap ??
          (route != null
              ? () {
                  Navigator.pushNamed(context, route!);
                }
              : null),
    );
  }
}
