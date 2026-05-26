import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:micro_mobility_app/src/core/services/promo_api_service.dart';

class BoltAccountsAdminScreen extends StatefulWidget {
  const BoltAccountsAdminScreen({super.key});

  @override
  State<BoltAccountsAdminScreen> createState() =>
      _BoltAccountsAdminScreenState();
}

class _BoltAccountsAdminScreenState extends State<BoltAccountsAdminScreen> {
  final PromoApiService _service = PromoApiService();
  List<dynamic> _accounts = [];
  List<dynamic> _allUsers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final accounts = await _service.getBoltAccounts();
      List<dynamic> users = [];
      try {
        users = await _service.getAllAdminUsers();
      } catch (_) {}
      if (mounted) {
        setState(() {
          _accounts = accounts;
          _allUsers = users;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _showCreateDialog() async {
    final loginCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final descCtrl = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Новый Bolt аккаунт'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: loginCtrl,
                decoration: const InputDecoration(
                    labelText: 'Логин',
                    prefixIcon: Icon(Icons.person_outline))),
            const SizedBox(height: 12),
            TextField(
                controller: passCtrl,
                decoration: const InputDecoration(
                    labelText: 'Пароль', prefixIcon: Icon(Icons.lock_outline))),
            const SizedBox(height: 12),
            TextField(
                controller: descCtrl,
                decoration: const InputDecoration(
                    labelText: 'Описание (опционально)',
                    prefixIcon: Icon(Icons.note_outlined))),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          ElevatedButton(
            onPressed: () {
              if (loginCtrl.text.isNotEmpty && passCtrl.text.isNotEmpty) {
                Navigator.pop(ctx, true);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Создать', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (result == true) {
      try {
        await _service.createBoltAccount(loginCtrl.text, passCtrl.text,
            description: descCtrl.text);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Аккаунт создан'), backgroundColor: Colors.green));
        }
        _loadData();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Ошибка: $e'), backgroundColor: Colors.red));
        }
      }
    }
  }

  Future<void> _showEditDialog(Map<String, dynamic> account) async {
    final loginCtrl = TextEditingController(text: account['login']);
    final passCtrl = TextEditingController(text: account['password']);
    final descCtrl = TextEditingController(text: account['description'] ?? '');

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Редактирование'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: loginCtrl,
                decoration: const InputDecoration(
                    labelText: 'Логин',
                    prefixIcon: Icon(Icons.person_outline))),
            const SizedBox(height: 12),
            TextField(
                controller: passCtrl,
                decoration: const InputDecoration(
                    labelText: 'Пароль', prefixIcon: Icon(Icons.lock_outline))),
            const SizedBox(height: 12),
            TextField(
                controller: descCtrl,
                decoration: const InputDecoration(
                    labelText: 'Описание',
                    prefixIcon: Icon(Icons.note_outlined))),
          ],
        ),
        actions: [
          Row(
            children: [
              TextButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (c) => AlertDialog(
                      title: const Text('Удалить аккаунт?'),
                      content: Text('Аккаунт "${account['login']}" будет удалён.'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(c),
                            child: const Text('Нет')),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(c, true),
                          style:
                              ElevatedButton.styleFrom(backgroundColor: Colors.red),
                          child: const Text('Удалить',
                              style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    await _service.deleteBoltAccount(account['id']);
                    _loadData();
                  }
                },
                child: const Text('Удалить', style: TextStyle(color: Colors.red)),
              ),
              const Spacer(),
              TextButton(
                  onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                child:
                    const Text('Сохранить', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ],
      ),
    );

    if (result == true) {
      try {
        await _service.updateBoltAccount(
          account['id'],
          login: loginCtrl.text,
          password: passCtrl.text,
          description: descCtrl.text,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Обновлено'), backgroundColor: Colors.green));
        }
        _loadData();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Ошибка: $e'), backgroundColor: Colors.red));
        }
      }
    }
  }

  Future<void> _showBulkAssignDialog(Map<String, dynamic> account) async {
    // Currently assigned user IDs
    final assignedTo = (account['assigned_to'] as List?) ?? [];
    final assignedUserIds = assignedTo.map((a) => a['user_id'] as int).toSet();

    // All users (scouts)
    final allUsers = _allUsers.where((u) {
      final role = (u['role'] as String?) ?? '';
      return role == 'scout';
    }).toList();

    final selectedIds = Set<int>.from(assignedUserIds);

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: Text('Назначить "${account['login']}"'),
            content: SizedBox(
              width: double.maxFinite,
              height: 400,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Выбрано: ${selectedIds.length} сотрудников',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, color: Colors.green),
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () {
                            setDialogState(() {
                              for (final u in allUsers) {
                                selectedIds.add(u['id'] as int);
                              }
                            });
                          },
                          child: const Text('Выбрать всех'),
                        ),
                      ),
                      Expanded(
                        child: TextButton(
                          onPressed: () =>
                              setDialogState(() => selectedIds.clear()),
                          child: const Text('Снять всех'),
                        ),
                      ),
                    ],
                  ),
                  const Divider(),
                  Expanded(
                    child: ListView.builder(
                      itemCount: allUsers.length,
                      itemBuilder: (_, i) {
                        final user = allUsers[i];
                        final userId = user['id'] as int;
                        final name = user['first_name'] ?? '';
                        final username = user['username'] ?? '';
                        final isChecked = selectedIds.contains(userId);

                        return CheckboxListTile(
                          value: isChecked,
                          dense: true,
                          activeColor: Colors.green,
                          title: Text(
                            name.isNotEmpty
                                ? '$name (@$username)'
                                : '@$username',
                            style: const TextStyle(fontSize: 14),
                          ),
                          onChanged: (v) {
                            setDialogState(() {
                              if (v == true) {
                                selectedIds.add(userId);
                              } else {
                                selectedIds.remove(userId);
                              }
                            });
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Отмена')),
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  if (selectedIds.isEmpty) return;

                  try {
                    // Unassign removed users
                    for (final prev in assignedUserIds) {
                      if (!selectedIds.contains(prev)) {
                        await _service.unassignBoltAccount(account['id'], prev);
                      }
                    }
                    // Bulk assign selected
                    if (selectedIds.isNotEmpty) {
                      await _service.bulkAssignBoltAccount(
                          account['id'], selectedIds.toList());
                    }
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: Text(
                                'Назначено ${selectedIds.length} сотрудникам'),
                            backgroundColor: Colors.green),
                      );
                    }
                    _loadData();
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text('Ошибка: $e'),
                          backgroundColor: Colors.red));
                    }
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                child: const Text('Применить',
                    style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.bolt, color: Colors.green, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Bolt Аккаунты',
                        style: TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 16)),
                    Text('${_accounts.length} аккаунтов',
                        style:
                            TextStyle(color: Colors.grey[500], fontSize: 12)),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: _showCreateDialog,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Добавить'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // Account list
        Expanded(
          child: _accounts.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.bolt, size: 48, color: Colors.grey),
                      SizedBox(height: 12),
                      Text('Нет аккаунтов',
                          style: TextStyle(color: Colors.grey, fontSize: 16)),
                      Text('Нажмите "Добавить" для создания',
                          style: TextStyle(color: Colors.grey, fontSize: 13)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _accounts.length,
                    itemBuilder: (_, i) =>
                        _buildAccountCard(_accounts[i], isDark),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildAccountCard(Map<String, dynamic> account, bool isDark) {
    final assignedTo = (account['assigned_to'] as List?) ?? [];
    final isActive = account['is_active'] ?? true;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive
              ? Colors.green.withOpacity(0.3)
              : Colors.red.withOpacity(0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Account header
          InkWell(
            onTap: () => _showEditDialog(account),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child:
                        const Icon(Icons.bolt, color: Colors.green, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(account['login'] ?? '',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w900, fontSize: 16)),
                            const SizedBox(width: 8),
                            if (!isActive)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                    color: Colors.red.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(6)),
                                child: const Text('OFF',
                                    style: TextStyle(
                                        color: Colors.red,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold)),
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(Icons.lock_outline,
                                size: 14, color: Colors.grey),
                            const SizedBox(width: 4),
                            Text(account['password'] ?? '',
                                style: TextStyle(
                                    color: Colors.grey[500],
                                    fontSize: 13,
                                    fontFamily: 'monospace')),
                            const SizedBox(width: 8),
                            InkWell(
                              onTap: () {
                                Clipboard.setData(ClipboardData(
                                    text:
                                        '${account['login']}\n${account['password']}'));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content:
                                          Text('Логин и пароль скопированы'),
                                      backgroundColor: Colors.green,
                                      duration: Duration(seconds: 1)),
                                );
                              },
                              child: const Icon(Icons.copy,
                                  size: 14, color: Colors.green),
                            ),
                          ],
                        ),
                        if (account['description'] != null &&
                            (account['description'] as String).isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(account['description'],
                                style: TextStyle(
                                    color: Colors.grey[400],
                                    fontSize: 12,
                                    fontStyle: FontStyle.italic)),
                          ),
                      ],
                    ),
                  ),
                  const Icon(Icons.edit_outlined, size: 18, color: Colors.grey),
                ],
              ),
            ),
          ),

          // Assigned users
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withOpacity(0.02) : Colors.grey[50],
              borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(16)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.people_outline,
                        size: 16, color: Colors.grey[600]),
                    const SizedBox(width: 6),
                    Text(
                      assignedTo.isEmpty
                          ? 'Не назначен'
                          : '${assignedTo.length} сотрудников',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color:
                            assignedTo.isEmpty ? Colors.orange : Colors.green,
                      ),
                    ),
                    const Spacer(),
                    InkWell(
                      onTap: () => _showBulkAssignDialog(account),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.person_add_alt,
                                size: 14, color: Colors.green),
                            SizedBox(width: 4),
                            Text('Назначить',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                if (assignedTo.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: assignedTo.map<Widget>((user) {
                      final name = (user['first_name'] ?? '').toString();
                      final username = (user['username'] ?? '').toString();
                      final displayName = name.isNotEmpty ? name : '@$username';
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border:
                              Border.all(color: Colors.green.withOpacity(0.2)),
                        ),
                        child: Text(displayName,
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.green)),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
