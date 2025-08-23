// lib/modals/slot_setup_modal.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../providers/shift_provider.dart';
import '../services/api_service.dart';

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
  dynamic _activeShift; // Для хранения активной смены

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  @override
  void dispose() {
    super.dispose();
  }

  // Функция проверки, можно ли начать смену в текущее время
  bool _canStartShift(String timeSlot) {
    final now = DateTime.now();
    final currentHour = now.hour;
    final currentMinute = now.minute;

    switch (timeSlot) {
      case '07:00–15:00':
        // Смена начинается в 07:00
        // Можно начать с 06:40 до 07:00 или в любое время до 15:00
        if ((currentHour == 6 && currentMinute >= 40) ||
            (currentHour >= 7 && currentHour < 15) ||
            (currentHour == 15 && currentMinute == 0)) {
          return true;
        }
      case '15:00–23:00':
        // Смена начинается в 15:00
        // Можно начать с 14:40 до 15:00 или в любое время до 23:00
        if ((currentHour == 14 && currentMinute >= 40) ||
            (currentHour >= 15 && currentHour < 23) ||
            (currentHour == 23 && currentMinute == 0)) {
          return true;
        }
      case '23:00–07:00':
        // Ночная смена начинается в 23:00
        // Можно начать с 22:40 или в любое время после 23:00 или до 07:00
        if ((currentHour == 22 && currentMinute >= 40) ||
            currentHour >= 23 ||
            currentHour < 7) {
          return true;
        }
    }
    return false;
  }

  // Функция получения сообщения о ограничениях времени
  String _getTimeRestrictionMessage(String timeSlot) {
    switch (timeSlot) {
      case '07:00–15:00':
        return 'Смену можно начать с 06:40 или в любое время до 15:00';
      case '15:00–23:00':
        return 'Смену можно начать с 14:40 или в любое время до 23:00';
      case '23:00–07:00':
        return 'Смену можно начать с 22:40 или в любое время после 23:00';
      default:
        return 'Смену можно начать только в определенное время';
    }
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

      final profile =
          await _retryApiCall(() => _apiService.getUserProfile(_token!));
      debugPrint('Полный профиль пользователя: $profile');

      String? positionFromProfile;
      final possibleKeys = [
        'position',
        'job_title',
        'role',
        'dolzhnost',
        'должность'
      ];

      for (var key in possibleKeys) {
        if (profile.containsKey(key) && profile[key] != null) {
          positionFromProfile = profile[key].toString();
          debugPrint('Найдена позиция по ключу "$key": $positionFromProfile');
          break;
        }
      }

      final serverZones =
          await _retryApiCall(() => _apiService.getAvailableZones(_token!));
      final serverTimeSlots =
          await _retryApiCall(() => _apiService.getAvailableTimeSlots(_token!));

      final uniqueZones = serverZones.toSet().toList();
      final defaultZone = uniqueZones.isNotEmpty ? uniqueZones.first : null;

      if (mounted) {
        setState(() {
          _zones = uniqueZones;
          _timeSlots = serverTimeSlots.toSet().toList(); // Убираем дубликаты
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
      if (mounted) {
        setState(() => _isLoading = false);
      }
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
    if (_isLoading) return; // Убираем проверку _hasActiveShift
    try {
      final image = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 800,
        imageQuality: 80,
      );
      if (image != null && mounted) {
        setState(() => _selfie = image);
      }
    } catch (e) {
      if (mounted) {
        _showError('Не удалось открыть камеру');
      }
    }
  }

  Future<void> _finish() async {
    if (_hasActiveShift) {
      // Если есть активная смена, заканчиваем её
      await _endShift();
    } else {
      // Если нет активной смены, начинаем новую
      await _startNewShift();
    }
  }

  Future<void> _startNewShift() async {
    if (_token == null) {
      _showError('Требуется авторизация');
      return;
    }
    if (_selectedTime == null) {
      _showError('Выберите время смены');
      return;
    }
    // Проверяем, можно ли начать смену в текущее время
    if (!_canStartShift(_selectedTime!)) {
      _showError(_getTimeRestrictionMessage(_selectedTime!));
      return;
    }
    if (_zone == null) {
      _showError('Нет доступных зон');
      return;
    }
    if (_selfie == null) {
      _showError('Сделайте селфи');
      return;
    }
    if (_position == null || _position!.isEmpty) {
      _showError(
          'Не удалось определить вашу должность. Обратитесь к администратору.');
      return;
    }

    final provider = Provider.of<ShiftProvider>(context, listen: false);
    try {
      final compressedFile = await _compressImage(File(_selfie!.path));
      debugPrint(
          'Отправка данных на сервер: slotTimeRange=$_selectedTime, position=$_position, zone=$_zone');

      await _retryApiCall(() => provider.startSlot(
            slotTimeRange: _selectedTime!,
            position: _position!,
            zone: _zone!,
            selfie: XFile(compressedFile.path),
          ));

      // После успешного начала смены обновляем состояние
      await provider
          .loadShifts(); // Используем существующий метод вместо refreshShiftData

      if (mounted) {
        Navigator.pop(context, true);
        _showSuccess('Смена успешно начата');
      }
    } on Exception catch (e) {
      if (mounted) {
        final errorMessage = e.toString().contains('502')
            ? 'Сервер временно недоступен (502). Пожалуйста, попробуйте позже.'
            : e.toString().contains('active')
                ? 'У вас уже есть активная смена'
                : 'Ошибка при старте смены: ${e.toString()}';
        _showError(errorMessage);
        if (e.toString().contains('active')) {
          setState(() => _backendConflict = true);
        }
      }
    }
  }

  Future<void> _endShift() async {
    if (_token == null) {
      _showError('Требуется авторизация');
      return;
    }

    try {
      final provider = Provider.of<ShiftProvider>(context, listen: false);
      await _retryApiCall(() => provider.endSlot());

      // После успешного завершения смены обновляем состояние
      await provider
          .loadShifts(); // Используем существующий метод вместо refreshShiftData

      if (mounted) {
        setState(() {
          _hasActiveShift = false;
          _backendConflict = false;
          _activeShift = null;
        });
        _showSuccess('Смена успешно завершена');
      }
    } catch (e) {
      if (mounted) {
        _showError('Ошибка при завершении смены: ${e.toString()}');
      }
    }
  }

  Future<File> _compressImage(File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    final original = img.decodeImage(bytes);
    if (original == null)
      throw Exception("Не удалось декодировать изображение");
    final oriented = img.bakeOrientation(original);
    final resized = img.copyResize(oriented, width: 800);
    final jpeg = img.encodeJpg(resized, quality: 80);
    final tempFile = File(
        '${imageFile.path}_compressed_${DateTime.now().millisecondsSinceEpoch}.jpg');
    return await tempFile.writeAsBytes(jpeg);
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showSuccess(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    return PopScope(
      canPop: !_isLoading,
      child: Container(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 24,
          right: 24,
          top: 24,
        ),
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
                      _hasActiveShift ? 'Активная смена' : 'Начать новую смену',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: isDarkMode ? Colors.white : Colors.green[800],
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    // Отображаем информацию об активной смене или форму для новой
                    if (_hasActiveShift)
                      _buildActiveShiftInfo()
                    else
                      _buildNewShiftForm(isDarkMode),
                    const SizedBox(height: 24),
                    _buildActionButton(),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildActiveShiftInfo() {
    if (_activeShift == null) return const SizedBox.shrink();
    return Column(
      children: [
        // Информация о активной смене
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.green[100],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.green[300]!),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Активная смена',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.green[800],
                ),
              ),
              const SizedBox(height: 8),
              if (_activeShift['slot_time_range'] != null)
                Text('Время: ${_activeShift['slot_time_range']}'),
              if (_activeShift['zone'] != null)
                Text('Зона: ${_activeShift['zone']}'),
              if (_activeShift['position'] != null)
                Text('Должность: ${_activeShift['position']}'),
              if (_activeShift['start_time'] != null)
                Text('Начало: ${_activeShift['start_time']}'),
              if (_activeShift['worked_duration'] != null)
                Text('Длительность: ${_activeShift['worked_duration']}'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNewShiftForm(bool isDarkMode) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_selfie != null)
          _buildSelfiePreview()
        else
          _buildSelfiePlaceholder(isDarkMode),
        _buildSelfieButton(isDarkMode),
        const SizedBox(height: 24),
        if (_timeSlots.isNotEmpty) _buildTimeSlotsSection(isDarkMode),
        const SizedBox(height: 24),
        if (_zones.isNotEmpty) _buildZoneDropdown(isDarkMode),
        const SizedBox(height: 24),
        TextFormField(
          initialValue: _position ?? 'Не указана',
          readOnly: true,
          decoration: InputDecoration(
            labelText: 'Должность',
            labelStyle: TextStyle(
                color: isDarkMode ? Colors.grey[400] : Colors.grey[600]),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                  color: isDarkMode ? Colors.grey[700]! : Colors.grey[400]!),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                  color: isDarkMode ? Colors.grey[700]! : Colors.grey[400]!),
            ),
            filled: true,
            fillColor: isDarkMode ? Colors.grey[800] : Colors.grey[100],
          ),
          style: TextStyle(
              color: isDarkMode ? Colors.white : Colors.black, fontSize: 16),
        ),
      ],
    );
  }

  Widget _buildSelfiePreview() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        children: [
          Image.file(
            File(_selfie!.path),
            height: 150,
            width: 150,
            fit: BoxFit.cover,
          ),
          Positioned(
            top: 8,
            right: 8,
            child: GestureDetector(
              onTap: () {
                if (mounted) {
                  setState(() => _selfie = null);
                }
              },
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                    color: Colors.red, shape: BoxShape.circle),
                child: const Icon(Icons.close, color: Colors.white, size: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelfiePlaceholder(bool isDarkMode) {
    return Container(
      height: 150,
      width: 150,
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.grey[800] : Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isDarkMode ? Colors.grey[700]! : Colors.grey[300]!,
            width: 2),
      ),
      child: Icon(Icons.person,
          size: 60, color: isDarkMode ? Colors.grey[600] : Colors.grey[400]),
    );
  }

  Widget _buildSelfieButton(bool isDarkMode) {
    return ElevatedButton.icon(
      onPressed: _isLoading ? null : _takeSelfie,
      icon: const Icon(Icons.camera_alt, color: Colors.white),
      label: const Text('Сделать селфи', style: TextStyle(color: Colors.white)),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.green[700],
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildTimeSlotsSection(bool isDarkMode) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Время смены',
          style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: isDarkMode ? Colors.white70 : Colors.black54),
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 3 / 1.5,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: _timeSlots.length,
          itemBuilder: (context, index) {
            final timeSlot = _timeSlots[index];
            final isSelected = _selectedTime == timeSlot;
            final canStart = _canStartShift(timeSlot);
            return Tooltip(
              message: canStart ? '' : _getTimeRestrictionMessage(timeSlot),
              child: ElevatedButton(
                onPressed: _isLoading || !canStart
                    ? null
                    : () {
                        if (mounted) {
                          setState(() => _selectedTime = timeSlot);
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: isSelected
                      ? Colors.green[700]
                      : !canStart
                          ? Colors.grey[400]
                          : isDarkMode
                              ? Colors.grey[800]
                              : Colors.white,
                  foregroundColor: isSelected
                      ? Colors.white
                      : isDarkMode
                          ? Colors.white
                          : Colors.black,
                  side: BorderSide(
                    color: isSelected
                        ? Colors.green[700]!
                        : isDarkMode
                            ? Colors.grey[700]!
                            : Colors.grey[300]!,
                    width: isSelected ? 2 : 1,
                  ),
                  padding: const EdgeInsets.all(12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: isSelected ? 4 : 1,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      timeSlot,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.normal),
                      textAlign: TextAlign.center,
                    ),
                    if (!canStart)
                      Icon(
                        Icons.lock,
                        size: 12,
                        color: isDarkMode ? Colors.grey[300] : Colors.grey[600],
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildZoneDropdown(bool isDarkMode) {
    final validZone = _zones.contains(_zone)
        ? _zone
        : (_zones.isNotEmpty ? _zones.first : null);
    return DropdownButtonFormField<String>(
      value: validZone,
      items: _zones.map((item) {
        return DropdownMenuItem(
          value: item,
          child: Text(item,
              style:
                  TextStyle(color: isDarkMode ? Colors.white : Colors.black)),
        );
      }).toList(),
      onChanged: _isLoading
          ? null
          : (String? value) {
              if (mounted && value != null) {
                setState(() => _zone = value);
              }
            },
      decoration: InputDecoration(
        labelText: 'Зона',
        labelStyle:
            TextStyle(color: isDarkMode ? Colors.grey[400] : Colors.grey[600]),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
              color: isDarkMode ? Colors.grey[700]! : Colors.grey[400]!),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
              color: isDarkMode ? Colors.grey[700]! : Colors.grey[400]!),
        ),
        filled: true,
        fillColor: isDarkMode ? Colors.grey[800] : Colors.grey[100],
      ),
      dropdownColor: isDarkMode ? Colors.grey[800] : Colors.white,
      style: TextStyle(
          color: isDarkMode ? Colors.white : Colors.black, fontSize: 16),
      icon: Icon(Icons.arrow_drop_down,
          color: isDarkMode ? Colors.grey[400] : Colors.grey[600]),
    );
  }

  Widget _buildActionButton() {
    // Проверяем, можно ли начать выбранную смену
    bool canStartSelectedShift =
        _selectedTime != null && _canStartShift(_selectedTime!);
    bool canSubmit = !_isLoading &&
        !_hasActiveShift &&
        _selectedTime != null &&
        _selfie != null &&
        _position != null &&
        _zone != null &&
        canStartSelectedShift;
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: (_hasActiveShift || canSubmit) ? _finish : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: _hasActiveShift
              ? Colors.red[700]
              : (canSubmit ? Colors.green[700] : Colors.grey[400]),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 2,
        ),
        child: _isLoading
            ? const CircularProgressIndicator(color: Colors.white)
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_hasActiveShift)
                    const Icon(Icons.stop, color: Colors.white),
                  if (!_hasActiveShift)
                    const Icon(Icons.play_arrow, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(
                    _hasActiveShift
                        ? 'Закончить смену'
                        : (canSubmit ? 'Начать смену' : 'Недоступно'),
                    style: const TextStyle(
                        fontSize: 16,
                        color: Colors.white,
                        fontWeight: FontWeight.bold),
                  ),
                ],
              ),
      ),
    );
  }
}
