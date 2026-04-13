import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:micro_mobility_app/src/core/themes/colors.dart';
import 'package:micro_mobility_app/src/core/providers/shift_provider.dart' show ShiftProvider;
import 'package:micro_mobility_app/src/core/services/api_service.dart' show ApiService;
import 'package:provider/provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:micro_mobility_app/src/features/home/bloc/shift_bloc.dart';
import 'package:micro_mobility_app/src/features/home/bloc/shift_event.dart';
import 'package:micro_mobility_app/src/features/home/bloc/shift_state.dart';

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
      
      // Сортировка зон: сначала числа по возрастанию, затем все остальное
      final uniqueZones = serverZones.toSet().toList();
      uniqueZones.sort((a, b) {
        final aInt = int.tryParse(a);
        final bInt = int.tryParse(b);
        if (aInt != null && bInt != null) return aInt.compareTo(bInt);
        if (aInt != null) return -1;
        if (bInt != null) return 1;
        return a.compareTo(b);
      });

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
    if (_selfie == null || _token == null) return;
    final bloc = BlocProvider.of<ShiftBloc>(context);
    try {
      final processedFile = await _processSelfieWithOverlay(File(_selfie!.path));
      
      bloc.add(StartShiftRequested(
        slotTimeRange: _selectedTime!,
        position: _position!,
        zone: _zone!,
        selfie: XFile(processedFile.path),
      ));

      if (mounted) {
        Navigator.pop(context, true);
        _showSuccess('Запрос на открытие смены отправлен');
      }
    } catch (e) {
      if (mounted) {
        _showError('Ошибка при обработке фото: ${e.toString()}');
      }
    }
  }

  Future<void> _endShift() async {
    if (_token == null) { _showError('Требуется авторизация'); return; }
    try {
      final bloc = BlocProvider.of<ShiftBloc>(context);
      bloc.add(EndShiftRequested());
      
      if (mounted) {
        setState(() {
          _hasActiveShift = false;
          _backendConflict = false;
          _activeShift = null;
        });
        Navigator.pop(context, true);
        _showSuccess('Запрос на завершение смены отправлен');
      }
    } catch (e) {
      if (mounted) _showError('Ошибка при отправке запроса: ${e.toString()}');
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
    final colorScheme = theme.colorScheme;
    final isDarkMode = theme.brightness == Brightness.dark;
    
    return PopScope(
      canPop: !_isLoading,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          left: 20,
          right: 20,
          top: 10,
        ),
        decoration: BoxDecoration(
          color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 20,
              offset: const Offset(0, -5),
            )
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle for modal
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            
            Text(
              _hasActiveShift ? 'Завершить смену' : 'Начать новую смену',
              style: TextStyle(
                fontSize: 22, 
                fontWeight: FontWeight.w900, 
                color: isDarkMode ? Colors.white : Colors.black,
                letterSpacing: -0.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            
            Flexible(
              child: _isLoading
                ? const Padding(
                    padding: EdgeInsets.all(40.0),
                    child: CircularProgressIndicator(),
                  )
                : SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_hasActiveShift) 
                          _buildActiveShiftInfo(theme) 
                        else 
                          _buildNewShiftForm(theme, isDarkMode),
                        const SizedBox(height: 24),
                        _buildActionButton(theme),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
            ),
          ],
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
      if (!serviceEnabled) {
        locationStr = 'Гео: сервис отключён';
      } else {
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
          final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium, timeLimit: const Duration(seconds: 8));
          locationStr = 'Гео: ${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}';
        } else {
          locationStr = 'Гео: доступ запрещён';
        }
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

  Widget _buildActiveShiftInfo(ThemeData theme) {
    if (_activeShift == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.red.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, 
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
              const SizedBox(width: 12),
              Text('Внимание!', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red[800])),
            ],
          ),
          const SizedBox(height: 12),
          const Text('У вас уже есть активная смена. Вы не можете начать новую, пока не завершите текущую.', 
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          const SizedBox(height: 16),
          Divider(color: Colors.red.withOpacity(0.1)),
          const SizedBox(height: 16),
          if (_activeShift['slot_time_range'] != null) 
            _buildInfoRow(Icons.access_time, 'Время', _activeShift['slot_time_range']),
          if (_activeShift['zone'] != null) 
            _buildInfoRow(Icons.location_on_outlined, 'Зона', _activeShift['zone']),
          if (_activeShift['position'] != null) 
            _buildInfoRow(Icons.work_outline, 'Должность', _activeShift['position']),
        ]
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          const SizedBox(width: 8),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildNewShiftForm(ThemeData theme, bool isDarkMode) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Selfie Area
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDarkMode ? Colors.white.withOpacity(0.05) : Colors.grey[50],
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: isDarkMode ? Colors.white.withOpacity(0.1) : Colors.grey[200]!),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(Icons.camera_alt_outlined, size: 20),
                  const SizedBox(width: 10),
                  const Text('Фото-подтверждение', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ],
              ),
              const SizedBox(height: 20),
              _selfie != null ? _buildSelfiePreview() : _buildSelfiePlaceholder(isDarkMode),
              const SizedBox(height: 20),
              _buildSelfieButton(isDarkMode),
            ],
          ),
        ),
        const SizedBox(height: 20),
        
        // Time Slot Area
        if (_timeSlots.isEmpty) 
          _buildNoTimeSlotsWarning(isDarkMode) 
        else 
          _buildTimeSlotsSelection(isDarkMode),
        
        const SizedBox(height: 20),
        
        // Zone and Position
        LayoutBuilder(
          builder: (context, constraints) {
            final bool isNarrow = constraints.maxWidth < 350;
            if (isNarrow) {
              return Column(
                children: [
                  _buildInputWrapper(
                    isDarkMode,
                    'Зона',
                    Icons.location_on_outlined,
                    _buildZoneDropdown(isDarkMode),
                  ),
                  const SizedBox(height: 16),
                  _buildInputWrapper(
                    isDarkMode,
                    'Должность',
                    Icons.work_outline,
                    _buildPositionField(isDarkMode),
                  ),
                ],
              );
            }
            return Row(
              children: [
                Expanded(
                  child: _buildInputWrapper(
                    isDarkMode,
                    'Зона',
                    Icons.location_on_outlined,
                    _buildZoneDropdown(isDarkMode),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildInputWrapper(
                    isDarkMode,
                    'Должность',
                    Icons.work_outline,
                    _buildPositionField(isDarkMode),
                  ),
                ),
              ],
            );
          }
        ),
      ],
    );
  }

  Widget _buildInputWrapper(bool isDarkMode, String label, IconData icon, Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Row(
            children: [
              Icon(icon, size: 14, color: Colors.grey[600]),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey[600])),
            ],
          ),
        ),
        child,
      ],
    );
  }

  Widget _buildPositionField(bool isDarkMode) {
    return TextFormField(
      initialValue: _position ?? 'Не указана',
      readOnly: true,
      decoration: InputDecoration(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        filled: true,
        fillColor: isDarkMode ? Colors.white.withOpacity(0.05) : Colors.grey[100],
      ),
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    );
  }

  Widget _buildNoTimeSlotsWarning(bool isDarkMode) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.orange.withOpacity(0.1),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.orange.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), shape: BoxShape.circle),
              child: const Icon(Icons.access_time_filled, color: Colors.orange, size: 28),
            ),
            const SizedBox(height: 16),
            const Text('Сейчас не время начала смены', 
              textAlign: TextAlign.center, 
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.orange)),
            const SizedBox(height: 8),
            Text('Начало смены доступно только в пределах выбранных слотов.', 
              textAlign: TextAlign.center, 
              style: TextStyle(color: Colors.grey[600], fontSize: 13)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isDarkMode ? Colors.white.withOpacity(0.05) : Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text('Слоты: 06:40–15:00, 14:40–23:00', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            ),
          ],
        ),
      );

  Widget _buildTimeSlotsSelection(bool isDarkMode) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDarkMode ? Colors.white.withOpacity(0.05) : Colors.grey[50],
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: isDarkMode ? Colors.white.withOpacity(0.1) : Colors.grey[200]!),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.history_toggle_off, size: 20),
                const SizedBox(width: 10),
                const Text('Выберите слот', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8.0,
              runSpacing: 8.0,
              children: _timeSlots.map((slot) {
                final isSelected = _selectedTime == slot;
                return GestureDetector(
                  onTap: _isLoading ? null : () { if (mounted) setState(() => _selectedTime = slot); },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.green : (isDarkMode ? Colors.white.withOpacity(0.05) : Colors.white),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isSelected ? Colors.green : (isDarkMode ? Colors.white.withOpacity(0.1) : Colors.grey[300]!)),
                      boxShadow: isSelected ? [BoxShadow(color: Colors.green.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))] : [],
                    ),
                    child: Text(slot, 
                      style: TextStyle(
                        color: isSelected ? Colors.white : (isDarkMode ? Colors.white : Colors.black),
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        fontSize: 13,
                      )),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      );

  Widget _buildSelfiePreview() => Stack(
        alignment: Alignment.center,
        children: [
          Container(
            height: 180,
            width: 180,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 15)],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: Image.file(File(_selfie!.path), fit: BoxFit.cover),
            ),
          ),
          Positioned(
            top: -5,
            right: -5,
            child: IconButton(
              onPressed: () { if (mounted) setState(() => _selfie = null); },
              icon: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                child: const Icon(Icons.close, color: Colors.white, size: 14),
              ),
            ),
          ),
        ],
      );

  Widget _buildSelfiePlaceholder(bool isDarkMode) => Container(
        height: 180,
        width: 180,
        decoration: BoxDecoration(
          color: isDarkMode ? Colors.white.withOpacity(0.02) : Colors.white,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: isDarkMode ? Colors.white.withOpacity(0.1) : Colors.grey[300]!, style: BorderStyle.none),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_outline, size: 64, color: isDarkMode ? Colors.grey[700] : Colors.grey[300]),
            const SizedBox(height: 8),
            Text('Нет фото', style: TextStyle(color: Colors.grey[500], fontSize: 12, fontWeight: FontWeight.bold)),
          ],
        ),
      );

  Widget _buildSelfieButton(bool isDarkMode) => SizedBox(
    width: double.infinity,
    child: ElevatedButton.icon(
          onPressed: _isLoading ? null : _takeSelfie,
          icon: const Icon(Icons.add_a_photo_outlined, size: 20),
          label: const Text('Сделать селфи', style: TextStyle(fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
  );

  Widget _buildZoneDropdown(bool isDarkMode) {
    final validZone = _zones.contains(_zone) ? _zone : (_zones.isNotEmpty ? _zones.first : null);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.white.withOpacity(0.05) : Colors.grey[100],
        borderRadius: BorderRadius.circular(16),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: validZone,
          isExpanded: true,
          menuMaxHeight: 350,
          items: _zones.map((item) => DropdownMenuItem(
            value: item, 
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(item, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))
            )
          )).toList(),
          onChanged: _isLoading ? null : (String? value) { if (mounted && value != null) setState(() => _zone = value); },
          dropdownColor: isDarkMode ? const Color(0xFF2C2C2C) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
        ),
      ),
    );
  }

  Widget _buildActionButton(ThemeData theme) {
    bool canSubmit = !_isLoading && !_hasActiveShift && _selectedTime != null && _selfie != null && _position != null && _zone != null;
    final isEnded = _hasActiveShift;
    
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          if (canSubmit || isEnded)
            BoxShadow(
              color: (isEnded ? Colors.red : Colors.green).withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 6),
            )
        ],
      ),
      child: ElevatedButton(
        onPressed: (isEnded || canSubmit) ? _finish : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: isEnded ? Colors.red : (canSubmit ? Colors.green : Colors.grey[300]),
          foregroundColor: Colors.white,
          disabledBackgroundColor: theme.brightness == Brightness.dark ? Colors.white.withOpacity(0.05) : Colors.grey[200],
          padding: const EdgeInsets.symmetric(vertical: 18),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
        child: _isLoading
            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Row(
                mainAxisAlignment: MainAxisAlignment.center, 
                children: [
                  Icon(isEnded ? Icons.power_settings_new : Icons.verified_user_outlined, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    isEnded ? 'Завершить смену' : (canSubmit ? 'Начать смену' : 'Заполните данные'), 
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 0.2),
                  ),
                ],
              ),
      ),
    );
  }
}
