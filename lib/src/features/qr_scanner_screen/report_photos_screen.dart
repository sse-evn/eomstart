import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'dart:ui' as ui;
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

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Stack(
        children: [
          // Glass effect background
          Positioned.fill(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                decoration: BoxDecoration(
                  color: _colors.primaryContainer.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: _colors.primary.withOpacity(0.2),
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _colors.primary.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.person_outline_rounded,
                          color: _colors.onPrimaryContainer, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.employeeName,
                            style: _theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: _colors.onPrimaryContainer,
                              letterSpacing: -0.5,
                            ),
                          ),
                          if (username.isNotEmpty)
                            Text(
                              '@$username',
                              style: _theme.textTheme.bodyMedium?.copyWith(
                                color: _colors.onPrimaryContainer.withOpacity(0.7),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(height: 32, thickness: 0.5),
                Row(
                  children: [
                    Icon(Icons.electric_scooter,
                        color: _colors.onPrimaryContainer.withOpacity(0.6), size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.scooterNumbers.isEmpty
                            ? 'Самокаты не выбраны'
                            : 'Самокаты: ${widget.scooterNumbers.join(', ')}',
                        style: _theme.textTheme.bodyMedium?.copyWith(
                          color: _colors.onPrimaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
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
        borderRadius: BorderRadius.circular(20),
        onTap: _sending ? null : () => setState(() => _reportType = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            gradient: selected
                ? LinearGradient(
                    colors: [Colors.green[700]!, Colors.green[500]!],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: selected ? null : _colors.surfaceContainerHighest.withOpacity(0.5),
            borderRadius: BorderRadius.circular(20),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.green.withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    )
                  ]
                : null,
            border: Border.all(
              color: selected ? Colors.transparent : _colors.outlineVariant,
              width: 1.5,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 28,
                color: selected ? Colors.white : _colors.onSurfaceVariant,
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: _theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: selected ? Colors.white : _colors.onSurface,
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
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _colors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _colors.outlineVariant.withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: _colors.shadow.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.photo_library_rounded, color: Colors.green[700]),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '$reportTitle (${_photos.length}/10)',
                  style: _theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: _colors.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _actionButton(
                  onPressed: _sending ? null : _takePhoto,
                  icon: Icons.camera_alt_rounded,
                  label: 'Камера',
                  isPrimary: true,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _actionButton(
                  onPressed: _sending ? null : _pickImages,
                  icon: Icons.image_rounded,
                  label: 'Галерея',
                  isPrimary: false,
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
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Image.file(
                _photos[index],
                fit: BoxFit.cover,
              ),
            ),
          ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: GestureDetector(
            onTap: _sending ? null : () => _removePhoto(index),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.9),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 4,
                  ),
                ],
              ),
              child: const Icon(Icons.close, color: Colors.white, size: 16),
            ),
          ),
        ),
        Positioned(
          bottom: 8,
          left: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.6),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${index + 1}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _actionButton({
    required VoidCallback? onPressed,
    required IconData icon,
    required String label,
    required bool isPrimary,
  }) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 54,
        decoration: BoxDecoration(
          color: isPrimary ? Colors.green[700] : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: isPrimary ? null : Border.all(color: _colors.outlineVariant),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: isPrimary ? Colors.white : _colors.onSurface, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isPrimary ? Colors.white : _colors.onSurface,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
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
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                child: InkWell(
                  onTap: _sending ? null : _sendReport,
                  borderRadius: BorderRadius.circular(22),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    height: 64,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      gradient: _sending
                          ? LinearGradient(colors: [Colors.grey[700]!, Colors.grey[600]!])
                          : LinearGradient(
                              colors: [Colors.green[700]!, Colors.green[500]!],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: (_sending ? Colors.grey : Colors.green).withOpacity(0.3),
                          blurRadius: 15,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Center(
                      child: _sending
                          ? const CircularProgressIndicator(color: Colors.white)
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.send_rounded, color: Colors.white),
                                const SizedBox(width: 12),
                                Text(
                                  'Отправить отчёт',
                                  style: _theme.textTheme.titleMedium?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
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
