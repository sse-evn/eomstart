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
  Map<String, dynamic> _stats = {};
  
  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token == null) return;
      
      final allShifts = await _apiService.getEndedShifts(token);
      final username = widget.user['username'] ?? '';
      
      // Фильтруем только смены этого пользователя
      final userShifts = allShifts.where((s) => s.username == username).toList();
      userShifts.sort((a, b) => (b.endTimeString ?? '').compareTo(a.endTimeString ?? ''));
      
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
           _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
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
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text('Всего: ${_userShifts.length}', style: TextStyle(color: Colors.green[700], fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_userShifts.isEmpty)
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
                  ..._userShifts.map((shift) => Container(
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
