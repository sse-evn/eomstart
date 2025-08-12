import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../../providers/shift_provider.dart';
import '../../../models/active_shift.dart';

class SlotSetupModal extends StatefulWidget {
  const SlotSetupModal({super.key});

  @override
  State<SlotSetupModal> createState() => _SlotSetupModalState();
}

class _SlotSetupModalState extends State<SlotSetupModal> {
  String? _selectedTime;
  String _position = 'Курьер';
  String _zone = 'Центр';
  XFile? _selfie;
  bool _isLoading = false;
  bool _hasActiveShift = false;

  @override
  void initState() {
    super.initState();
    _checkActiveShift();
  }

  Future<void> _checkActiveShift() async {
    try {
      final provider = context.read<ShiftProvider>();
      await provider.loadShifts();
      if (mounted) {
        setState(() {
          _hasActiveShift = provider.slotState == SlotState.active;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка проверки смены: $e')),
        );
      }
    }
  }

  Future<void> _takeSelfie() async {
    try {
      final image = await ImagePicker().pickImage(source: ImageSource.camera);
      if (image != null && mounted) {
        setState(() => _selfie = image);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка камеры: $e')),
        );
      }
    }
  }

  Future<File> _compressImage(File imageFile) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final original = img.decodeImage(bytes);
      if (original == null)
        throw Exception("Не удалось обработать изображение");

      final resized = img.copyResize(original, width: 800);
      final jpeg = img.encodeJpg(resized, quality: 80);
      final tempFile = File('${imageFile.path}_compressed.jpg');
      return await tempFile.writeAsBytes(jpeg);
    } catch (e) {
      throw Exception("Ошибка сжатия: $e");
    }
  }

  Future<void> _finish() async {
    if (_hasActiveShift) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('У вас уже есть активная смена')),
      );
      return;
    }

    if (_selectedTime == null || _selfie == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Заполните все поля')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final compressedFile = await _compressImage(File(_selfie!.path));
      final compressedXFile = XFile(compressedFile.path);

      await context.read<ShiftProvider>().startSlot(
            slotTimeRange: _selectedTime!,
            position: _position,
            zone: _zone,
            selfie: compressedXFile,
          );

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Начать новую смену',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              if (_selfie != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(
                    File(_selfie!.path),
                    height: 120,
                    width: 120,
                    fit: BoxFit.cover,
                  ),
                ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _hasActiveShift || _isLoading ? null : _takeSelfie,
                icon: const Icon(Icons.camera_alt),
                label: const Text('Сделать селфи'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[700],
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
              const SizedBox(height: 24),
              ..._buildTimeSlots(),
              const SizedBox(height: 24),
              _buildDropdown(
                value: _position,
                items: ['Курьер', 'Оператор', 'Менеджер'],
                onChanged: (v) => setState(() => _position = v!),
                hint: 'Должность',
              ),
              const SizedBox(height: 16),
              _buildDropdown(
                value: _zone,
                items: ['Центр', 'Север', 'Юг', 'Запад', 'Восток'],
                onChanged: (v) => setState(() => _zone = v!),
                hint: 'Зона',
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _hasActiveShift ||
                          _isLoading ||
                          _selectedTime == null ||
                          _selfie == null
                      ? null
                      : _finish,
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        _hasActiveShift ? Colors.grey : Colors.green[700],
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(
                          _hasActiveShift
                              ? 'Смена уже активна'
                              : 'Начать смену',
                          style: const TextStyle(fontSize: 16),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildTimeSlots() {
    const slots = [
      '7:00 - 15:00',
      '15:00 - 23:00',
      '7:00 - 23:00',
    ];

    return slots.map((slot) {
      final isSelected = _selectedTime == slot;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: InkWell(
          onTap: _hasActiveShift || _isLoading
              ? null
              : () => setState(() => _selectedTime = slot),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: isSelected ? Colors.green[100] : Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected ? Colors.green : Colors.transparent,
              ),
            ),
            child: Center(
              child: Text(
                slot,
                style: TextStyle(
                  color: isSelected ? Colors.green[800] : Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      );
    }).toList();
  }

  Widget _buildDropdown({
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
    required String hint,
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      items: items.map((item) {
        return DropdownMenuItem(
          value: item,
          child: Text(item),
        );
      }).toList(),
      onChanged: _hasActiveShift || _isLoading ? null : onChanged,
      decoration: InputDecoration(
        labelText: hint,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}
