// lib/widgets/admin_users_list.dart
import 'package:flutter/material.dart';
import 'package:micro_mobility_app/services/api_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  List<String> _auditLog = [];

  final Map<String, String> _roleLabels = {
    'scout': 'Скаут',
    'supervisor': 'Супервайзер',
    'coordinator': 'Координатор',
    'superadmin': 'Суперадмин',
  };

  String _selectedRoleFilter = 'all';
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _firstNameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _usersFuture = _fetchUsers();
    _initData();
    _loadAuditLog();
  }

  Future<void> _initData() async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token == null) return;

      final profile = await _apiService.getUserProfile(token);
      final role = (profile['role'] ?? 'user').toString().toLowerCase();

      if (mounted) {
        setState(() {
          _currentUserRole = role;
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
      debugPrint('✅ getAdminUsers response: $users');
      return users;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
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
    // ... (остаётся как было)
  }

  Future<void> _activateUser(int userId, String username) async {
    // ... (как было)
  }

  Future<void> _deactivateUser(int userId, String username) async {
    // ... (как было)
  }

  Future<void> _deleteUser(int userId, String username) async {
    // ... (как было)
  }

  Future<void> _createUser() async {
    // ... (как было)
  }

  Future<void> _refreshData() async {
    if (mounted) {
      setState(() {
        _usersFuture = _fetchUsers();
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _usernameController.dispose();
    _firstNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: Theme.of(context).cardColor,
          child: Column(
            children: [
              TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  hintText: 'Поиск по логину или имени...',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) => setState(() {}),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _selectedRoleFilter,
                items: [
                  const DropdownMenuItem(value: 'all', child: Text('Все роли')),
                  ..._roleLabels.keys.map((role) => DropdownMenuItem(
                        value: role,
                        child: Text(_roleLabels[role]!),
                      )),
                ],
                onChanged: (value) {
                  setState(() {
                    _selectedRoleFilter = value!;
                  });
                },
                decoration: const InputDecoration(
                  labelText: 'Фильтр по ролям',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              if (_currentUserRole == 'superadmin')
                ElevatedButton.icon(
                  onPressed: _showCreateUserDialog,
                  icon: const Icon(Icons.person_add),
                  label: const Text('Добавить пользователя'),
                  style:
                      ElevatedButton.styleFrom(backgroundColor: Colors.green),
                ),
            ],
          ),
        ),
        if (_auditLog.isNotEmpty)
          Card(
            margin: const EdgeInsets.all(16),
            child: ExpansionTile(
              title: const Text('Журнал',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              children: _auditLog
                  .take(10)
                  .map((log) => ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        leading: const Icon(Icons.history,
                            size: 16, color: Colors.grey),
                        title: Text(log,
                            style: const TextStyle(
                                fontSize: 12, fontFamily: 'monospace')),
                      ))
                  .toList(),
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refreshData,
            child: FutureBuilder<List<dynamic>>(
              future: _usersFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                } else if (snapshot.hasError || !snapshot.hasData) {
                  return Center(child: Text('Ошибка: ${snapshot.error}'));
                }

                final allUsers = snapshot.data!;
                final query = _searchController.text.toLowerCase();

                final filteredUsers = allUsers.where((user) {
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

                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 6),
                      child: ListTile(
                        leading: CircleAvatar(child: Text('$userId')),
                        title: Text(username,
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('$firstName • $displayRole • $status'),
                        trailing: PopupMenuButton<String>(
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
                          itemBuilder: (ctx) {
                            final items = <PopupMenuEntry<String>>[];
                            for (final role in _roleLabels.keys) {
                              items.add(PopupMenuItem(
                                  value: 'role:$role',
                                  child:
                                      Text('Назначить: ${_roleLabels[role]}')));
                            }
                            if (_currentUserRole == 'superadmin') {
                              items.add(const PopupMenuDivider());
                              if (status == 'active') {
                                items.add(const PopupMenuItem(
                                    value: 'deactivate',
                                    child: Text('Отправить в ожидание',
                                        style:
                                            TextStyle(color: Colors.orange))));
                              } else if (status == 'pending') {
                                items.add(const PopupMenuItem(
                                    value: 'activate',
                                    child: Text('Активировать доступ')));
                              }
                              items.add(const PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Удалить',
                                      style: TextStyle(color: Colors.red))));
                            }
                            return items;
                          },
                          icon: const Icon(Icons.more_vert),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  void _showCreateUserDialog() {
    _usernameController.clear();
    _firstNameController.clear();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Добавить пользователя'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: _usernameController,
                decoration:
                    const InputDecoration(hintText: 'Логин (обязательно)')),
            const SizedBox(height: 8),
            TextField(
                controller: _firstNameController,
                decoration:
                    const InputDecoration(hintText: 'Имя (необязательно)')),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          TextButton(onPressed: _createUser, child: const Text('Добавить')),
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
