import 'package:flutter/material.dart';
import 'package:micro_mobility_app/src/features/app/models/active_shift.dart';
import 'package:micro_mobility_app/src/core/services/api_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:micro_mobility_app/src/features/admin/shifts_list/shift_details_screen.dart';
import 'package:micro_mobility_app/src/core/config/app_config.dart' as AppConfig;
import 'package:micro_mobility_app/src/core/utils/time_utils.dart';

class UserProfileScreen extends StatefulWidget {
  final Map<String, dynamic> user;

  const UserProfileScreen({super.key, required this.user});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  final ApiService _apiService = ApiService();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  
  bool _isLoading = true;
  List<ActiveShift> _userShifts = [];
  List<ActiveShift> _filteredShifts = [];
  Map<String, dynamic> _stats = {};
  String? _currentUserRole;
  DateTimeRange? _selectedDateRange;
  
  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token == null) return;

      final currentProfile = await _apiService.getUserProfile(token);
      final currentUserRole = currentProfile['role'] as String?;
      
      final allShifts = await _apiService.getEndedShifts(token);
      final username = widget.user['username'] ?? '';
      
      // Фильтруем только смены этого пользователя
      final userShifts = allShifts.where((s) => s.username == username).toList();
      userShifts.sort((a, b) => (b.endTimeString ?? '').compareTo(a.endTimeString ?? ''));
      
      _applyFilter(userShifts);
      
      // Считаем статистику
      int totalShifts = userShifts.length;
      Duration totalDuration = Duration.zero;
      
      for (var s in userShifts) {
        if (s.startTimeString != null && s.endTimeString != null) {
           final start = DateTime.parse(s.startTimeString!);
           final end = DateTime.parse(s.endTimeString!);
           totalDuration += end.difference(start);
        }
      }
      
      final userId = widget.user['id'] as int;
      final statsResponse = await _apiService.getUserStats(token, userId);
      
      if (mounted) {
        setState(() {
           _userShifts = userShifts;
           _stats = {
             'total_shifts': totalShifts,
             'total_hours': totalDuration.inHours,
             'total_minutes': totalDuration.inMinutes.remainder(60),
             'total_scooter_reports': statsResponse['total_scooter_reports'] ?? 0,
             'avg_reports_per_day': statsResponse['avg_reports_per_day'] ?? 0.0,
             'late_shifts': statsResponse['late_shifts'] ?? 0,
             'late_percentage': statsResponse['late_percentage'] ?? 0.0,
           };
           _currentUserRole = currentUserRole;
           _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _applyFilter(List<ActiveShift> allUserShifts) {
    if (_selectedDateRange == null) {
      _filteredShifts = List.from(allUserShifts);
    } else {
      _filteredShifts = allUserShifts.where((shift) {
        if (shift.startTimeString == null) return false;
        final date = DateTime.parse(shift.startTimeString!).toLocal();
        final start = _selectedDateRange!.start;
        final end = _selectedDateRange!.end.add(const Duration(days: 1)); // Включаем конец дня
        return date.isAfter(start) && date.isBefore(end);
      }).toList();
    }
  }

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: _selectedDateRange,
      builder: (context, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: isDark
                ? const ColorScheme.dark(
                    primary: Colors.green,
                    onPrimary: Colors.white,
                    surface: Color(0xFF1E1E1E),
                    onSurface: Colors.white,
                  )
                : const ColorScheme.light(
                    primary: Colors.green,
                    onPrimary: Colors.white,
                    surface: Colors.white,
                    onSurface: Colors.black,
                  ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && mounted) {
      setState(() {
        _selectedDateRange = picked;
        _applyFilter(_userShifts);
      });
    }
  }

  void _clearFilter() {
    setState(() {
      _selectedDateRange = null;
      _applyFilter(_userShifts);
    });
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 4),
            Text(title, style: TextStyle(fontSize: 12, color: Colors.grey[600]), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  String _formatLocalTime(String isoString) {
    return TimeUtils.formatTime(isoString);
  }

  String _formatDate(String isoString) {
    try {
      final date = DateTime.parse(isoString).toLocal();
      return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
    } catch (e) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final username = widget.user['username'] ?? 'Неизвестно';
    final firstName = widget.user['first_name'] ?? username;
    final role = widget.user['role'] ?? 'user';
    final phone = widget.user['phone'] ?? 'Нет номера';
    final avatarUrl = widget.user['avatar_url'] ?? '';
    
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Профиль сотрудника'),
        centerTitle: true,
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: Colors.green))
        : RefreshIndicator(
            onRefresh: _loadData,
            child: ListView(
              padding: const EdgeInsets.all(16),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                // Header (аватарка и данные)
                Center(
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.green,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.green.withOpacity(0.3),
                          blurRadius: 15,
                          offset: const Offset(0, 5),
                        )
                      ]
                    ),
                    child: avatarUrl.isNotEmpty
                        ? ClipOval(
                            child: Image.network(
                              avatarUrl,
                              fit: BoxFit.cover,
                            ),
                          )
                        : Center(
                            child: Text(
                              username.substring(0, 1).toUpperCase(),
                              style: const TextStyle(fontSize: 40, color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 16),
                Center(child: Text(firstName, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold))),
                const SizedBox(height: 4),
                Center(child: Text('@$username • Роль: $role', style: TextStyle(fontSize: 16, color: Colors.grey[600], fontWeight: FontWeight.w500))),
                const SizedBox(height: 4),
                Center(child: Text(phone, style: TextStyle(fontSize: 16, color: Colors.grey[600]))),
                if (widget.user['app_version'] != null && widget.user['app_version'].toString().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.system_update_rounded, size: 16, color: Colors.blueAccent),
                      const SizedBox(width: 6),
                      Text('Версия: ${widget.user['app_version']}',
                          style: const TextStyle(color: Colors.blueAccent, fontSize: 14, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
                if (_currentUserRole == 'evn') ...[
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.deepPurpleAccent.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.deepPurpleAccent.withOpacity(0.2)),
                    ),
                    child: Column(
                      children: [
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.admin_panel_settings, size: 20, color: Colors.redAccent),
                            SizedBox(width: 8),
                            Text('Скрытая Телеметрия', style: TextStyle(color: Colors.redAccent, fontSize: 16, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.analytics_rounded, size: 16, color: Colors.deepPurpleAccent),
                            const SizedBox(width: 6),
                            Text('Открытий приложения: ${widget.user['app_opens'] ?? 0}',
                                style: const TextStyle(color: Colors.deepPurpleAccent, fontSize: 14, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        if (widget.user['device_model'] != null && widget.user['device_model'].toString().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text('Устройство: ${widget.user['device_model']}',
                                style: TextStyle(color: Colors.grey[700], fontSize: 13), textAlign: TextAlign.center),
                          ),
                        if (widget.user['os_version'] != null && widget.user['os_version'].toString().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Text('Версия ОС: ${widget.user['os_version']}',
                                style: TextStyle(color: Colors.grey[700], fontSize: 13), textAlign: TextAlign.center),
                          ),
                        if (widget.user['last_ip'] != null && widget.user['last_ip'].toString().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Text('Последний IP: ${widget.user['last_ip']}',
                                style: TextStyle(color: Colors.grey[700], fontSize: 13), textAlign: TextAlign.center),
                          ),
                        if (widget.user['system_language'] != null && widget.user['system_language'].toString().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Text('Язык системы: ${widget.user['system_language']}',
                                style: TextStyle(color: Colors.grey[700], fontSize: 13), textAlign: TextAlign.center),
                          ),
                        if (widget.user['timezone'] != null && widget.user['timezone'].toString().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Text('Часовой пояс: ${widget.user['timezone']}',
                                style: TextStyle(color: Colors.grey[700], fontSize: 13), textAlign: TextAlign.center),
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 32),
                
                // Stats
                const Text('Общая статистика', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _buildStatCard('Завершенных\nсмен', '${_stats['total_shifts'] ?? 0}', Icons.work_history_rounded, Colors.blue),
                    const SizedBox(width: 12),
                    _buildStatCard('Отработано\nвремени', '${_stats['total_hours'] ?? 0}ч ${_stats['total_minutes'] ?? 0}м', Icons.timer_rounded, Colors.orange),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _buildStatCard('Поправлено\nТС', '${_stats['total_scooter_reports'] ?? 0}', Icons.electric_scooter, Colors.purple),
                    const SizedBox(width: 12),
                    _buildStatCard('В среднем\nв день', '${((_stats['avg_reports_per_day'] ?? 0.0) as num).toStringAsFixed(1)}', Icons.query_stats, Colors.teal),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _buildStatCard('Опоздания\n(>15 мин)', '${_stats['late_shifts'] ?? 0}', Icons.run_circle_outlined, Colors.red),
                    const SizedBox(width: 12),
                    _buildStatCard('% опозданий\nот всех смен', '${((_stats['late_percentage'] ?? 0.0) as num).toStringAsFixed(1)}%', Icons.pie_chart_outline, Colors.deepOrange),
                  ],
                ),
                const SizedBox(height: 32),
                
                // Shifts History
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('История смен', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                    Row(
                      children: [
                        if (_selectedDateRange != null)
                          IconButton(
                            icon: const Icon(Icons.clear, color: Colors.redAccent),
                            onPressed: _clearFilter,
                            tooltip: 'Сбросить фильтр',
                          ),
                        IconButton(
                          icon: Icon(Icons.date_range, color: _selectedDateRange == null ? Colors.grey : Colors.green),
                          onPressed: _selectDateRange,
                          tooltip: 'Фильтр по дате',
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text('Всего: ${_filteredShifts.length}', style: TextStyle(color: Colors.green[700], fontWeight: FontWeight.bold, fontSize: 13)),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_filteredShifts.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(32),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isDarkMode ? Colors.white.withOpacity(0.05) : Colors.grey.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      children: [
                        Icon(Icons.history_toggle_off, size: 48, color: Colors.grey[400]),
                        const SizedBox(height: 12),
                        const Text('Нет завершенных смен', style: TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                  )
                else
                  ..._filteredShifts.map((shift) => Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: isDarkMode ? Colors.white.withOpacity(0.05) : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: isDarkMode ? Colors.white.withOpacity(0.05) : Colors.grey[200]!),
                      boxShadow: [
                        if (!isDarkMode)
                          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 2))
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => ShiftDetailsScreen(shift: shift)));
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(Icons.check_circle_outline, color: Colors.green[700]),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('${shift.zone} • ${shift.position}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${_formatDate(shift.startTimeString!)} | ${_formatLocalTime(shift.startTimeString!)} – ${_formatLocalTime(shift.endTimeString!)}',
                                      style: TextStyle(color: Colors.grey[600], fontSize: 13),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(Icons.chevron_right, color: Colors.grey[400]),
                            ],
                          ),
                        ),
                      ),
                    ),
                  )),
              ],
            ),
          ),
    );
  }
}
