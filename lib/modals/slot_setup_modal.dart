// lib/modals/slot_setup_modal.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../providers/shift_provider.dart';
import '../../services/api_service.dart';

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
  List<String> _positions = [];
  List<String> _zones = [];
  String? _token;

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _initializeData() async {
    if (!mounted) return;

    setState(() => _isLoading = true);

    try {
      _token = await _storage.read(key: 'jwt_token');
      if (_token == null) throw Exception('Требуется авторизация');

      final profile = await _apiService.getUserProfile(_token!);
      final serverPositions = await _apiService.getAvailablePositions(_token!);
      final serverZones = await _apiService.getAvailableZones(_token!);
      final serverTimeSlots = await _apiService.getAvailableTimeSlots(_token!);

      if (mounted) {
        setState(() {
          _positions = serverPositions;
          _zones = serverZones;
          _timeSlots = serverTimeSlots.isNotEmpty
              ? List<String>.from(serverTimeSlots)
              : ['07:00 - 15:00', '15:00 - 23:00'];

          // ✅ Берём из профиля, если есть
          _position = profile['position'] as String? ??
              (_positions.isNotEmpty ? _positions.first : null);
          _zone = profile['zone'] as String? ??
              (_zones.isNotEmpty ? _zones.first : null);
          _selectedTime = _timeSlots.isNotEmpty ? _timeSlots.first : null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          // ❌ Резервные значения только если сервер недоступен
          _positions = ['Оператор', 'Менеджер', 'Скаут'];
          _zones = ['Центр', 'Север', 'Юг', 'Запад', 'Восток'];
          _timeSlots = ['07:00 - 15:00', '15:00 - 23:00'];
          _position = _positions.first;
          _zone = _zones.first;
          _selectedTime = _timeSlots.first;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _takeSelfie() async {
    if (_isLoading) return;
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось открыть камеру')),
        );
      }
    }
  }

  Future<void> _finish() async {
    if (_token == null) {
      _showError('Требуется авторизация');
      return;
    }

    if (_selectedTime == null) {
      _showError('Выберите время смены');
      return;
    }

    if (_position == null) {
      _showError('Выберите должность');
      return;
    }

    if (_zone == null) {
      _showError('Выберите зону');
      return;
    }

    if (_selfie == null) {
      _showError('Сделайте селфи');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final compressedFile = await _compressImage(File(_selfie!.path));
      final provider = Provider.of<ShiftProvider>(context, listen: false);
      await provider.startSlot(
        slotTimeRange: _selectedTime!,
        position: _position!,
        zone: _zone!,
        selfie: XFile(compressedFile.path),
      );

      if (mounted) {
        Navigator.pop(context, true);
        _showSuccess('Смена успешно начата');
      }
    } on Exception catch (e) {
      if (mounted) {
        if (e.toString().contains('active')) {
          _showError('У вас уже есть активная смена');
        } else {
          _showError('Ошибка: ${e.toString()}');
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
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
    final hasActiveShift = _hasActiveShift || _backendConflict;

    return Container(
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
      child: _isLoading && _timeSlots.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Начать новую смену',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: isDarkMode ? Colors.white : Colors.green[800],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  if (_selfie != null)
                    _buildSelfiePreview()
                  else
                    _buildSelfiePlaceholder(isDarkMode),
                  _buildSelfieButton(isDarkMode, hasActiveShift),
                  const SizedBox(height: 24),
                  _buildTimeSlotsSection(isDarkMode, hasActiveShift),
                  const SizedBox(height: 24),
                  if (_zones.isNotEmpty)
                    _buildZoneDropdown(isDarkMode, hasActiveShift),
                  const SizedBox(height: 24),
                  if (_positions.isNotEmpty)
                    _buildPositionDropdown(isDarkMode, hasActiveShift),
                  const SizedBox(height: 24),
                  _buildSubmitButton(hasActiveShift),
                ],
              ),
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
              onTap: () {
                if (mounted) {
                  setState(() => _selfie = null);
                }
              },
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

  Widget _buildSelfiePlaceholder(bool isDarkMode) {
    return Container(
      height: 150,
      width: 150,
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.grey[800] : Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDarkMode ? Colors.grey[700]! : Colors.grey[300]!,
          width: 2,
        ),
      ),
      child: Icon(
        Icons.person,
        size: 60,
        color: isDarkMode ? Colors.grey[600] : Colors.grey[400],
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

  Widget _buildTimeSlotsSection(bool isDarkMode, bool isBlocked) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Время смены',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: isDarkMode ? Colors.white70 : Colors.black54,
          ),
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

            return ElevatedButton(
              onPressed: isBlocked || _isLoading
                  ? null
                  : () {
                      if (mounted) {
                        setState(() => _selectedTime = timeSlot);
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: isSelected
                    ? Colors.green[700]
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
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: isSelected ? 4 : 1,
              ),
              child: Text(
                timeSlot,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
                textAlign: TextAlign.center,
              ),
            );
          },
        ),
      ],
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
          : (String? value) {
              if (mounted && value != null) {
                setState(() => _zone = value);
              }
            },
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
          : (String? value) {
              if (mounted && value != null) {
                setState(() => _position = value);
              }
            },
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

  Widget _buildSubmitButton(bool isBlocked) {
    final isDisabled = isBlocked ||
        _isLoading ||
        _selectedTime == null ||
        _selfie == null ||
        _position == null ||
        _zone == null;

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
          elevation: 2,
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
