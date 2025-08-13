import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:micro_mobility_app/models/shift_data.dart';
import 'package:provider/provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../providers/shift_provider.dart';
import '../../../services/api_service.dart';

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
  String _position = 'Курьер';
  String _zone = 'Центр';
  XFile? _selfie;
  bool _isLoading = false;
  bool _hasActiveShift = false;
  bool _backendConflict = false;
  List<String> _timeSlots = [];
  List<String> _positions = [];
  List<String> _zones = [];
  String? _token;
  Timer? _syncTimer;

  @override
  void initState() {
    super.initState();
    _initializeData();
    _startSyncTimer();
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    super.dispose();
  }

  void _startSyncTimer() {
    _syncTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) _syncWithServer();
    });
  }

  /// Инициализация: получаем токен и синхронизируем с сервером
  Future<void> _initializeData() async {
    setState(() => _isLoading = true);
    try {
      _token = await _storage.read(key: 'jwt_token');
      if (_token == null) throw Exception('Требуется авторизация');

      // Сначала синхронизируем с сервером
      await _syncWithServer();

      // Загружаем доступные опции
      await Future.wait([
        _loadTimeSlots(),
        _loadPositions(),
        _loadZones(),
      ]);
    } catch (e) {
      _showError('Ошибка инициализации: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 🔁 Принудительная синхронизация с сервером
  Future<void> _syncWithServer() async {
    try {
      final activeShift = await _apiService.getActiveShift(_token!);
      if (mounted) {
        setState(() {
          _hasActiveShift = activeShift != null;
          _backendConflict = false;
        });

        // Обновляем провайдер
        final provider = Provider.of<ShiftProvider>(context, listen: false);
        if (activeShift != null) {
          provider.setActiveShift(activeShift as ShiftData);
        } else {
          provider.clearActiveShift();
        }
      }
    } catch (e) {
      if (mounted && !e.toString().contains('404')) {
        setState(() => _backendConflict = true);
        _showError('Ошибка проверки смены: $e');
      }
    }
  }

  Future<void> _loadTimeSlots() async {
    try {
      final slots = await _apiService.getAvailableTimeSlots(_token!);
      if (mounted) setState(() => _timeSlots = slots);
    } catch (e) {
      if (mounted) {
        setState(() =>
            _timeSlots = ['7:00 - 15:00', '15:00 - 23:00', '7:00 - 23:00']);
      }
    }
  }

  Future<void> _loadPositions() async {
    try {
      final positions = await _apiService.getAvailablePositions(_token!);
      if (mounted) {
        setState(() {
          _positions = positions;
          if (positions.isNotEmpty) _position = positions.first;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _positions = ['Курьер', 'Оператор', 'Менеджер'];
          _position = _positions.first;
        });
      }
    }
  }

  Future<void> _loadZones() async {
    try {
      final zones = await _apiService.getAvailableZones(_token!);
      if (mounted) {
        setState(() {
          _zones = zones;
          if (zones.isNotEmpty) _zone = zones.first;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _zones = ['Центр', 'Север', 'Юг', 'Запад', 'Восток'];
          _zone = _zones.first;
        });
      }
    }
  }

  /// 📸 Сделать селфи
  Future<void> _takeSelfie() async {
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
      _showError('Ошибка камеры: ${e.toString()}');
    }
  }

  /// ✅ Завершить и начать смену
  Future<void> _finish() async {
    if (_token == null) {
      _showError('Требуется авторизация');
      return;
    }

    // ⚠️ Перед стартом — снова проверяем сервер
    await _syncWithServer();
    if (_hasActiveShift) {
      setState(() => _backendConflict = true);
      _showError('Смена уже активна на сервере');
      return;
    }

    if (_selectedTime == null || _selfie == null) {
      _showError('Заполните все поля');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final compressedFile = await _compressImage(File(_selfie!.path));
      await _startShift(compressedFile);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (e.toString().contains('active')) {
        setState(() => _backendConflict = true);
      }
      _showError('Не удалось начать смену: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 🖼️ Улучшенное сжатие с обработкой ориентации
  Future<File> _compressImage(File imageFile) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final original = img.decodeImage(bytes);
      if (original == null)
        throw Exception("Не удалось декодировать изображение");

      // Правильная ориентация по EXIF
      final oriented = img.bakeOrientation(original);
      // Масштабируем
      final resized = img.copyResize(oriented, width: 800);
      final jpeg = img.encodeJpg(resized, quality: 80);

      // Уникальное имя
      final tempFile = File(
          '${imageFile.path}_compressed_${DateTime.now().millisecondsSinceEpoch}.jpg');
      return await tempFile.writeAsBytes(jpeg);
    } catch (e) {
      throw Exception("Ошибка сжатия: ${e.toString()}");
    }
  }

  /// 🚀 Запуск смены через провайдер
  Future<void> _startShift(File compressedFile) async {
    try {
      final provider = Provider.of<ShiftProvider>(context, listen: false);
      await provider.startSlot(
        slotTimeRange: _selectedTime!,
        position: _position,
        zone: _zone,
        selfie: XFile(compressedFile.path),
      );
      setState(() => _hasActiveShift = true);
    } catch (e) {
      if (e.toString().contains('active')) {
        setState(() => _backendConflict = true);
        await _syncWithServer(); // Обновляем состояние
      }
      rethrow;
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    final isBlocked = _hasActiveShift || _backendConflict;

    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 16,
      ),
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.grey[900] : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: _isLoading && _timeSlots.isEmpty
          ? _buildLoadingIndicator()
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Начать новую смену',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: isDarkMode ? Colors.white : Colors.green[800],
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (_selfie != null) _buildSelfiePreview(),
                  _buildSelfieButton(isDarkMode, isBlocked),
                  const SizedBox(height: 24),
                  ..._buildTimeSlots(isDarkMode, isBlocked),
                  const SizedBox(height: 24),
                  _buildPositionDropdown(isDarkMode, isBlocked),
                  const SizedBox(height: 16),
                  _buildZoneDropdown(isDarkMode, isBlocked),
                  const SizedBox(height: 24),
                  _buildSubmitButton(),
                  if (_backendConflict) _buildConflictWarning(),
                ],
              ),
            ),
    );
  }

  Widget _buildConflictWarning() {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        color: Colors.orange[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.warning, color: Colors.orange[800]),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Обнаружен конфликт состояний. Попробуйте обновить данные.',
              style: TextStyle(color: Colors.orange[800]),
            ),
          ),
          IconButton(
            icon: Icon(Icons.refresh, color: Colors.orange[800]),
            onPressed: _initializeData,
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingIndicator() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: CircularProgressIndicator(),
      ),
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
              onTap: () => setState(() => _selfie = null),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, color: Colors.white, size: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelfieButton(bool isDarkMode, bool isBlocked) {
    return ElevatedButton.icon(
      onPressed: isBlocked || _isLoading ? null : _takeSelfie,
      icon: const Icon(Icons.camera_alt, color: Colors.white),
      label: const Text(
        'Сделать селфи',
        style: TextStyle(color: Colors.white),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: isBlocked ? Colors.grey : Colors.green[700],
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  List<Widget> _buildTimeSlots(bool isDarkMode, bool isBlocked) {
    return _timeSlots.map((slot) {
      final isSelected = _selectedTime == slot;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: InkWell(
          onTap: isBlocked || _isLoading
              ? null
              : () => setState(() => _selectedTime = slot),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: isSelected
                  ? Colors.green[100]
                  : isDarkMode
                      ? Colors.grey[800]
                      : Colors.grey[100],
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected ? Colors.green : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Center(
              child: Text(
                slot,
                style: TextStyle(
                  fontSize: 16,
                  color: isSelected
                      ? Colors.green[800]
                      : isDarkMode
                          ? Colors.white
                          : Colors.black,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      );
    }).toList();
  }

  Widget _buildPositionDropdown(bool isDarkMode, bool isBlocked) {
    return DropdownButtonFormField<String>(
      value: _position,
      items: _positions.map((item) {
        return DropdownMenuItem(
          value: item,
          child: Text(
            item,
            style: TextStyle(
              color: isDarkMode ? Colors.white : Colors.black,
            ),
          ),
        );
      }).toList(),
      onChanged: isBlocked || _isLoading
          ? null
          : (String? value) => setState(() => _position = value!),
      decoration: InputDecoration(
        labelText: 'Должность',
        labelStyle: TextStyle(
          color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: isDarkMode ? Colors.grey[700]! : Colors.grey[400]!,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: isDarkMode ? Colors.grey[700]! : Colors.grey[400]!,
          ),
        ),
        filled: true,
        fillColor: isDarkMode ? Colors.grey[800] : Colors.grey[100],
      ),
      dropdownColor: isDarkMode ? Colors.grey[800] : Colors.white,
      style: TextStyle(
        color: isDarkMode ? Colors.white : Colors.black,
        fontSize: 16,
      ),
      icon: Icon(
        Icons.arrow_drop_down,
        color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
      ),
    );
  }

  Widget _buildZoneDropdown(bool isDarkMode, bool isBlocked) {
    return DropdownButtonFormField<String>(
      value: _zone,
      items: _zones.map((item) {
        return DropdownMenuItem(
          value: item,
          child: Text(
            item,
            style: TextStyle(
              color: isDarkMode ? Colors.white : Colors.black,
            ),
          ),
        );
      }).toList(),
      onChanged: isBlocked || _isLoading
          ? null
          : (String? value) => setState(() => _zone = value!),
      decoration: InputDecoration(
        labelText: 'Зона',
        labelStyle: TextStyle(
          color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: isDarkMode ? Colors.grey[700]! : Colors.grey[400]!,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: isDarkMode ? Colors.grey[700]! : Colors.grey[400]!,
          ),
        ),
        filled: true,
        fillColor: isDarkMode ? Colors.grey[800] : Colors.grey[100],
      ),
      dropdownColor: isDarkMode ? Colors.grey[800] : Colors.white,
      style: TextStyle(
        color: isDarkMode ? Colors.white : Colors.black,
        fontSize: 16,
      ),
      icon: Icon(
        Icons.arrow_drop_down,
        color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
      ),
    );
  }

  Widget _buildSubmitButton() {
    final isBlocked = _hasActiveShift || _backendConflict;
    final isDisabled =
        isBlocked || _isLoading || _selectedTime == null || _selfie == null;

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: isDisabled ? null : _finish,
        style: ElevatedButton.styleFrom(
          backgroundColor: isBlocked ? Colors.grey : Colors.green[700],
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: _isLoading
            ? const CircularProgressIndicator(color: Colors.white)
            : Text(
                isBlocked ? 'Смена уже активна' : 'Начать смену',
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }
}
