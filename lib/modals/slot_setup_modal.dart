// lib/screens/dashboard/modals/slot_setup_modal.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../../providers/shift_provider.dart';

class SlotSetupModal extends StatefulWidget {
  const SlotSetupModal({super.key});

  @override
  State<SlotSetupModal> createState() => _SlotSetupModalState();
}

class _SlotSetupModalState extends State<SlotSetupModal> {
  String? _selectedTime;
  String? _position = 'Курьер';
  String? _zone = 'Центр';
  XFile? _selfie;
  bool _isLoading = false; // ✅ ДОБАВЛЕНО: Состояние загрузки для кнопки

  Future<void> _takeSelfie() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.camera);
    if (image != null) {
      setState(() => _selfie = image);
    }
  }

  // Сжатие фото
  Future<File> _compressImage(File imageFile) async {
    final bytes = imageFile.readAsBytesSync();
    final original = img.decodeImage(bytes);
    if (original == null) {
      throw Exception("Could not decode image.");
    }
    final resized = img.copyResize(original, width: 800);
    final jpeg = img.encodeJpg(resized, quality: 80);
    return await imageFile.writeAsBytes(jpeg);
  }

  void _finish() async {
    // ✅ ИСПРАВЛЕНИЕ: Проверяем, активен ли слот ПЕРЕД попыткой его начать
    if (context.read<ShiftProvider>().slotState == SlotState.active) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('У вас уже есть активный слот.')));
      Navigator.pop(context); // Закрываем модальное окно
      return;
    }

    if (_selectedTime == null ||
        _position == null ||
        _zone == null ||
        _selfie == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Заполните все поля')));
      return;
    }

    // ✅ ДОБАВЛЕНО: Устанавливаем состояние загрузки и перестраиваем UI
    setState(() {
      _isLoading = true;
    });

    try {
      final File compressedFile = await _compressImage(File(_selfie!.path));
      final XFile compressedXFile = XFile(compressedFile.path);

      await context.read<ShiftProvider>().startSlot(
            slotTimeRange: _selectedTime!,
            position: _position!,
            zone: _zone!,
            selfie: compressedXFile,
          );

      // ✅ ДОБАВЛЕНО: Проверяем, что виджет все еще в дереве, прежде чем закрывать модальное окно
      if (mounted) {
        Navigator.pop(
            context); // Закрываем модальное окно после успешного старта
      }
    } catch (e) {
      // ✅ ДОБАВЛЕНО: Проверяем, что виджет все еще в дереве, прежде чем показывать SnackBar
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      }
    } finally {
      // ✅ ДОБАВЛЕНО: Убедитесь, что состояние загрузки сброшено, даже если произошла ошибка
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // ✅ ИСПРАВЛЕНИЕ: Используем Consumer для прослушивания изменений ShiftProvider
    return Consumer<ShiftProvider>(
      builder: (context, shiftProvider, child) {
        final bool isSlotActive = shiftProvider.slotState == SlotState.active;
        // ✅ ДОБАВЛЕНО: Объединяем состояние активности слота и состояния загрузки
        final bool isButtonDisabled = isSlotActive || _isLoading;

        return Container(
          height: 500,
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Начать слот',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                if (_selfie != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(File(_selfie!.path),
                        height: 120, width: 120, fit: BoxFit.cover),
                  ),
                const SizedBox(height: 20),
                // Отключаем кнопку "Сделать селфи", если слот активен ИЛИ идет загрузка
                TextButton.icon(
                  onPressed: isButtonDisabled ? null : _takeSelfie,
                  icon: const Icon(Icons.camera),
                  label: const Text('Сделать селфи'),
                ),
                const SizedBox(height: 20),
                // Отключаем кнопки выбора времени, если слот активен ИЛИ идет загрузка
                _button(
                    '7:00 - 15:00',
                    _selectedTime == '7:00 - 15:00',
                    isButtonDisabled
                        ? () {}
                        : () => setState(() => _selectedTime = '7:00 - 15:00')),
                _button(
                    '15:00 - 23:00',
                    _selectedTime == '15:00 - 23:00',
                    isButtonDisabled
                        ? () {}
                        : () =>
                            setState(() => _selectedTime = '15:00 - 23:00')),
                _button(
                    '7:00 - 23:00',
                    _selectedTime == '7:00 - 23:00',
                    isButtonDisabled
                        ? () {}
                        : () => setState(() => _selectedTime = '7:00 - 23:00')),
                const SizedBox(height: 30),
                // ✅ ИСПРАВЛЕНИЕ: Отключаем кнопку "Начать", если слот активен ИЛИ идет загрузка
                ElevatedButton(
                  onPressed:
                      isButtonDisabled ? null : _finish, // Отключаем кнопку
                  style: ElevatedButton.styleFrom(
                      backgroundColor: isButtonDisabled
                          ? Colors.grey
                          : Colors
                              .green[700], // Меняем цвет для отключенной кнопки
                      padding: const EdgeInsets.symmetric(vertical: 16)),
                  child: Text(
                      // ✅ ИЗМЕНЕНО: Текст кнопки меняется в зависимости от состояния
                      _isLoading
                          ? 'Запуск...'
                          : (isSlotActive ? 'Слот уже активен' : 'Начать'),
                      style: const TextStyle(
                          fontSize: 16,
                          color: Colors
                              .white)), // Устанавливаем цвет текста, чтобы он был виден на сером фоне
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _button(String text, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        margin: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.green[700] : Colors.grey[200],
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: selected ? Colors.green[700]! : Colors.transparent),
        ),
        child: Center(
          child: Text(text,
              style: TextStyle(
                  color: selected ? Colors.white : Colors.black,
                  fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }
}
