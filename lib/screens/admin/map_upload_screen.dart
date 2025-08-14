// lib/screens/admin/map_upload_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class MapUploadScreen extends StatefulWidget {
  final Function(File) onGeoJsonLoaded;

  const MapUploadScreen({super.key, required this.onGeoJsonLoaded});

  @override
  State<MapUploadScreen> createState() => _MapUploadScreenState();
}

class _MapUploadScreenState extends State<MapUploadScreen> {
  File? _uploadedGeoJson;
  bool _isLoading = false;
  bool _isUploading = false;
  List<dynamic> _uploadedMaps = [];
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final TextEditingController _cityController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadUploadedMaps();
  }

  Future<void> _loadUploadedMaps() async {
    setState(() => _isLoading = true);
    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token != null) {
        final response = await http.get(
          Uri.parse('https://eom-sharing.duckdns.org/api/admin/maps'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        );

        if (response.statusCode == 200) {
          final dynamic body = jsonDecode(response.body);
          if (body is List) {
            setState(() {
              _uploadedMaps = body;
            });
          }
        } else {
          throw Exception('Ошибка загрузки: ${response.statusCode}');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка загрузки списка карт: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _pickGeoJson() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['geojson', 'json'],
      );

      if (result != null) {
        final pickedFile = File(result.files.single.path!);
        final fileStat = pickedFile.statSync();
        final fileSizeMB = fileStat.size / (1024 * 1024);

        // Проверка размера файла (максимум 40 МБ)
        if (fileSizeMB > 40) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content:
                    Text('Файл слишком большой. Максимальный размер: 40 МБ'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }

        setState(() {
          _uploadedGeoJson = pickedFile;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Файл выбран: ${result.files.single.name} (${fileSizeMB.toStringAsFixed(1)} МБ)'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка выбора файла: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _uploadMapToServer() async {
    if (_uploadedGeoJson == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Сначала выберите файл'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_cityController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Укажите город'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isUploading = true);

    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token != null) {
        final request = http.MultipartRequest(
          'POST',
          Uri.parse('https://eom-sharing.duckdns.org/api/admin/maps/upload'),
        );

        request.headers['Authorization'] = 'Bearer $token';
        request.fields['city'] = _cityController.text.trim();
        request.fields['description'] = _descriptionController.text.trim();

        final file = await http.MultipartFile.fromPath(
          'geojson_file',
          _uploadedGeoJson!.path,
          filename: _uploadedGeoJson!.path.split('/').last,
        );
        request.files.add(file);

        final response = await request.send();
        final resp = await http.Response.fromStream(response);

        if (resp.statusCode == 200 || resp.statusCode == 201) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Карта успешно загружена на сервер'),
                backgroundColor: Colors.green,
              ),
            );

            // Очищаем форму
            _clearForm();
            // Обновляем список карт
            await _loadUploadedMaps();
          }
        } else {
          throw Exception(
              'Ошибка загрузки: ${resp.statusCode} - ${resp.reasonPhrase}');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка загрузки на сервер: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  Future<void> _deleteMap(int mapId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить карту?'),
        content: const Text('Вы уверены, что хотите удалить эту карту?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Удалить',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);

    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token != null) {
        final response = await http.delete(
          Uri.parse('https://eom-sharing.duckdns.org/api/admin/maps/$mapId'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        );

        if (response.statusCode == 200 || response.statusCode == 204) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Карта успешно удалена'),
                backgroundColor: Colors.green,
              ),
            );

            // Обновляем список карт
            await _loadUploadedMaps();
          }
        } else {
          throw Exception(
              'Ошибка удаления: ${response.statusCode} - ${response.body}');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка удаления карты: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _clearForm() {
    setState(() {
      _uploadedGeoJson = null;
      _cityController.clear();
      _descriptionController.clear();
    });
  }

  @override
  void dispose() {
    _cityController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _loadUploadedMaps,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // === Заголовок ===
            const Text(
              'Управление картами',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Загрузка, управление и настройка GeoJSON карт по городам',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 24),

            // === Форма загрузки ===
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Загрузить новую карту',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Выберите файл GeoJSON и укажите город для загрузки на сервер',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Выбор файла
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _isLoading ? null : _pickGeoJson,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          side: BorderSide(color: Colors.green[700]!),
                        ),
                        icon:
                            const Icon(Icons.upload_file, color: Colors.green),
                        label: Text(
                          _uploadedGeoJson != null
                              ? 'Файл выбран: ${_uploadedGeoJson!.path.split('/').last}'
                              : 'Выбрать GeoJSON файл',
                          style: const TextStyle(color: Colors.green),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Информация о выбранном файле
                    if (_uploadedGeoJson != null) ...[
                      _buildSelectedFileInfo(),
                      const SizedBox(height: 16),
                    ],

                    // Город
                    _buildTextField(
                      controller: _cityController,
                      label: 'Город',
                      hint: 'Введите название города',
                      icon: Icons.location_city,
                    ),
                    const SizedBox(height: 16),

                    // Описание
                    _buildTextField(
                      controller: _descriptionController,
                      label: 'Описание (опционально)',
                      hint: 'Описание карты или зон',
                      maxLines: 2,
                      icon: Icons.description,
                    ),
                    const SizedBox(height: 24),

                    // Кнопка загрузки
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isUploading || _uploadedGeoJson == null
                            ? null
                            : _uploadMapToServer,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green[700],
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: _isUploading
                            ? const CircularProgressIndicator(
                                color: Colors.white)
                            : const Icon(Icons.cloud_upload),
                        label: Text(
                          _isUploading ? 'Загрузка...' : 'Загрузить на сервер',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Информация о ограничениях
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.green[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.green[100]!),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'ℹ️ Ограничения',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            '• Поддерживаются файлы формата .geojson и .json',
                            style: TextStyle(fontSize: 12),
                          ),
                          const Text(
                            '• Максимальный размер файла: 40 МБ',
                            style: TextStyle(fontSize: 12),
                          ),
                          const Text(
                            '• Можно загружать карты по разным городам',
                            style: TextStyle(fontSize: 12),
                          ),
                          const Text(
                            '• Каждая карта должна содержать корректные геоданные',
                            style: TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 32),

            // === Список загруженных карт ===
            const Text(
              'Загруженные карты',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 16),

            _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _uploadedMaps.isEmpty
                    ? _buildEmptyState()
                    : _buildMapsList(),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedFileInfo() {
    final fileStat = _uploadedGeoJson!.statSync();
    final fileSize = _formatFileSize(fileStat.size);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green[200]!),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle,
            color: Colors.green,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _uploadedGeoJson!.path.split('/').last,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Размер: $fileSize',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () {
              setState(() {
                _uploadedGeoJson = null;
              });
            },
            icon: const Icon(Icons.close, color: Colors.red),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    int maxLines = 1,
    IconData? icon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLines: maxLines,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: icon != null ? Icon(icon, color: Colors.grey) : null,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.green[700]!),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMapsList() {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _uploadedMaps.length,
      itemBuilder: (context, index) {
        final map = _uploadedMaps[index];
        return _buildMapCard(map);
      },
    );
  }

  Widget _buildMapCard(Map<String, dynamic> map) {
    // Извлекаем данные из JSON ответа сервера
    final id = map['id'] as int;
    final city = map['city'] as String? ?? 'Неизвестный город';
    final description = map['description'] as String? ?? '';
    final fileName = map['file_name'] as String? ?? '';
    final fileSize = map['file_size'] as int? ?? 0;
    final uploadDate = map['upload_date'] as String? ?? '';

    // Форматируем размер файла
    final formattedFileSize = _formatFileSize(fileSize);

    // Извлекаем имя файла без пути
    final displayName = fileName.split('/').last;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green[100],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.map,
                    color: Colors.green,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName.isNotEmpty ? displayName : 'Без названия',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$city • $formattedFileSize',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (description.isNotEmpty)
              Text(
                description,
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                ),
              ),
            const SizedBox(height: 8),
            if (uploadDate.isNotEmpty)
              Text(
                'Загружено: $uploadDate',
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      // Здесь можно добавить просмотр карты
                    },
                    icon: const Icon(Icons.visibility, size: 16),
                    label: const Text('Просмотр'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 120,
                  child: ElevatedButton.icon(
                    onPressed: () => _deleteMap(id),
                    icon: const Icon(Icons.delete, size: 16),
                    label: const Text('Удалить'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Icon(
              Icons.assignment_outlined,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            const Text(
              'Нет загруженных карт',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Загрузите первую карту GeoJSON',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes байт';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} КБ';
    } else {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ';
    }
  }
}
