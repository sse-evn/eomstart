import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:micro_mobility_app/services/api_service.dart';

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  final ApiService _apiService = ApiService();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final ImagePicker _picker = ImagePicker();

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  File? _selectedImage;
  String _selectedUser = '';
  String _priority = 'medium';
  DateTime? _deadline;

  List<dynamic> _users = [];
  List<dynamic> _tasks = [];
  bool _isLoading = false;
  String _currentUserRole = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      await _loadCurrentUser();
      await _loadUsers();
      await _loadTasks();
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadCurrentUser() async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token != null) {
        final profile = await _apiService.getUserProfile(token);
        setState(() {
          _currentUserRole =
              profile['role']?.toString().toLowerCase() ?? 'user';
        });
      }
    } catch (e) {
      debugPrint('Ошибка загрузки профиля: $e');
    }
  }

  Future<void> _loadUsers() async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token != null) {
        final users = await _apiService.getAdminUsers(token);
        // Фильтруем только скаутов
        setState(() {
          _users = users
              .where(
                  (user) => user['role']?.toString().toLowerCase() == 'scout')
              .toList();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки пользователей: $e')),
        );
      }
    }
  }

  Future<void> _loadTasks() async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token != null) {
        // Исправленный вызов с именованным параметром
        final tasks = await _apiService.getTasks(token: token);
        setState(() {
          _tasks = tasks;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки заданий: $e')),
        );
      }
    }
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        setState(() {
          _selectedImage = File(image.path);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ошибка выбора изображения')),
        );
      }
    }
  }

  Future<void> _pickImageFromCamera() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.camera);
      if (image != null) {
        setState(() {
          _selectedImage = File(image.path);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ошибка съемки фото')),
        );
      }
    }
  }

  Future<void> _selectDeadline() async {
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (BuildContext context, Widget? child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Colors.green[700]!,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: Colors.green[700],
              ),
            ),
          ),
          child: child!,
        );
      },
    );

    if (pickedDate != null) {
      final TimeOfDay? pickedTime = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.now(),
      );

      if (pickedTime != null) {
        final deadline = DateTime(
          pickedDate.year,
          pickedDate.month,
          pickedDate.day,
          pickedTime.hour,
          pickedTime.minute,
        );
        setState(() {
          _deadline = deadline;
        });
      }
    }
  }

  Future<void> _createTask() async {
    if (_selectedUser.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Выберите пользователя')),
      );
      return;
    }

    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введите название задания')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token != null) {
        await _apiService.createTask(
          token: token,
          assigneeUsername: _selectedUser,
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim(),
          priority: _priority,
          deadline: _deadline,
          image: _selectedImage,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Задание успешно создано'),
              backgroundColor: Colors.green,
            ),
          );

          // Очищаем форму
          _clearForm();
          // Перезагружаем список заданий
          await _loadTasks();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка создания задания: $e'),
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
      _selectedUser = '';
      _titleController.clear();
      _descriptionController.clear();
      _selectedImage = null;
      _deadline = null;
      _priority = 'medium';
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // title: const Text('Задания'), // Главный заголовок
        // centerTitle: true,
        // backgroundColor: const Color(0xFF388E3C),
        // leading: null, // Удаляем кнопку "Назад"
        automaticallyImplyLeading:
            false, // Отключаем автоматическую кнопку назад
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // === Подзаголовок ===
              const Text(
                'Задания пользователям',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Создание и управление заданиями для скаутов',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 24),
              // === Форма создания задания ===
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Создать новое задание',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Выбор пользователя
                      _buildUserSelector(),
                      const SizedBox(height: 16),

                      // Название задания
                      _buildTextField(
                        controller: _titleController,
                        label: 'Название задания',
                        hint: 'Введите название задания',
                      ),
                      const SizedBox(height: 16),

                      // Описание
                      _buildTextField(
                        controller: _descriptionController,
                        label: 'Описание',
                        hint: 'Опишите задание подробно',
                        maxLines: 3,
                      ),
                      const SizedBox(height: 16),

                      // Приоритет
                      _buildPrioritySelector(),
                      const SizedBox(height: 16),

                      // Срок выполнения
                      _buildDeadlineSelector(),
                      const SizedBox(height: 16),

                      // Фото
                      _buildImagePicker(),
                      const SizedBox(height: 20),

                      // Кнопка создания
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _createTask,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green[700],
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: _isLoading
                              ? const CircularProgressIndicator(
                                  color: Colors.white)
                              : const Text(
                                  'Создать задание',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // === Список заданий ===
              const Text(
                'Список заданий',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 16),

              _tasks.isEmpty ? _buildEmptyState() : _buildTasksList(),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deleteTask(int taskId) async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token != null) {
        await _apiService.deleteTask(token: token, taskId: taskId);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Задание успешно удалено'),
              backgroundColor: Colors.green,
            ),
          );

          // Обновляем список заданий после удаления
          await _loadTasks();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка удаления задания: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildUserSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Назначить пользователю',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey[300]!),
            borderRadius: BorderRadius.circular(12),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedUser.isEmpty ? null : _selectedUser,
              hint: const Text('Выберите скаута'),
              isExpanded: true,
              items: _users.map((user) {
                final username = user['username'] as String;
                final firstName =
                    user['firstName'] ?? user['first_name'] ?? 'Без имени';
                return DropdownMenuItem(
                  value: username,
                  child: Text('$firstName ($username)'),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedUser = value ?? '';
                });
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    int maxLines = 1,
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

  Widget _buildPrioritySelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Приоритет',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _buildPriorityOption('low', 'Низкий', Colors.grey),
            const SizedBox(width: 12),
            _buildPriorityOption('medium', 'Средний', Colors.orange),
            const SizedBox(width: 12),
            _buildPriorityOption('high', 'Высокий', Colors.red),
          ],
        ),
      ],
    );
  }

  Widget _buildPriorityOption(String value, String label, Color color) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _priority = value;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color:
                _priority == value ? color.withOpacity(0.2) : Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _priority == value ? color : Colors.grey[300]!,
            ),
          ),
          child: Column(
            children: [
              Icon(
                _priority == value ? Icons.circle : Icons.circle_outlined,
                color: color,
                size: 20,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: _priority == value ? color : Colors.grey[700],
                  fontSize: 12,
                  fontWeight:
                      _priority == value ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDeadlineSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Срок выполнения',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _selectDeadline,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_today, color: Colors.grey),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _deadline == null
                        ? 'Выберите дату и время'
                        : '${_deadline!.day.toString().padLeft(2, '0')}.${_deadline!.month.toString().padLeft(2, '0')}.${_deadline!.year} ${_deadline!.hour.toString().padLeft(2, '0')}:${_deadline!.minute.toString().padLeft(2, '0')}',
                    style: TextStyle(
                      color: _deadline == null ? Colors.grey : Colors.black87,
                    ),
                  ),
                ),
                const Icon(Icons.arrow_drop_down, color: Colors.grey),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildImagePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Фото (опционально)',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickImage,
                icon: const Icon(Icons.photo_library, color: Colors.green),
                label: const Text('Галерея'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickImageFromCamera,
                icon: const Icon(Icons.camera_alt, color: Colors.green),
                label: const Text('Камера'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
        if (_selectedImage != null) ...[
          const SizedBox(height: 16),
          Container(
            height: 120,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(
                    _selectedImage!,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedImage = null;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
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
              'Нет заданий',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Создайте первое задание для скаутов',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTasksList() {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _tasks.length,
      itemBuilder: (context, index) {
        final task = _tasks[index];
        return _buildTaskCard(task);
      },
    );
  }

  Widget _buildTaskCard(Map<String, dynamic> task) {
    final title = task['title'] as String? ?? 'Без названия';
    final description = task['description'] as String? ?? '';
    final assignee = task['assignee_username'] as String? ?? 'Не назначен';
    final status = task['status'] as String? ?? 'pending';
    final priority = task['priority'] as String? ?? 'medium';
    final createdAt = task['created_at'] as String?;
    final deadline = task['deadline'] as String?;
    final imageUrl = task['image_url'] as String?;
    final createdBy = task['created_by'] as String?; // Кто создал задание
    final taskId = task['id']; // Предполагается, что есть поле id

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Заголовок и статус
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _getStatusColor(status).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _getStatusText(status),
                    style: TextStyle(
                      color: _getStatusColor(status),
                      fontWeight: FontWeight.w500,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Описание
            if (description.isNotEmpty)
              Text(
                description,
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                ),
              ),

            const SizedBox(height: 12),

            // Информация о задании
            Row(
              children: [
                Icon(Icons.person, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(
                  'Для: $assignee',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(width: 16),
                Icon(_getPriorityIcon(priority),
                    size: 16, color: _getPriorityColor(priority)),
                const SizedBox(width: 4),
                Text(
                  _getPriorityText(priority),
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Информация о создателе и датах
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (createdBy != null)
                  Text(
                    'Создал: $createdBy',
                    style: const TextStyle(fontSize: 11, color: Colors.blue),
                  ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (createdAt != null)
                      Text(
                        'Создано: ${_formatDateTime(createdAt)}',
                        style:
                            const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    if (deadline != null) ...[
                      const SizedBox(width: 16),
                      Text(
                        'Дедлайн: ${_formatDateTime(deadline)}',
                        style:
                            const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ],
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Фото если есть
            if (imageUrl != null && imageUrl.isNotEmpty)
              Container(
                height: 100,
                margin: const EdgeInsets.only(top: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        color: Colors.grey[200],
                        child:
                            const Icon(Icons.broken_image, color: Colors.grey),
                      );
                    },
                  ),
                ),
              ),

            // Кнопка удаления
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: () => _deleteTask(taskId),
                icon: const Icon(Icons.delete, color: Colors.white),
                label: const Text('Удалить',
                    style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return Colors.green;
      case 'in_progress':
        return Colors.blue;
      case 'pending':
        return Colors.orange;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _getStatusText(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return 'Выполнено';
      case 'in_progress':
        return 'В работе';
      case 'pending':
        return 'Ожидает';
      case 'cancelled':
        return 'Отменено';
      default:
        return status;
    }
  }

  IconData _getPriorityIcon(String priority) {
    switch (priority.toLowerCase()) {
      case 'high':
        return Icons.arrow_upward;
      case 'low':
        return Icons.arrow_downward;
      default:
        return Icons.remove;
    }
  }

  Color _getPriorityColor(String priority) {
    switch (priority.toLowerCase()) {
      case 'high':
        return Colors.red;
      case 'medium':
        return Colors.orange;
      case 'low':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  String _getPriorityText(String priority) {
    switch (priority.toLowerCase()) {
      case 'high':
        return 'Высокий';
      case 'medium':
        return 'Средний';
      case 'low':
        return 'Низкий';
      default:
        return priority;
    }
  }

  String _formatDateTime(String dateTimeStr) {
    try {
      final dateTime = DateTime.parse(dateTimeStr);
      final localDateTime = dateTime.toLocal();
      return '${localDateTime.day.toString().padLeft(2, '0')}.${localDateTime.month.toString().padLeft(2, '0')}.${localDateTime.year} ${localDateTime.hour.toString().padLeft(2, '0')}:${localDateTime.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return dateTimeStr;
    }
  }
}
