import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/services/api_service.dart';

class AdminUsersList extends StatefulWidget {
  const AdminUsersList({super.key});

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
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    bool canManage = ['admin', 'superadmin', 'coordinator', 'supervisor']
        .contains(_currentUserRole);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Column(
            children: [
              _buildModernHeader(isDarkMode),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _refreshData,
                  displacement: 20,
                  color: Colors.green,
                  child: FutureBuilder<List<Map<String, dynamic>>>(
                    future: _usersFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) return _buildErrorState(snapshot.error.toString());
                      if (!snapshot.hasData || snapshot.data!.isEmpty) return _buildEmptyState();

                      final filteredUsers = _applyFilters(snapshot.data!);
                      if (filteredUsers.isEmpty) return _buildNoResultsState();

                      return ListView.builder(
                        padding: const EdgeInsets.only(top: 8, bottom: 80),
                        physics: const BouncingScrollPhysics(),
                        itemCount: filteredUsers.length,
                        itemBuilder: (context, index) => _buildUserCard(filteredUsers[index], isDarkMode),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
          if (canManage) _buildFloatingActionButton(isDarkMode),
        ],
      ),
    );
  }

  Widget _buildModernHeader(bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF1A1A1A) : Colors.white,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDarkMode ? 0.3 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        children: [
          // Search Field
          Container(
            decoration: BoxDecoration(
              color: isDarkMode ? Colors.white.withOpacity(0.05) : Colors.grey[100],
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: isDarkMode ? Colors.white.withOpacity(0.1) : Colors.grey[300]!),
            ),
            child: TextField(
              controller: _searchController,
              onChanged: _filterUsers,
              decoration: InputDecoration(
                hintText: 'Поиск по логину или имени',
                hintStyle: TextStyle(color: Colors.grey[500], fontSize: 14),
                prefixIcon: Icon(Icons.search, color: Colors.green.withOpacity(0.7)),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Filter Row
          Row(
            children: [
              Expanded(child: _buildFilterDropdown('Роль', _filterRole, _roleLabels, _changeRoleFilter, isDarkMode)),
              const SizedBox(width: 12),
              Expanded(child: _buildFilterStatusDropdown(isDarkMode)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterDropdown(String label, String value, Map<String, String> items, Function(String?) onChanged, bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.white.withOpacity(0.03) : Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDarkMode ? Colors.white.withOpacity(0.08) : Colors.grey[200]!),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
          style: TextStyle(fontSize: 13, color: isDarkMode ? Colors.white : Colors.black, fontWeight: FontWeight.w500),
          items: [
            DropdownMenuItem(value: 'all', child: Text('Все ${label.toLowerCase()}и')),
            ...items.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildFilterStatusDropdown(bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.white.withOpacity(0.03) : Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDarkMode ? Colors.white.withOpacity(0.08) : Colors.grey[200]!),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _filterStatus,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
          style: TextStyle(fontSize: 13, color: isDarkMode ? Colors.white : Colors.black, fontWeight: FontWeight.w500),
          items: const [
            DropdownMenuItem(value: 'all', child: Text('Все статусы')),
            DropdownMenuItem(value: 'active', child: Text('Активные')),
            DropdownMenuItem(value: 'pending', child: Text('Ожидание')),
          ],
          onChanged: _changeStatusFilter,
        ),
      ),
    );
  }

  Widget _buildUserCard(Map<String, dynamic> user, bool isDarkMode) {
    final username = user['username'] as String? ?? 'Неизвестно';
    final firstName = user['first_name'] as String?;
    final role = user['role'] as String? ?? 'user';
    final status = user['status'] as String? ?? 'pending';
    final roleColor = _roleColors[role] ?? Colors.grey;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.white.withOpacity(0.05) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isDarkMode ? Colors.white.withOpacity(0.05) : Colors.grey[100]!),
        boxShadow: [
          if (!isDarkMode)
            BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showUserActions(user),
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // Avatar with role indicator
                Stack(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [roleColor, roleColor.withOpacity(0.6)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        username.substring(0, 1).toUpperCase(),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: status == 'active' ? Colors.green : Colors.orange,
                          shape: BoxShape.circle,
                          border: Border.all(color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white, width: 2),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 16),
                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(firstName ?? username, 
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: -0.2)),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text('@$username', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: roleColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(_roleLabels[role] ?? role, 
                              style: TextStyle(color: roleColor, fontSize: 10, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Status Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: (status == 'active' ? Colors.green : Colors.orange).withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    status == 'active' ? 'Активен' : 'Ожидание',
                    style: TextStyle(
                      color: status == 'active' ? Colors.green : Colors.orange,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingActionButton(bool isDarkMode) {
    return Positioned(
      bottom: 24,
      right: 24,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.green.withOpacity(0.4),
              blurRadius: 15,
              offset: const Offset(0, 6),
            )
          ],
        ),
        child: FloatingActionButton.extended(
          onPressed: _showCreateUserDialog,
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          icon: const Icon(Icons.person_add_rounded, size: 20),
          label: const Text('Пользователь', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.2)),
        ),
      ),
    );
  }

  Widget _buildErrorState(String error) => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.error_outline_rounded, size: 64, color: Colors.red),
        const SizedBox(height: 16),
        Text('Ошибка загрузки', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey[400])),
        const SizedBox(height: 8),
        Text(error, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
        const SizedBox(height: 24),
        ElevatedButton(onPressed: _refreshData, child: const Text('Повторить')),
      ],
    ),
  );

  Widget _buildEmptyState() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.people_outline_rounded, size: 64, color: Colors.grey[800]),
        const SizedBox(height: 16),
        const Text('Пользователи не найдены', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      ],
    ),
  );

  Widget _buildNoResultsState() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.search_off_rounded, size: 64, color: Colors.grey[800]),
        const SizedBox(height: 16),
        const Text('Никого не нашли по фильтрам', style: TextStyle(color: Colors.grey, fontSize: 15)),
      ],
    ),
  );

  void _showUserActions(Map<String, dynamic> user) {
    final username = user['username'] as String? ?? 'Неизвестно';
    final role = user['role'] as String? ?? 'user';
    final status = user['status'] as String? ?? 'pending';
    final userId = user['id'] as int?;
    if (userId == null) return;

    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    bool canManage = ['admin', 'superadmin', 'coordinator', 'supervisor'].contains(_currentUserRole);
    bool canDelete = _currentUserRole == 'superadmin';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.withOpacity(0.3), borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 24),
            Text(username, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
            const SizedBox(height: 4),
            Text('${_roleLabels[role] ?? role} • ${status == 'active' ? 'Активен' : 'Ожидание'}', 
              style: TextStyle(color: _roleColors[role], fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 24),
            if (canManage) ...[
              if (status != 'active')
                _buildActionButton('Активировать', Icons.check_circle_outline, Colors.green, () {
                  Navigator.pop(ctx);
                  _updateUserStatus(userId, username, 'active');
                }),
              if (status == 'active')
                _buildActionButton('Деактивировать', Icons.block_flipped, Colors.orange, () {
                  Navigator.pop(ctx);
                  _updateUserStatus(userId, username, 'pending');
                }),
              const SizedBox(height: 12),
              _buildActionButton('Изменить роль', Icons.manage_accounts_outlined, isDarkMode ? Colors.white : Colors.black87, () {
                Navigator.pop(ctx);
                _changeUserRole(userId, username, role);
              }),
            ],
            if (canDelete) ...[
              const SizedBox(height: 12),
              _buildActionButton('Удалить пользователя', Icons.delete_outline_rounded, Colors.red, () {
                Navigator.pop(ctx);
                _deleteUser(userId, username);
              }),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(String label, IconData icon, Color color, VoidCallback onTap) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 20, color: color),
        label: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          side: BorderSide(color: color.withOpacity(0.2)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
