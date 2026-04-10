import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:micro_mobility_app/src/core/config/app_config.dart' show AppConfig;
import 'package:micro_mobility_app/src/features/app/models/active_shift.dart';
import 'package:micro_mobility_app/src/core/services/api_service.dart';
import 'package:provider/provider.dart';
import 'package:micro_mobility_app/src/core/providers/shift_provider.dart';
import 'package:micro_mobility_app/src/core/utils/time_utils.dart';

class ShiftDetailsScreen extends StatefulWidget {
  final ActiveShift shift;

  const ShiftDetailsScreen({required this.shift, super.key});

  @override
  State<ShiftDetailsScreen> createState() => _ShiftDetailsScreenState();
}

class _ShiftDetailsScreenState extends State<ShiftDetailsScreen> {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final ApiService _apiService = ApiService();
  String? _currentUserRole;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token == null) return;
      final profile = await _apiService.getUserProfile(token);
      final role = (profile['role'] ?? 'user').toString().toLowerCase();
      if (mounted) setState(() => _currentUserRole = role);
    } catch (e) {
      debugPrint('Ошибка загрузки профиля: $e');
    }
  }

  Future<void> _forceEndShift() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('⚠️ Завершить смену?', style: TextStyle(fontWeight: FontWeight.w800)),
        content: Text('Вы уверены, что хотите принудительно завершить смену пользователя ${widget.shift.username}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Да, завершить'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);
    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token == null) throw Exception('Токен не найден');
      await _apiService.forceEndShift(token, widget.shift.userId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Смена завершена'), backgroundColor: Colors.green));
        Navigator.pop(context, true);
        Provider.of<ShiftProvider>(context, listen: false).loadShifts();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatDuration(String? startStr, String? endStr) {
    if (startStr == null) return '—';
    try {
      final start = DateTime.parse(startStr);
      final end = endStr != null ? DateTime.parse(endStr) : DateTime.now();
      final diff = end.difference(start);
      final hours = diff.inHours;
      final minutes = diff.inMinutes.remainder(60);
      return '$hours ч $minutes мин';
    } catch (_) {
      return '—';
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isEnded = widget.shift.endTimeString != null;
    final primaryColor = Theme.of(context).primaryColor;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Детали смены', style: TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.black,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildUserHeader(primaryColor, isEnded),
                const SizedBox(height: 24),
                _buildSectionTitle('Временные метки'),
                const SizedBox(height: 12),
                _buildTimeCard(primaryColor, isEnded),
                const SizedBox(height: 24),
                _buildSectionTitle('Фото-подтверждение'),
                const SizedBox(height: 12),
                _buildSelfieCard(),
                const SizedBox(height: 32),
                if ((_currentUserRole == 'superadmin' || _currentUserRole == 'admin') && !isEnded) ...[
                  _buildAdminActions(),
                  const SizedBox(height: 40),
                ],
              ],
            ),
          ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.blueGrey));
  }

  Widget _buildUserHeader(Color primaryColor, bool isEnded) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 20, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: primaryColor.withOpacity(0.1),
            child: Text(widget.shift.username.substring(0, 1).toUpperCase(), 
              style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold, fontSize: 24)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.shift.username, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('${widget.shift.position} • ${widget.shift.zone}', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isEnded ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              isEnded ? 'Завершена' : 'В процессе',
              style: TextStyle(color: isEnded ? Colors.green : Colors.orange, fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeCard(Color primaryColor, bool isEnded) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 20, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          _buildTimeRow(Icons.play_circle_outline, 'Начало', 
              extractTimeFromIsoString(widget.shift.startTimeString), 
              extractDateFromIsoString(widget.shift.startTimeString), Colors.blue),
          const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Divider()),
          _buildTimeRow(Icons.stop_circle, 'Конец', 
              isEnded ? extractTimeFromIsoString(widget.shift.endTimeString) : '— : —', 
              isEnded ? extractDateFromIsoString(widget.shift.endTimeString) : 'Смена активна', 
              isEnded ? Colors.red : Colors.grey),
          const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Divider()),
          _buildTimeRow(Icons.timer_outlined, 'Длительность', 
              _formatDuration(widget.shift.startTimeString, widget.shift.endTimeString), 
              'Общее время работы', Colors.teal),
        ],
      ),
    );
  }

  Widget _buildTimeRow(IconData icon, String label, String time, String date, Color color) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
              Text(time, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        Text(date, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
      ],
    );
  }

  Widget _buildSelfieCard() {
    final photoUrl = '${AppConfig.mediaBaseUrl}${widget.shift.selfie}';
    return Container(
      height: 300,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 20, offset: const Offset(0, 4))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: widget.shift.selfie.isEmpty
          ? const Center(child: Icon(Icons.no_photography_outlined, size: 48, color: Colors.grey))
          : Image.network(
              photoUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image_outlined, size: 48, color: Colors.grey)),
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return const Center(child: CircularProgressIndicator());
              },
            ),
      ),
    );
  }

  Widget _buildAdminActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Управление'),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 60,
          child: ElevatedButton.icon(
            onPressed: _forceEndShift,
            icon: const Icon(Icons.highlight_off),
            label: const Text('Принудительно завершить', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red[50],
              foregroundColor: Colors.red,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.red[100]!)),
            ),
          ),
        ),
      ],
    );
  }
}
