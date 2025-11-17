import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:micro_mobility_app/core/themes/colors.dart';
import 'package:micro_mobility_app/providers/shift_provider.dart' show ShiftProvider;
import 'package:micro_mobility_app/services/api_service.dart' show ApiService;
import 'package:provider/provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';

class SlotSetupModal extends StatefulWidget {
  const SlotSetupModal({super.key});
  @override
  State<SlotSetupModal> createState() => _SlotSetupModalState();
}

class _SlotSetupModalState extends State<SlotSetupModal> {
  final _storage = const FlutterSecureStorage();
  final _picker = ImagePicker();
  final _apiService = ApiService();

  String? _selectedTime;
  String? _position;
  String? _zone;
  XFile? _selfie;
  bool _isLoading = false;
  bool _hasActiveShift = false;
  bool _backendConflict = false;
  List<String> _timeSlots = [];
  List<String> _zones = [];
  String? _token;
  dynamic _activeShift;

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  Future<void> _initializeData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      _token = await _storage.read(key: 'jwt_token');
      if (_token == null) throw Exception('Требуется авторизация');

      final provider = Provider.of<ShiftProvider>(context, listen: false);
      final activeShift = await provider.getActiveShift();
      if (activeShift != null) {
        setState(() {
          _hasActiveShift = true;
          _backendConflict = true;
          _activeShift = activeShift;
        });
        return;
      }

      final profile = await _retryApiCall(() => _apiService.getUserProfile(_token!));
      String? positionFromProfile;
      for (var key in ['position', 'job_title', 'role', 'dolzhnost', 'должность']) {
        if (profile.containsKey(key) && profile[key] != null) {
          positionFromProfile = profile[key].toString();
          break;
        }
      }

      final serverZones = await _retryApiCall(() => _apiService.getAvailableZones(_token!));
      final serverTimeSlots = await _retryApiCall(() => _apiService.getAvailableTimeSlotsForStart(_token!));
      final uniqueZones = serverZones.toSet().toList();
      final defaultZone = uniqueZones.isNotEmpty ? uniqueZones.first : null;

      if (mounted) {
        setState(() {
          _zones = uniqueZones;
          _timeSlots = serverTimeSlots.toSet().toList();
          _position = positionFromProfile ?? 'Не указана';
          _zone = defaultZone;
          _selectedTime = _timeSlots.isNotEmpty ? _timeSlots.first : null;
        });
      }
    } catch (e) {
      if (mounted) {
        final errorMessage = e.toString().contains('502')
            ? 'Сервер временно недоступен (502). Пожалуйста, попробуйте позже.'
            : 'Не удалось загрузить данные: ${e.toString()}';
        _showError(errorMessage);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<T> _retryApiCall<T>(Future<T> Function() apiCall) async {
    const maxRetries = 3;
    const retryDelay = Duration(seconds: 2);
    for (var i = 0; i < maxRetries; i++) {
      try {
        return await apiCall();
      } catch (e) {
        if (e.toString().contains('502') && i < maxRetries - 1) {
          await Future.delayed(retryDelay);
          continue;
        }
        rethrow;
      }
    }
    throw Exception('API call failed after $maxRetries retries');
  }

  Future<void> _takeSelfie() async {
    if (_isLoading) return;
    try {
      final image = await _picker.pickImage(source: ImageSource.camera, maxWidth: 800, imageQuality: 80);
      if (image != null && mounted) setState(() => _selfie = image);
    } catch (e) {
      if (mounted) _showError('Не удалось открыть камеру');
    }
  }

  Future<void> _finish() async {
    if (_hasActiveShift) {
      await _endShift();
    } else {
      await _startNewShift();
    }
  }

  Future<void> _startNewShift() async {
    if (_token == null) { _showError('Требуется авторизация'); return; }
    if (_selectedTime == null) { _showError('Выберите время смены'); return; }
    if (_zone == null) { _showError('Нет доступных зон'); return; }
    if (_selfie == null) { _showError('Сделайте селфи'); return; }
    if (_position == null || _position!.isEmpty) {
      _showError('Не удалось определить вашу должность. Обратитесь к администратору.'); return;
    }

    final provider = Provider.of<ShiftProvider>(context, listen: false);
    try {
      final processedFile = await _processSelfieWithOverlay(File(_selfie!.path));
      await _retryApiCall(() => provider.startSlot(
        slotTimeRange: _selectedTime!,
        position: _position!,
        zone: _zone!,
        selfie: XFile(processedFile.path),
      ));
      await provider.loadShifts();
      if (mounted) {
        Navigator.pop(context, true);
        _showSuccess('Смена успешно начата');
      }
    } catch (e) {
      if (mounted) {
        final errorMessage = e.toString().contains('502')
            ? 'Сервер временно недоступен (502). Пожалуйста, попробуйте позже.'
            : e.toString().contains('active')
                ? 'У вас уже есть активная смена'
                : 'Ошибка при старте смены: ${e.toString()}';
        _showError(errorMessage);
        if (e.toString().contains('active')) _backendConflict = true;
      }
    }
  }

  Future<void> _endShift() async {
    if (_token == null) { _showError('Требуется авторизация'); return; }
    try {
      final provider = Provider.of<ShiftProvider>(context, listen: false);
      await _retryApiCall(() => provider.endSlot());
      await provider.loadShifts();
      if (mounted) {
        setState(() {
          _hasActiveShift = false;
          _backendConflict = false;
          _activeShift = null;
        });
        _showSuccess('Смена успешно завершена');
      }
    } catch (e) {
      if (mounted) _showError('Ошибка при завершении смены: ${e.toString()}');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: Colors.red,
      behavior: SnackBarBehavior.floating,
    ));
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: Colors.green,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    return PopScope(
      canPop: !_isLoading,
      child: Container(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 24, right: 24, top: 24),
        decoration: BoxDecoration(
          color: isDarkMode ? Colors.grey[900] : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _hasActiveShift ? 'Завершить смену' : 'Начать новую смену',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: isDarkMode ? Colors.white : Colors.green[800]),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    if (_hasActiveShift) _buildActiveShiftInfo() else _buildNewShiftForm(isDarkMode),
                    const SizedBox(height: 24),
                    _buildActionButton(),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
      ),
    );
  }

  Future<File> _processSelfieWithOverlay(File imageFile) async {
    final now = DateTime.now();
    final timeStr = '${now.day}.${now.month}.${now.year} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    String locationStr = 'Гео: недоступно';
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) locationStr = 'Гео: сервис отключён';
      else {
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
          final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium, timeLimit: const Duration(seconds: 8));
          locationStr = 'Гео: ${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}';
        } else locationStr = 'Гео: доступ запрещён';
      }
    } catch (_) { locationStr = 'Гео: ошибка'; }

    final bytes = await imageFile.readAsBytes();
    final original = img.decodeImage(bytes);
    if (original == null) throw Exception('Не удалось декодировать изображение');
    final oriented = img.bakeOrientation(original);
    final resized = img.copyResize(oriented, width: 800);
    final textColor = img.ColorRgb8(255, 255, 255);
    final shadowColor = img.ColorRgb8(0, 0, 0);
    final font = img.arial48;
    img.drawString(resized, font: font, timeStr, x: 11, y: 11, color: shadowColor);
    img.drawString(resized, font: font, locationStr, x: 11, y: 41, color: shadowColor);
    img.drawString(resized, font: font, timeStr, x: 10, y: 10, color: textColor);
    img.drawString(resized, font: font, locationStr, x: 10, y: 40, color: textColor);
    final jpeg = img.encodeJpg(resized, quality: 100);
    final tempFile = File('${imageFile.path}_overlay_${DateTime.now().millisecondsSinceEpoch}.jpg');
    return await tempFile.writeAsBytes(jpeg);
  }

  Widget _buildActiveShiftInfo() {
    if (_activeShift == null) return const SizedBox.shrink();
    return Card(
      color: Colors.red[50],
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Внимание!', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red[800])),
          const SizedBox(height: 8),
          Text('У вас уже есть активная смена.'),
          if (_activeShift['slot_time_range'] != null) Text('Время: ${_activeShift['slot_time_range']}'),
          if (_activeShift['zone'] != null) Text('Зона: ${_activeShift['zone']}'),
          if (_activeShift['position'] != null) Text('Должность: ${_activeShift['position']}'),
        ]),
      ),
    );
  }

  Widget _buildNewShiftForm(bool isDarkMode) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: isDarkMode ? Colors.grey[850] : Colors.grey[100], borderRadius: BorderRadius.circular(12)),
          child: Column(
            children: [
              Row(children: [Icon(Icons.camera_alt, color: isDarkMode ? Colors.white : Colors.black), const SizedBox(width: 8), Text('Селфи', style: TextStyle(fontWeight: FontWeight.w500))]),
              const SizedBox(height: 12),
              _selfie != null ? _buildSelfiePreview() : _buildSelfiePlaceholder(isDarkMode),
              const SizedBox(height: 12),
              _buildSelfieButton(isDarkMode),
            ],
          ),
        ),
        const SizedBox(height: 24),
        if (_timeSlots.isEmpty) _buildNoTimeSlotsWarning() else _buildTimeSlotsSelection(isDarkMode),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: isDarkMode ? Colors.grey[850] : Colors.grey[100], borderRadius: BorderRadius.circular(12)),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [Icon(Icons.location_on, color: isDarkMode ? Colors.white : Colors.black), const SizedBox(width: 6), Text('Зона', style: TextStyle(fontWeight: FontWeight.w500))]),
                    const SizedBox(height: 6),
                    _buildZoneDropdown(isDarkMode),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [Icon(Icons.work, color: isDarkMode ? Colors.white : Colors.black), const SizedBox(width: 6), Text('Должность', style: TextStyle(fontWeight: FontWeight.w500))]),
                    const SizedBox(height: 6),
                    TextFormField(
                      initialValue: _position ?? 'Не указана',
                      readOnly: true,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        filled: true,
                        fillColor: isDarkMode ? Colors.grey[800] : Colors.grey[50],
                        hintStyle: TextStyle(color: isDarkMode ? Colors.grey[500] : Colors.grey[400]),
                      ),
                      style: TextStyle(color: isDarkMode ? Colors.white : Colors.black, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNoTimeSlotsWarning() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.orange[100], borderRadius: BorderRadius.circular(12)),
        child: Column(
          children: [
            Icon(Icons.access_time, color: Colors.orange, size: 32),
            const SizedBox(height: 8),
            Text('Сейчас не время начала смены', textAlign: TextAlign.center, style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Доступные слоты:\n• 06:40–15:00\n• 14:40–23:00', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
          ],
        ),
      );

  Widget _buildTimeSlotsSelection(bool isDarkMode) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: isDarkMode ? Colors.grey[850] : Colors.grey[100], borderRadius: BorderRadius.circular(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [Icon(Icons.schedule, color: isDarkMode ? Colors.white : Colors.black), const SizedBox(width: 8), Text('Время смены', style: TextStyle(fontWeight: FontWeight.w500))]),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8.0,
              runSpacing: 8.0,
              children: _timeSlots.map((slot) {
                final isSelected = _selectedTime == slot;
                return ChoiceChip(
                  label: Text(slot),
                  selected: isSelected,
                  selectedColor: Colors.green[700],
                  onSelected: _isLoading ? null : (selected) { if (selected && mounted) setState(() => _selectedTime = slot); },
                );
              }).toList(),
            ),
          ],
        ),
      );

  Widget _buildSelfiePreview() => ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            Image.file(File(_selfie!.path), height: 150, width: 150, fit: BoxFit.cover),
            Positioned(
              top: 8,
              right: 8,
              child: GestureDetector(
                onTap: () { if (mounted) setState(() => _selfie = null); },
                child: Container(padding: const EdgeInsets.all(4), decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle), child: const Icon(Icons.close, color: Colors.white, size: 16)),
              ),
            ),
          ],
        ),
      );

  Widget _buildSelfiePlaceholder(bool isDarkMode) => Container(
        height: 150,
        width: 150,
        decoration: BoxDecoration(
          color: isDarkMode ? Colors.grey[800] : Colors.grey[200],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isDarkMode ? Colors.grey[700]! : Colors.grey[300]!, width: 2),
        ),
        child: Icon(Icons.person, size: 60, color: isDarkMode ? Colors.grey[600] : Colors.grey[400]),
      );

  Widget _buildSelfieButton(bool isDarkMode) => ElevatedButton.icon(
        onPressed: _isLoading ? null : _takeSelfie,
        icon: const Icon(Icons.camera_alt, color: Colors.white),
        label: const Text('Сделать селфи', style: TextStyle(color: Colors.white)),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green[700],
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );

  Widget _buildZoneDropdown(bool isDarkMode) {
    final validZone = _zones.contains(_zone) ? _zone : (_zones.isNotEmpty ? _zones.first : null);
    return DropdownButtonFormField<String>(
      value: validZone,
      items: _zones.map((item) => DropdownMenuItem(value: item, child: Text(item, style: TextStyle(color: isDarkMode ? Colors.white : Colors.black)))).toList(),
      onChanged: _isLoading ? null : (String? value) { if (mounted && value != null) setState(() => _zone = value); },
      decoration: InputDecoration(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        filled: true,
        fillColor: isDarkMode ? Colors.grey[800] : Colors.grey[50],
        hintStyle: TextStyle(color: isDarkMode ? Colors.grey[500] : Colors.grey[400]),
      ),
      dropdownColor: isDarkMode ? Colors.grey[800] : Colors.white,
      style: TextStyle(color: isDarkMode ? Colors.white : Colors.black, fontSize: 16),
      icon: Icon(Icons.arrow_drop_down, color: isDarkMode ? Colors.grey[400] : Colors.grey[600]),
    );
  }

  Widget _buildActionButton() {
    bool canSubmit = !_isLoading && !_hasActiveShift && _selectedTime != null && _selfie != null && _position != null && _zone != null;
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: (_hasActiveShift || canSubmit) ? _finish : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: _hasActiveShift ? Colors.red[700] : (canSubmit ? AppColors.primary : Colors.grey[400]),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 2,
        ),
        child: _isLoading
            ? const CircularProgressIndicator(color: Colors.white)
            : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(_hasActiveShift ? Icons.stop : Icons.play_arrow, color: Colors.white),
                const SizedBox(width: 8),
                Text(_hasActiveShift ? 'Закончить смену' : (canSubmit ? 'Начать смену' : 'Недоступно'), style: const TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold)),
              ]),
      ),
    );
  }
}
