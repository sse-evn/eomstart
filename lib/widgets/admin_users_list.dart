// lib/widgets/admin_users_list.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:micro_mobility_app/services/api_service.dart';
import 'package:micro_mobility_app/config.dart';

class AdminUsersList extends StatefulWidget {
  const AdminUsersList({super.key});

  @override
  State<AdminUsersList> createState() => _AdminUsersListState();
}

class _AdminUsersListState extends State<AdminUsersList> {
  final ApiService _apiService = ApiService();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  late Future<List<dynamic>> _usersFuture;
  String _currentUserRole = '';
  String _currentUsername = '';
  String _currentUserFirstName = '';
  String _currentUserRoleLabel = '';
  List<String> _auditLog = [];

  final Map<String, String> _roleLabels = {
    'scout': 'Скаут',
    'supervisor': 'Супервайзер',
    'coordinator': 'Координатор',
    'superadmin': 'Суперадмин',
  };

  final Map<String, Color> _statusColors = {
    'active': Colors.green,
    'pending': Colors.orange,
    'deleted': Colors.grey,
  };

  String _selectedRoleFilter = 'all';
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _usersFuture = _fetchUsers();
    _loadProfile();
    _loadAuditLog();
  }

  Future<void> _loadProfile() async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token == null) return;

      final profile = await _apiService.getUserProfile(token);
      final role = (profile['role'] ?? 'user').toString().toLowerCase();
      final username = profile['username'] as String? ?? 'User';
      final firstName = profile['first_name'] as String? ?? 'Не указано';

      if (mounted) {
        setState(() {
          _currentUserRole = role;
          _currentUsername = username;
          _currentUserFirstName = firstName;
          _currentUserRoleLabel = _roleLabels[role] ?? role;
        });
      }
    } catch (e) {
      debugPrint('Ошибка загрузки профиля: $e');
    }
  }

  Future<List<dynamic>> _fetchUsers() async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token == null) throw Exception('Токен не найден');

      final users = await _apiService.getAdminUsers(token);
      return users;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки: ${e.toString()}')),
        );
      }
      return [];
    }
  }

  Future<void> _loadAuditLog() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('admin_audit_log') ?? [];
    if (mounted) {
      setState(() {
        _auditLog.clear();
        _auditLog.addAll(saved.reversed.toList());
      });
    }
  }

  Future<void> _saveAuditLog() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('admin_audit_log', _auditLog.reversed.toList());
  }

  void _addLog(String action) {
    final entry = '${DateTime.now().formatTime()} — $action';
    _auditLog.insert(0, entry);
    _saveAuditLog();
  }

  Future<void> _updateUserRole(
      int userId, String newRole, String username) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Изменить роль?',
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text('Назначить "$username" роль "${_roleLabels[newRole]}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Да, назначить'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token == null) throw Exception('Токен не найден');

      await _apiService.updateUserRole(token, userId, newRole);
      _addLog('🔄 $username → ${_roleLabels[newRole]}');

      if (mounted) {
        setState(() => _usersFuture = _fetchUsers());
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Роль обновлена'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _activateUser(int userId, String username) async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token == null) throw Exception('Токен не найден');

      await _apiService.activateUser(token, userId);
      _addLog('✅ Активирован: $username');

      if (mounted) {
        setState(() => _usersFuture = _fetchUsers());
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Доступ активирован'),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deactivateUser(int userId, String username) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Отправить в ожидание?',
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text('Пользователь "$username" потеряет доступ к приложению.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Да, отправить'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token == null) throw Exception('Токен не найден');

      await _apiService.deactivateUser(token, userId);
      _addLog('⏸️ Отправлен в ожидание: $username');

      if (mounted) {
        setState(() => _usersFuture = _fetchUsers());
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Доступ отозван'), backgroundColor: Colors.orange),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteUser(int userId, String username) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Удалить пользователя?',
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text(
            'Вы уверены, что хотите удалить "$username"? Это действие нельзя отменить.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token == null) throw Exception('Токен не найден');

      await _apiService.deleteUser(token, userId);
      _addLog('❌ Удалён: $username');

      if (mounted) {
        setState(() => _usersFuture = _fetchUsers());
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Пользователь удалён'),
              backgroundColor: Colors.orange),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _createUser() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    if (username.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Введите логин')));
      return;
    }
    if (password.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Введите пароль')));
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Добавить пользователя',
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Логин: $username'),
            const SizedBox(height: 4),
            Text('Пароль: ${'*' * password.length}'),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Добавить'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token == null) throw Exception('Токен не найден');

      await _apiService.createUser(token, username, password);
      _addLog('✅ Добавлен: $username');

      if (mounted) {
        Navigator.pop(context);
        setState(() => _usersFuture = _fetchUsers());
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Пользователь добавлен'),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      String message = 'Ошибка: $e';
      if (e.toString().contains('duplicate'))
        message = 'Пользователь с таким логином уже существует.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _refreshData() async {
    if (mounted) {
      setState(() => _usersFuture = _fetchUsers());
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // === Профиль администратора ===
          Card(
            elevation: 4,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 36,
                    backgroundColor: Colors.green[700],
                    child: Icon(Icons.person, size: 36, color: Colors.white),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _currentUsername,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '$_currentUserFirstName • $_currentUserRoleLabel',
                          style: const TextStyle(color: Colors.grey),
                        ),
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green[100],
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Вы: $_currentUserRoleLabel',
                            style: TextStyle(
                                fontSize: 12, color: Colors.green[800]),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // === Поиск и фильтры ===
          Card(
            elevation: 4,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Поиск по логину или имени...',
                      prefixIcon: const Icon(Icons.search, color: Colors.grey),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.grey[100],
                    ),
                    onChanged: (value) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _selectedRoleFilter,
                    items: [
                      const DropdownMenuItem(
                          value: 'all', child: Text('Все роли')),
                      ..._roleLabels.entries.map((e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value),
                          )),
                    ],
                    onChanged: (value) =>
                        setState(() => _selectedRoleFilter = value!),
                    decoration: InputDecoration(
                      labelText: 'Фильтр по ролям',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.grey[100],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_currentUserRole == 'superadmin')
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _showCreateUserDialog,
                        icon: const Icon(Icons.person_add, size: 18),
                        label: const Text('Добавить пользователя'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green[700],
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // === Журнал действий ===
          if (_auditLog.isNotEmpty)
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: ExpansionTile(
                title: const Text('Журнал действий',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                children: _auditLog
                    .take(10)
                    .map((log) => ListTile(
                          leading: const Icon(Icons.history,
                              size: 16, color: Colors.grey),
                          title: Text(log,
                              style: const TextStyle(
                                  fontSize: 12, fontFamily: 'monospace')),
                        ))
                    .toList(),
              ),
            ),

          const SizedBox(height: 24),

          // === Список пользователей ===
          RefreshIndicator(
            onRefresh: _refreshData,
            child: FutureBuilder<List<dynamic>>(
              future: _usersFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                } else if (!snapshot.hasData || snapshot.hasError) {
                  return Center(
                      child: Text('Ошибка: ${snapshot.error ?? 'Нет данных'}'));
                }

                final query = _searchController.text.toLowerCase();
                final filteredUsers = snapshot.data!.where((user) {
                  final role = (user['role']?.toString().toLowerCase() ?? '');
                  final name = ((user['firstName'] ?? user['first_name'] ?? '')
                          as String)
                      .toLowerCase();
                  final username = (user['username'] as String).toLowerCase();
                  final matchesSearch = query.isEmpty ||
                      name.contains(query) ||
                      username.contains(query);
                  final matchesRole = _selectedRoleFilter == 'all' ||
                      role == _selectedRoleFilter;
                  return matchesSearch && matchesRole;
                }).toList();

                if (filteredUsers.isEmpty) {
                  return const Center(child: Text('Пользователи не найдены'));
                }

                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: filteredUsers.length,
                  itemBuilder: (context, index) {
                    final user = filteredUsers[index];
                    final userId = user['id'];
                    final username = user['username'] as String;
                    final firstName =
                        user['firstName'] ?? user['first_name'] ?? 'Без имени';
                    final role =
                        (user['role']?.toString().toLowerCase() ?? 'unknown');
                    final status =
                        (user['status']?.toString().toLowerCase() ?? 'pending');
                    final displayRole = _roleLabels[role] ?? role;
                    final statusColor = _statusColors[status] ?? Colors.grey;

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 3,
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: statusColor,
                          child: Text('$userId',
                              style: const TextStyle(color: Colors.white)),
                        ),
                        title: Text(username,
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('$firstName • $displayRole'),
                            Text(
                              status == 'active'
                                  ? 'Активен'
                                  : status == 'pending'
                                      ? 'Ожидание'
                                      : 'Удалён',
                              style:
                                  TextStyle(color: statusColor, fontSize: 12),
                            ),
                          ],
                        ),
                        trailing: PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert),
                          itemBuilder: (ctx) {
                            return [
                              ..._roleLabels.entries.map((e) => PopupMenuItem(
                                    value: 'role:${e.key}',
                                    child: Text('Назначить: ${e.value}'),
                                  )),
                              if (_currentUserRole == 'superadmin') ...[
                                const PopupMenuDivider(),
                                if (status == 'pending')
                                  const PopupMenuItem(
                                      value: 'activate',
                                      child: Text('Активировать')),
                                if (status == 'active')
                                  const PopupMenuItem(
                                    value: 'deactivate',
                                    child: Text('Отправить в ожидание',
                                        style: TextStyle(color: Colors.orange)),
                                  ),
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Удалить',
                                      style: TextStyle(color: Colors.red)),
                                ),
                              ]
                            ];
                          },
                          onSelected: (action) {
                            if (action.startsWith('role:')) {
                              final newRole = action.replaceFirst('role:', '');
                              _updateUserRole(userId, newRole, username);
                            } else if (action == 'activate') {
                              _activateUser(userId, username);
                            } else if (action == 'deactivate') {
                              _deactivateUser(userId, username);
                            } else if (action == 'delete') {
                              _deleteUser(userId, username);
                            }
                          },
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showCreateUserDialog() {
    _usernameController.clear();
    _passwordController.clear();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Добавить пользователя',
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(
                hintText: 'Логин',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(
                hintText: 'Пароль',
                prefixIcon: Icon(Icons.lock_outline),
              ),
              obscureText: true,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          ElevatedButton(
            onPressed: _createUser,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Добавить'),
          ),
        ],
      ),
    );
  }
}

extension TimeFormat on DateTime {
  String formatTime() {
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }
}
