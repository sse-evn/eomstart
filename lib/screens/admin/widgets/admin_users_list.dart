import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../services/api_service.dart';
import '../../../config/config.dart';

class AdminUsersList extends StatefulWidget {
  const AdminUsersList({Key? key}) : super(key: key);

  @override
  State<AdminUsersList> createState() => _AdminUsersListState();
}

class _AdminUsersListState extends State<AdminUsersList> {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final ApiService _apiService = ApiService();
  late Future<List<Map<String, dynamic>>> _usersFuture;
  List<String> _auditLog = [];
  String? _currentUserId;
  String? _currentUserRole;
  String? _currentUserFirstName;
  String _currentUserRoleLabel = 'Пользователь';

  final Map<String, String> _roleLabels = {
    'user': 'Пользователь',
    'scout': 'Скаут',
    'supervisor': 'Супервайзер',
    'coordinator': 'Координатор',
    // 'admin': 'Админ',
    'superadmin': 'Суперадмин',
  };

  final Map<String, Color> _roleColors = {
    'user': Colors.grey,
    'scout': Colors.blue,
    'supervisor': Colors.orange,
    'coordinator': Colors.purple,
    // 'admin': Colors.red,
    'superadmin': Colors.red,
  };

  final Map<String, Color> _statusColors = {
    'active': Colors.green,
    'pending': Colors.orange,
    'inactive': Colors.grey,
  };

  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  String _searchQuery = '';
  String _filterRole = 'all';
  String _filterStatus = 'all';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _usersFuture = _fetchUsers();
    _loadCurrentUserAndData();
    _loadAuditLog();
  }

  Future<void> _loadCurrentUserAndData() async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token != null) {
        final profile = await _apiService.getUserProfile(token);
        if (mounted) {
          // ← ДОБАВЛЕНО: безопасная проверка
          setState(() {
            _currentUserId = profile['id']?.toString();
            _currentUserRole = profile['role'] as String?;
            _currentUserFirstName = profile['first_name'] as String? ??
                profile['username'] as String?;
            _currentUserRoleLabel =
                _roleLabels[_currentUserRole ?? ''] ?? 'Пользователь';
          });
        }
      }
    } catch (e) {
      debugPrint('Ошибка загрузки профиля: $e');
      // Даже в catch — если нужно обновить UI, проверяйте mounted
    }
  }

  Future<List<Map<String, dynamic>>> _fetchUsers() async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token == null) throw Exception('Токен не найден');

      final users = await _apiService.getAdminUsers(token);
      return List<Map<String, dynamic>>.from(users);
    } catch (e) {
      debugPrint('Ошибка загрузки пользователей: $e');
      rethrow;
    }
  }

  Future<void> _refreshData() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final newFuture = _fetchUsers();
      setState(() {
        _usersFuture = newFuture;
      });
      await newFuture;
    } catch (e) {
      debugPrint('Ошибка обновления: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadAuditLog() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('admin_audit_log') ?? [];
    if (mounted) {
      setState(() {
        _auditLog = saved.reversed.toList();
      });
    }
  }

  Future<void> _saveAuditLog() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('admin_audit_log', _auditLog.reversed.toList());
  }

  void _addLog(String action) {
    final now = DateTime.now().toString().split('.')[0];
    final entry = '[$now] $action';
    setState(() {
      _auditLog.insert(0, entry);
      if (_auditLog.length > 50) _auditLog = _auditLog.sublist(0, 50);
    });
    _saveAuditLog();
  }

  void _filterUsers(String query) {
    setState(() {
      _searchQuery = query.toLowerCase();
    });
  }

  void _changeRoleFilter(String? newRole) {
    if (newRole != null) {
      setState(() {
        _filterRole = newRole;
      });
    }
  }

  void _changeStatusFilter(String? newStatus) {
    if (newStatus != null) {
      setState(() {
        _filterStatus = newStatus;
      });
    }
  }

  List<Map<String, dynamic>> _applyFilters(List<Map<String, dynamic>> users) {
    return users.where((user) {
      if (_searchQuery.isNotEmpty) {
        final username = (user['username'] as String?)?.toLowerCase() ?? '';
        final firstName = (user['first_name'] as String?)?.toLowerCase() ?? '';
        if (!username.contains(_searchQuery) &&
            !firstName.contains(_searchQuery)) {
          return false;
        }
      }

      if (_filterRole != 'all') {
        final role = user['role'] as String?;
        if (role != _filterRole) return false;
      }

      if (_filterStatus != 'all') {
        final status = user['status'] as String?;
        if (status != _filterStatus) return false;
      }

      return true;
    }).toList();
  }

  Future<void> _updateUserStatus(
      int userId, String username, String newStatus) async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token == null) throw Exception('Токен не найден');

      await _apiService.updateUserStatus(token, userId, newStatus);

      _addLog(newStatus == 'active'
          ? '✅ Активирован: $username'
          : '❌ Деактивирован: $username');

      await _refreshData();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(newStatus == 'active'
                  ? 'Пользователь активирован'
                  : 'Пользователь деактивирован'),
              backgroundColor:
                  newStatus == 'active' ? Colors.green : Colors.orange,
            ),
          );
        }
      });
    } catch (e) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Ошибка: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      });
    }
  }

  Future<void> _changeUserRole(
      int userId, String username, String currentRole) async {
    final newRole = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Изменить роль'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _roleLabels.length,
            itemBuilder: (context, index) {
              final entry = _roleLabels.entries.elementAt(index);
              return RadioListTile<String>(
                title: Text(entry.value),
                value: entry.key,
                groupValue: currentRole,
                onChanged: (value) => Navigator.pop(ctx, value),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, currentRole),
            child: const Text('Изменить'),
          ),
        ],
      ),
    );

    if (newRole != null && newRole != currentRole) {
      try {
        final token = await _storage.read(key: 'jwt_token');
        if (token == null) throw Exception('Токен не найден');

        await _apiService.updateUserRole(token, userId, newRole);
        _addLog('🔄 $username → ${_roleLabels[newRole]}');

        await _refreshData();

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Роль обновлена'),
                backgroundColor: Colors.green,
              ),
            );
          }
        });
      } catch (e) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Ошибка: ${e.toString()}'),
                backgroundColor: Colors.red,
              ),
            );
          }
        });
      }
    }
  }

  Future<void> _deleteUser(int userId, String username) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить пользователя?'),
        content: Text('Вы уверены, что хотите удалить "$username"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final token = await _storage.read(key: 'jwt_token');
        if (token == null) throw Exception('Токен не найден');

        await _apiService.deleteUser(token, userId);
        _addLog('🗑️ Удален: $username');

        await _refreshData();

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Пользователь удален'),
                backgroundColor: Colors.red,
              ),
            );
          }
        });
      } catch (e) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Ошибка: ${e.toString()}'),
                backgroundColor: Colors.red,
              ),
            );
          }
        });
      }
    }
  }

  void _showCreateUserDialog() {
    _usernameController.clear();
    _passwordController.clear();
    _firstNameController.clear();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Добавить пользователя'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: 'Логин *',
                  prefixIcon: Icon(Icons.person),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _firstNameController,
                decoration: const InputDecoration(
                  labelText: 'Имя',
                  prefixIcon: Icon(Icons.badge),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                decoration: const InputDecoration(
                  labelText: 'Пароль *',
                  prefixIcon: Icon(Icons.lock),
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () async {
              final username = _usernameController.text.trim();
              final password = _passwordController.text.trim();
              final firstName = _firstNameController.text.trim();

              if (username.isEmpty || password.isEmpty) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(
                        content: Text('Заполните обязательные поля'),
                      ),
                    );
                  }
                });
                return;
              }

              Navigator.pop(ctx);

              try {
                final token = await _storage.read(key: 'jwt_token');
                if (token == null) throw Exception('Токен не найден');

                await _apiService.createUser(
                  token,
                  username,
                  password,
                  firstName: firstName.isNotEmpty ? firstName : null,
                );

                _addLog('🆕 Создан: $username');
                await _refreshData();

                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Пользователь создан'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                });
              } catch (e) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Ошибка: ${e.toString()}'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                });
              }
            },
            child: const Text('Создать'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Права: кто может управлять
    bool canManage = ['admin', 'superadmin', 'coordinator', 'supervisor']
        .contains(_currentUserRole);
    bool canDelete = _currentUserRole == 'superadmin';

    return Stack(
      children: [
        // Основной контент
        Column(
          children: [
            // Фильтры
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      TextField(
                        controller: _searchController,
                        onChanged: _filterUsers,
                        decoration: InputDecoration(
                          labelText: 'Поиск по логину или имени',
                          prefixIcon: const Icon(Icons.search),
                          border: const OutlineInputBorder(),
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 12,
                            horizontal: 16,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _filterRole,
                              items: [
                                const DropdownMenuItem(
                                  value: 'all',
                                  child: Text('Все роли'),
                                ),
                                ..._roleLabels.entries
                                    .map((e) => DropdownMenuItem(
                                          value: e.key,
                                          child: Text(e.value),
                                        )),
                              ],
                              onChanged: _changeRoleFilter,
                              decoration: const InputDecoration(
                                labelText: 'Роль',
                                border: OutlineInputBorder(),
                              ),
                              isExpanded: true,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _filterStatus,
                              items: const [
                                DropdownMenuItem(
                                  value: 'all',
                                  child: Text('Все статусы'),
                                ),
                                DropdownMenuItem(
                                  value: 'active',
                                  child: Text('Активные'),
                                ),
                                DropdownMenuItem(
                                  value: 'pending',
                                  child: Text('Ожидание'),
                                ),
                              ],
                              onChanged: _changeStatusFilter,
                              decoration: const InputDecoration(
                                labelText: 'Статус',
                                border: OutlineInputBorder(),
                              ),
                              isExpanded: true,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Список пользователей
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refreshData,
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: _usersFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (snapshot.hasError) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.error,
                                size: 48, color: Colors.red),
                            const SizedBox(height: 16),
                            Text('Ошибка: ${snapshot.error}'),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _refreshData,
                              child: const Text('Повторить'),
                            ),
                          ],
                        ),
                      );
                    }

                    if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return const Center(
                          child: Text('Пользователи не найдены'));
                    }

                    final filteredUsers = _applyFilters(snapshot.data!);

                    if (filteredUsers.isEmpty) {
                      return const Center(
                        child: Text('Нет пользователей по выбранным фильтрам'),
                      );
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: filteredUsers.length,
                      itemBuilder: (context, index) {
                        final user = filteredUsers[index];
                        final username =
                            user['username'] as String? ?? 'Неизвестно';
                        final firstName = user['first_name'] as String?;
                        final role = user['role'] as String? ?? 'user';
                        final status = user['status'] as String? ?? 'pending';
                        return Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 6,
                          ),
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: _roleColors[role],
                              child: Text(
                                username.substring(0, 1).toUpperCase(),
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                            title: Text(firstName ?? username),
                            subtitle: Text(
                              '@$username • ${_roleLabels[role] ?? role}',
                              style: const TextStyle(fontSize: 12),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Chip(
                                  label: Text(
                                    status == 'active' ? 'Активен' : 'Ожидание',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: _statusColors[status],
                                    ),
                                  ),
                                  backgroundColor:
                                      _statusColors[status]?.withOpacity(0.1),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    side: BorderSide(
                                      color:
                                          _statusColors[status] ?? Colors.grey,
                                      width: 0.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            onTap: () => _showUserActions(user),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        ),

        if (canManage)
          Positioned(
            bottom: 16,
            right: 16,
            child: FloatingActionButton(
              onPressed: _showCreateUserDialog,
              tooltip: 'Добавить пользователя',
              child: const Icon(Icons.person_add),
            ),
          ),
      ],
    );
  }

  void _showUserActions(Map<String, dynamic> user) {
    final username = user['username'] as String? ?? 'Неизвестно';
    final role = user['role'] as String? ?? 'user';
    final status = user['status'] as String? ?? 'pending';
    final userId = user['id'] as int?;

    if (userId == null) return;

    bool canManage = ['admin', 'superadmin', 'coordinator', 'supervisor']
        .contains(_currentUserRole);
    bool canDelete = _currentUserRole == 'superadmin';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(left: 20, right: 20, top: 10, bottom: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                username,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Роль: ${_roleLabels[role] ?? role}',
                textAlign: TextAlign.center,
                style: TextStyle(color: _roleColors[role]),
              ),
              Text(
                'Статус: ${status == 'active' ? 'Активен' : 'Ожидание'}',
                textAlign: TextAlign.center,
                style: TextStyle(color: _statusColors[status]),
              ),
              const SizedBox(height: 24),
              if (canManage)
                if (status != 'active')
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _updateUserStatus(userId, username, 'active');
                    },
                    child: const Text('Активировать'),
                  ),
              if (canManage)
                if (status == 'active')
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _updateUserStatus(userId, username, 'pending');
                    },
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange),
                    child: const Text('Деактивировать'),
                  ),
              const SizedBox(height: 10,),
              if (canManage)
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _changeUserRole(userId, username, role);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.secondary,
                  ),
                  child: const Text('Изменить роль'),
                ),
              const SizedBox(height: 10,),
              
              if (canDelete)
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _deleteUser(userId, username);
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  child: const Text('Удалить'),
                ),

            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _firstNameController.dispose();
    _searchController.dispose();
    super.dispose();
  }
}
