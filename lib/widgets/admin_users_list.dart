// /home/evn/eomstart/lib/screens/admin_users_list.dart
// ИЛИ /home/evn/eomstart/lib/widgets/admin_users_list.dart - проверьте путь
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart'; // Для _auditLog
import '../services/api_service.dart';
import '../config/config.dart';

class AdminUsersList extends StatefulWidget {
  const AdminUsersList({Key? key}) : super(key: key);

  @override
  State<AdminUsersList> createState() => _AdminUsersListState();
}

class _AdminUsersListState extends State<AdminUsersList> {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final ApiService _apiService = ApiService();

  // Инициализируем _usersFuture сразу при объявлении
  late Future<List<Map<String, dynamic>>> _usersFuture = Future.value([]);
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
    'admin': 'Админ',
    'superadmin': 'Суперадмин',
  };

  final Map<String, Color> _roleColors = {
    'user': Colors.grey,
    'scout': Colors.blue,
    'supervisor': Colors.orange,
    'coordinator': Colors.purple,
    'admin': Colors.red,
    'superadmin': Colors.redAccent,
  };

  final Map<String, Color> _statusColors = {
    'active': Colors.green,
    'pending': Colors.orange,
  };

  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  String _searchQuery = '';
  String _filterRole = 'all';
  bool _showInactive = true;

  @override
  void initState() {
    super.initState();
    _loadCurrentUserAndData();
    _loadAuditLog();
  }

  Future<void> _loadCurrentUserAndData() async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token != null) {
        final profile = await _apiService.getUserProfile(token);
        setState(() {
          _currentUserId = profile['id']?.toString();
          _currentUserRole = profile['role'] as String?;
          _currentUserFirstName = profile['first_name'] as String? ??
              profile['username'] as String?;
          _currentUserRoleLabel =
              _roleLabels[_currentUserRole ?? ''] ?? 'Пользователь';
        });
      }
    } catch (e) {
      debugPrint('Ошибка загрузки профиля: $e');
    } finally {
      // Гарантируем инициализацию _usersFuture после попытки загрузки профиля
      _refreshData();
    }
  }

  Future<List<Map<String, dynamic>>> _fetchUsers() async {
    final token = await _storage.read(key: 'jwt_token');
    if (token == null) throw Exception('Токен не найден');

    final users = await _apiService.getAdminUsers(token);
    return List<Map<String, dynamic>>.from(users);
  }

  Future<void> _refreshData() async {
    if (!mounted) return;
    debugPrint('Refreshing user data...');

    // 1. Создаем новый Future
    final newFuture = _fetchUsers();

    // 2. Обновляем ссылку на Future в состоянии, вызывая перерисовку FutureBuilder
    setState(() {
      _usersFuture = newFuture;
    });

    // 3. Дожидаемся завершения Future (опционально, но надежнее)
    try {
      await newFuture;
      debugPrint('Refresh complete and data loaded.');
    } catch (e) {
      debugPrint('Refresh completed, but data loading failed: $e');
      // Ошибка будет обработана FutureBuilder'ом
    }
  }

  // --- Методы для работы с Audit Log ---
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
    // Используем стандартный формат даты вместо несуществующего formatLogTime()
    final now = DateTime.now()
        .toString()
        .split('.')[0]; // Убираем миллисекунды для краткости
    final entry = '[$now] $action';
    setState(() {
      _auditLog.insert(0, entry);
    });
    _saveAuditLog();
  }
  // --- Конец методов для работы с Audit Log ---

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

  void _toggleInactiveFilter(bool? value) {
    if (value != null) {
      setState(() {
        _showInactive = value;
      });
    }
  }

  List<Map<String, dynamic>> _applyFilters(List<Map<String, dynamic>> users) {
    List<Map<String, dynamic>> filtered = List.from(users);

    // Фильтр по поиску
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((user) {
        final username = (user['username'] as String?)?.toLowerCase() ?? '';
        final firstName = (user['first_name'] as String?)?.toLowerCase() ?? '';
        return username.contains(_searchQuery) ||
            firstName.contains(_searchQuery);
      }).toList();
    }

    // Фильтр по роли
    if (_filterRole != 'all') {
      filtered = filtered.where((user) => user['role'] == _filterRole).toList();
    }

    // Фильтр по активности
    if (!_showInactive) {
      filtered = filtered.where((user) => user['is_active'] == 1).toList();
    }

    return filtered;
  }

  Future<void> _activateUser(int userId, String username) async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token == null) throw Exception('Токен не найден');

      // 1. Отправляем запрос на сервер
      await _apiService.updateUserStatus(token, userId, 'active');

      // 2. Логируем действие
      _addLog('✅ Активирован: $username');

      if (mounted) {
        // 3. Обновляем основной список пользователей (обязательно!)
        // Добавляем небольшую задержку, чтобы сервер успел обработать запрос
        await Future.delayed(const Duration(milliseconds: 100));
        await _refreshData(); // Это должно привести к пересозданию Future и обновлению FutureBuilder

        // 4. Показываем уведомление
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Доступ активирован'),
                backgroundColor: Colors.green),
          );
        }
      }
    } catch (e) {
      // Логируем ошибку
      debugPrint('Ошибка при активации пользователя $userId: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deactivateUser(int userId, String username) async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token == null) throw Exception('Токен не найден');

      // 1. Отправляем запрос на сервер
      await _apiService.updateUserStatus(token, userId, 'pending');

      // 2. Логируем действие
      _addLog('❌ Отозван: $username');

      if (mounted) {
        // 3. Обновляем основной список пользователей (обязательно!)
        // Добавляем небольшую задержку, чтобы сервер успел обработать запрос
        await Future.delayed(const Duration(milliseconds: 100));
        await _refreshData(); // Это должно привести к пересозданию Future и обновлению FutureBuilder

        // 4. Показываем уведомление
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Доступ отозван'),
                backgroundColor: Colors.orange),
          );
        }
      }
    } catch (e) {
      // Логируем ошибку
      debugPrint('Ошибка при деактивации пользователя $userId: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // --- Добавлен недостающий метод _changeUserRole ---
  Future<void> _changeUserRole(
      int userId, String username, String currentRole) async {
    final newRole = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Изменить роль',
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: _roleLabels.entries
              .map((entry) {
                // Не позволяем пользователю выбирать роль, которую он уже имеет
                if (entry.key == currentRole) return const SizedBox.shrink();
                return RadioListTile<String>(
                  title: Text(entry.value),
                  value: entry.key,
                  groupValue: currentRole,
                  onChanged: (value) => Navigator.pop(ctx, value),
                );
              })
              .where((widget) => widget is RadioListTile<String>)
              .toList(),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
        ],
      ),
    );

    if (newRole != null && newRole != currentRole) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Подтвердить изменение?',
              style: TextStyle(fontWeight: FontWeight.bold)),
          content: Text(
              'Изменить роль "$username" с "${_roleLabels[currentRole]}" на "${_roleLabels[newRole]}"?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Отмена')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              child: const Text('Изменить'),
            ),
          ],
        ),
      );

      if (confirmed == true) {
        try {
          final token = await _storage.read(key: 'jwt_token');
          if (token == null) throw Exception('Токен не найден');

          await _apiService.updateUserRole(token, userId, newRole);
          _addLog('🔄 $username → ${_roleLabels[newRole]}');

          if (mounted) {
            await _refreshData(); // Ждем обновления данных
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Роль обновлена'),
                    backgroundColor: Colors.green),
              );
            }
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text('Ошибка: $e'), backgroundColor: Colors.red),
            );
          }
        }
      }
    }
  }
  // --- Конец _changeUserRole ---

  // --- Добавлен недостающий метод _deleteUser ---
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

    if (confirmed == true) {
      try {
        final token = await _storage.read(key: 'jwt_token');
        if (token == null) throw Exception('Токен не найден');

        await _apiService.deleteUser(token, userId);
        _addLog('🗑️ Удален: $username');

        if (mounted) {
          await _refreshData();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Пользователь удален'),
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
      }
    }
  }
  // --- Конец _deleteUser ---

  // --- Добавлен недостающий метод _showCreateUserDialog ---
  void _showCreateUserDialog() {
    _usernameController.clear();
    _passwordController.clear();
    _firstNameController.clear();

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
                hintText: 'Логин *',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _firstNameController,
              decoration: const InputDecoration(
                hintText: 'Имя',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(
                hintText: 'Пароль *',
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
            onPressed: () async {
              final username = _usernameController.text.trim();
              final password = _passwordController.text;
              final firstName = _firstNameController.text.trim().isNotEmpty
                  ? _firstNameController.text.trim()
                  : null;

              if (username.isEmpty || password.isEmpty) {
                if (mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Логин и пароль обязательны')),
                  );
                }
                return;
              }

              Navigator.pop(ctx);
              try {
                final token = await _storage.read(key: 'jwt_token');
                if (token == null) throw Exception('Токен не найден');

                await _apiService.createUser(token, username, password,
                    firstName: firstName);
                _addLog('🆕 Создан: $username');

                if (mounted) {
                  await _refreshData();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Пользователь создан'),
                          backgroundColor: Colors.green),
                    );
                  }
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text('Ошибка: $e'),
                        backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('Создать'),
          ),
        ],
      ),
    );
  }
  // --- Конец _showCreateUserDialog ---

  void _showUserProfile(Map<String, dynamic> user) {
    // Безопасное извлечение данных с проверкой на null
    final username = user['username'] as String? ?? 'Неизвестный';
    final firstName = user['first_name'] as String?;
    final role = user['role'] as String? ?? 'unknown';
    final status = user['status'] as String? ?? 'pending';
    final isActive = user['is_active'] == 1;
    final createdAtStr = user['created_at'] as String?; // Может быть null
    final userId = user['id'] as int?; // Может быть null

    // Проверка на null для обязательных полей
    if (userId == null) {
      debugPrint('Ошибка: ID пользователя не найден');
      return;
    }

    final roleLabel = _roleLabels[role] ?? 'Неизвестно';
    final roleColor = _roleColors[role] ?? Colors.grey;
    final statusColor = _statusColors[status] ?? Colors.grey;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // Для лучшего отображения на маленьких экранах
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          return Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom, // Клавиатура
                left: 16,
                right: 16,
                top: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Заголовок
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            username,
                            style: const TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          if (firstName != null && firstName.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              firstName,
                              style: const TextStyle(
                                  fontSize: 16, color: Colors.grey),
                            ),
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '${_currentUserFirstName ?? 'Загрузка...'} • ${_currentUserRoleLabel}',
                  style: const TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.green[100],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Вы: $_currentUserRoleLabel',
                    style: TextStyle(fontSize: 12, color: Colors.green[800]),
                  ),
                ),
                const SizedBox(height: 20),

                // Статус и роль
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: roleColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        roleLabel,
                        style: TextStyle(
                            color: roleColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: statusColor, width: 1),
                      ),
                      child: Text(
                        status == 'active' ? 'Активен' : 'Ожидание',
                        style: TextStyle(color: statusColor, fontSize: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Кнопки действий
                if (_currentUserRole == 'admin' ||
                    _currentUserRole == 'superadmin') ...[
                  if (status != 'active')
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          Navigator.pop(ctx); // Закрываем BottomSheet
                          await _activateUser(userId, username);
                          // setState для локального user НЕ НУЖЕН, так как _activateUser вызывает _refreshData()
                        },
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('Активировать'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  if (status == 'active')
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          Navigator.pop(ctx); // Закрываем BottomSheet
                          await _deactivateUser(userId, username);
                          // setState для локального user НЕ НУЖЕН, так как _deactivateUser вызывает _refreshData()
                        },
                        icon: const Icon(Icons.block, size: 18),
                        label: const Text('Отправить в ожидание'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _changeUserRole(userId, username, role),
                      icon: const Icon(Icons.admin_panel_settings, size: 18),
                      label: const Text('Изменить роль'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_currentUserRole == 'superadmin' &&
                      _currentUserId != userId.toString())
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _deleteUser(userId, username),
                        icon: const Icon(Icons.delete, size: 18),
                        label: const Text('Удалить пользователя'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                        ),
                      ),
                    ),
                ],
                const SizedBox(height: 16),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Пользователи'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshData,
            tooltip: 'Обновить список',
          ),
          if (_currentUserRole == 'admin' || _currentUserRole == 'superadmin')
            IconButton(
              icon: const Icon(Icons.person_add),
              onPressed: _showCreateUserDialog,
              tooltip: 'Добавить пользователя',
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshData,
        child: CustomScrollView(
          slivers: [
            // Шапка с информацией о текущем пользователе
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Текущий профиль',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _currentUserFirstName ?? 'Загрузка...',
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_currentUserFirstName ?? 'Пользователь'} • $_currentUserRoleLabel',
                          style: const TextStyle(color: Colors.grey),
                        ),
                        const SizedBox(height: 4),
                        Container(
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
                ),
              ),
            ),

            // Поиск и фильтры
            SliverToBoxAdapter(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Card(
                  elevation: 3,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        TextField(
                          controller: _searchController,
                          onChanged: _filterUsers,
                          decoration: const InputDecoration(
                            hintText: 'Поиск по имени или логину...',
                            prefixIcon: Icon(Icons.search),
                            border: InputBorder.none,
                          ),
                        ),
                        const Divider(),
                        Row(
                          children: [
                            const Text('Роль:'),
                            const SizedBox(width: 8),
                            DropdownButton<String>(
                              value: _filterRole,
                              items: [
                                const DropdownMenuItem(
                                    value: 'all', child: Text('Все')),
                                ..._roleLabels.entries
                                    .map((entry) => DropdownMenuItem(
                                          value: entry.key,
                                          child: Text(entry.value),
                                        )),
                              ],
                              onChanged: _changeRoleFilter,
                            ),
                            const Spacer(),
                            const Text('Активные:'),
                            const SizedBox(width: 8),
                            Switch(
                              value: _showInactive,
                              onChanged: _toggleInactiveFilter,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Журнал действий
            SliverToBoxAdapter(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Card(
                  elevation: 3,
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
              ),
            ),

            // Список пользователей
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: _usersFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    } else if (snapshot.hasError) {
                      return Center(child: Text('Ошибка: ${snapshot.error}'));
                    } else if (snapshot.hasData) {
                      final filteredUsers = _applyFilters(snapshot.data!);
                      if (filteredUsers.isEmpty) {
                        return const Center(
                            child: Text('Пользователи не найдены'));
                      }

                      return ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: filteredUsers.length,
                        itemBuilder: (context, index) {
                          final user = filteredUsers[index];
                          // Безопасное извлечение данных с проверкой на null
                          final username =
                              user['username'] as String? ?? 'Неизвестный';
                          final firstName = user['first_name'] as String?;
                          final role = user['role'] as String? ?? 'unknown';
                          final status = user['status'] as String? ?? 'pending';
                          final isActive = user['is_active'] == 1;
                          final userId = user['id'] as int?;

                          // Пропускаем пользователей без ID
                          if (userId == null) return const SizedBox.shrink();

                          final roleLabel = _roleLabels[role] ?? 'Неизвестно';
                          final roleColor = _roleColors[role] ?? Colors.grey;
                          final statusColor =
                              _statusColors[status] ?? Colors.grey;

                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            child: ListTile(
                              contentPadding: const EdgeInsets.all(12),
                              leading: CircleAvatar(
                                backgroundColor: roleColor.withOpacity(0.2),
                                child: Text(
                                  username.substring(0, 1).toUpperCase(),
                                  style: TextStyle(
                                      color: roleColor,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                              title: Text(
                                firstName ?? username,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w500),
                              ),
                              subtitle: Text(
                                username,
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.grey),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: roleColor.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      roleLabel,
                                      style: TextStyle(
                                          color: roleColor, fontSize: 10),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: statusColor.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                          color: statusColor, width: 1),
                                    ),
                                    child: Text(
                                      status == 'active'
                                          ? 'Активен'
                                          : 'Ожидание',
                                      style: TextStyle(
                                          color: statusColor, fontSize: 10),
                                    ),
                                  ),
                                  const Icon(Icons.arrow_forward_ios, size: 16),
                                ],
                              ),
                              onTap: () => _showUserProfile(user),
                            ),
                          );
                        },
                      );
                    } else {
                      return const Center(child: Text('Нет данных'));
                    }
                  },
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 16)),
          ],
        ),
      ),
      floatingActionButton:
          (_currentUserRole == 'admin' || _currentUserRole == 'superadmin')
              ? FloatingActionButton(
                  onPressed: _showCreateUserDialog,
                  child: const Icon(Icons.add),
                  tooltip: 'Добавить пользователя',
                )
              : null,
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
