import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:micro_mobility_app/src/core/config/app_config.dart';

class ReportPhotosScreen extends StatefulWidget {
  final List<String> scooterNumbers;
  final String employeeName;
  final String? employeeUsername;
  final int? employeeTelegramId;

  const ReportPhotosScreen({
    super.key,
    required this.scooterNumbers,
    required this.employeeName,
    this.employeeUsername,
    this.employeeTelegramId,
  });

  @override
  State<ReportPhotosScreen> createState() => _ReportPhotosScreenState();
}

class _ReportPhotosScreenState extends State<ReportPhotosScreen> {
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _commentController = TextEditingController();

  String _reportType = 'before';
  final List<File> _photos = [];
  bool _sending = false;

  ThemeData get _theme => Theme.of(context);
  ColorScheme get _colors => _theme.colorScheme;

  Future<void> _pickImages() async {
    if (_photos.length >= 10) {
      _showMessage('Можно максимум 10 фото');
      return;
    }

    final picked = await _picker.pickMultiImage(imageQuality: 80);

    if (picked.isEmpty) return;

    final remain = 10 - _photos.length;
    final toAdd = picked.take(remain).map((e) => File(e.path)).toList();

    setState(() {
      _photos.addAll(toAdd);
    });

    if (picked.length > remain) {
      _showMessage('Добавлены только первые 10 фото');
    }
  }

  Future<void> _takePhoto() async {
    if (_photos.length >= 10) {
      _showMessage('Можно максимум 10 фото');
      return;
    }

    final photo = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
    );

    if (photo == null) return;

    setState(() {
      _photos.add(File(photo.path));
    });
  }

  void _removePhoto(int index) {
    setState(() {
      _photos.removeAt(index);
    });
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _sendReport() async {
    if (_photos.isEmpty) {
      _showMessage('Добавь хотя бы одно фото');
      return;
    }

    setState(() => _sending = true);

    try {
      final uri = Uri.parse(AppConfig.reportUploadUrl);
      final request = http.MultipartRequest('POST', uri);

      request.headers['X-Report-Token'] = AppConfig.reportApiToken;
      request.fields['report_type'] = _reportType;
      request.fields['comment'] = _commentController.text.trim();
      request.fields['scooters'] = jsonEncode(widget.scooterNumbers);
      request.fields['employee_name'] = widget.employeeName;

      if (widget.employeeUsername != null &&
          widget.employeeUsername!.trim().isNotEmpty) {
        request.fields['employee_username'] = widget.employeeUsername!.trim();
      }

      if (widget.employeeTelegramId != null) {
        request.fields['employee_telegram_id'] =
            widget.employeeTelegramId.toString();
      }

      for (final file in _photos) {
        request.files.add(
          await http.MultipartFile.fromPath(
            'photos',
            file.path,
            contentType: MediaType('image', 'jpeg'),
          ),
        );
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (!mounted) return;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        _showMessage('Отчёт отправлен');
        Navigator.of(context).pop(true);
      } else {
        _showMessage('Ошибка ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      _showMessage('Ошибка отправки: $e');
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: _theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w800,
          color: _colors.onSurface,
        ),
      ),
    );
  }

  Widget _infoCard() {
    final username = widget.employeeUsername?.trim() ?? '';
    final telegramId = widget.employeeTelegramId?.toString() ?? '';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _colors.primaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.assignment_rounded, color: _colors.onPrimaryContainer),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Новый отчёт',
                  style: _theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: _colors.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Кто отправляет: ${widget.employeeName}',
            style: _theme.textTheme.bodyLarge?.copyWith(
              color: _colors.onPrimaryContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (username.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Логин: @$username',
              style: _theme.textTheme.bodyMedium?.copyWith(
                color: _colors.onPrimaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (telegramId.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Telegram ID: $telegramId',
              style: _theme.textTheme.bodyMedium?.copyWith(
                color: _colors.onPrimaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            widget.scooterNumbers.isEmpty
                ? 'Самокаты не выбраны'
                : 'Самокаты: ${widget.scooterNumbers.join(', ')}',
            style: _theme.textTheme.bodyLarge?.copyWith(
              color: _colors.onPrimaryContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeButton({
    required String value,
    required String title,
    required IconData icon,
  }) {
    final selected = _reportType == value;

    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: _sending ? null : () => setState(() => _reportType = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
          decoration: BoxDecoration(
            color: selected
                ? _colors.primaryContainer
                : _colors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? _colors.primary : _colors.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 30,
                color: selected ? _colors.primary : _colors.onSurfaceVariant,
              ),
              const SizedBox(height: 10),
              Text(
                title,
                style: _theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: selected ? _colors.primary : _colors.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _photoCard() {
    final reportTitle = _reportType == 'before' ? 'Фото ДО' : 'Фото ПОСЛЕ';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.collections_rounded, color: _colors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '$reportTitle (${_photos.length}/10)',
                  style: _theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: _colors.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _sending ? null : _takePhoto,
                  icon: const Icon(Icons.camera_alt_rounded),
                  label: const Text('Камера'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(54),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _sending ? null : _pickImages,
                  icon: const Icon(Icons.photo_library_rounded),
                  label: const Text('Галерея'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(54),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_photos.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _colors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _colors.outlineVariant),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.image_not_supported_outlined,
                    size: 34,
                    color: _colors.onSurfaceVariant,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Фото пока не добавлены',
                    textAlign: TextAlign.center,
                    style: _theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: _colors.onSurface,
                    ),
                  ),
                ],
              ),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _photos.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1,
              ),
              itemBuilder: (context, index) => _buildPhotoTile(index),
            ),
        ],
      ),
    );
  }

  Widget _buildPhotoTile(int index) {
    return Stack(
      children: [
        Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.file(
              _photos[index],
              fit: BoxFit.cover,
            ),
          ),
        ),
        Positioned(
          left: 8,
          bottom: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: _colors.scrim.withOpacity(0.72),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '${index + 1}',
              style: _theme.textTheme.bodyMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        Positioned(
          top: 6,
          right: 6,
          child: Material(
            color: _colors.scrim.withOpacity(0.72),
            borderRadius: BorderRadius.circular(30),
            child: InkWell(
              borderRadius: BorderRadius.circular(30),
              onTap: _sending ? null : () => _removePhoto(index),
              child: const Padding(
                padding: EdgeInsets.all(7),
                child: Icon(
                  Icons.close,
                  color: Colors.white,
                  size: 18,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _commentField() {
    return TextField(
      controller: _commentController,
      maxLines: 5,
      enabled: !_sending,
      style: TextStyle(color: _colors.onSurface),
      decoration: InputDecoration(
        hintText: 'Например: грязный, разбито крыло, нужна замена',
        hintStyle: TextStyle(color: _colors.onSurfaceVariant),
        filled: true,
        fillColor: _colors.surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: _colors.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: _colors.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: _colors.primary,
            width: 2,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Фотоотчёт'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                children: [
                  _infoCard(),
                  const SizedBox(height: 18),
                  _sectionTitle('Тип отчёта'),
                  Row(
                    children: [
                      _buildTypeButton(
                        value: 'before',
                        title: 'До',
                        icon: Icons.photo_camera_back_outlined,
                      ),
                      const SizedBox(width: 12),
                      _buildTypeButton(
                        value: 'after',
                        title: 'После',
                        icon: Icons.task_alt_rounded,
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _photoCard(),
                  const SizedBox(height: 18),
                  _sectionTitle('Комментарий'),
                  _commentField(),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _sending ? null : _sendReport,
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded),
                    label: Text(_sending ? 'Отправка...' : 'Отправить отчёт'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(58),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
