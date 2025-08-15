// lib/screens/tasks/tasks_screen.dart
import 'package:flutter/material.dart';
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

  List<dynamic> _myTasks = [];
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadMyTasks();
  }

  Future<void> _loadMyTasks() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null; // Сбрасываем ошибку перед новой загрузкой
    });

    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token != null) {
        final tasks = await _apiService.getMyTasks(token: token);
        if (mounted) {
          setState(() {
            _myTasks = tasks;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _errorMessage = 'Токен не найден. Пожалуйста, войдите снова.';
          });
        }
      }
    } catch (e) {
      debugPrint('Ошибка загрузки моих заданий: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Ошибка загрузки заданий: $e';
        });
        // Показываем Snackbar с ошибкой
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _refresh() async {
    await _loadMyTasks();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Мои задания'),
        centerTitle: true,
        backgroundColor: Colors.green[700],
        // Опционально: убрать кнопку "Назад", если это главный экран для этой роли
        // automaticallyImplyLeading: false,
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // === Заголовок ===
                    _buildHeader(),

                    const SizedBox(height: 24),

                    // === Основной контент ===
                    if (_isLoading) ...[
                      const _LoadingIndicator(),
                    ] else if (_errorMessage != null) ...[
                      _ErrorCard(message: _errorMessage!),
                    ] else if (_myTasks.isEmpty) ...[
                      const _EmptyState(),
                    ] else ...[
                      _buildTasksList(),
                    ],

                    const SizedBox(height: 32),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.green[700]!,
            Colors.green[600]!,
          ],
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(30),
          bottomRight: Radius.circular(30),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.3),
            spreadRadius: 2,
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: const Column(
        children: [
          Icon(
            Icons.assignment,
            size: 50,
            color: Colors.white,
          ),
          SizedBox(height: 16),
          Text(
            'Мои задания',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Список заданий, назначенных вам',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTasksList() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView.builder(
        shrinkWrap:
            true, // Важно для использования внутри SingleChildScrollView
        physics:
            const NeverScrollableScrollPhysics(), // Отключаем прокрутку самого ListView
        itemCount: _myTasks.length,
        itemBuilder: (context, index) {
          final task = _myTasks[index];
          return _TaskCard(task: task);
        },
      ),
    );
  }
}

// === Виджеты состояний ===

class _LoadingIndicator extends StatelessWidget {
  const _LoadingIndicator();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(50),
      child: Center(
        child: Column(
          children: [
            CircularProgressIndicator(
              color: Colors.green,
            ),
            SizedBox(height: 20),
            Text(
              'Загрузка заданий...',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;

  const _ErrorCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.1),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(30),
          bottomRight: Radius.circular(30),
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: Colors.red,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.error,
              color: Colors.white,
              size: 48,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Ошибка загрузки',
            style: TextStyle(
              color: Colors.red,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.red,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment
            .center, // Центрируем по вертикали внутри своего пространства
        children: [
          Icon(
            Icons.assignment_outlined,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 20),
          const Text(
            'Нет заданий',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Вам пока не назначено ни одного задания.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
}

// === Карточка задания ===

class _TaskCard extends StatelessWidget {
  final Map<String, dynamic> task;

  const _TaskCard({required this.task});

  @override
  Widget build(BuildContext context) {
    final title = task['title'] as String? ?? 'Без названия';
    final description = task['description'] as String? ?? '';
    final status = task['status'] as String? ?? 'pending';
    final priority = task['priority'] as String? ?? 'medium';
    final createdAt = task['created_at'] as String?;
    final deadline = task['deadline'] as String?;
    final imageUrl = task['image_url'] as String?;
    final createdBy = task['created_by'] as String?;

    return Card(
      margin: const EdgeInsets.only(bottom: 20),
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Заголовок и статус
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
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
            const SizedBox(height: 12),

            // Описание
            if (description.isNotEmpty) ...[
              Text(
                description,
                style: const TextStyle(
                  fontSize: 15,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Приоритет
            Row(
              children: [
                Icon(_getPriorityIcon(priority),
                    size: 18, color: _getPriorityColor(priority)),
                const SizedBox(width: 6),
                Text(
                  _getPriorityText(priority),
                  style: TextStyle(
                    fontSize: 14,
                    color: _getPriorityColor(priority),
                  ),
                )
              ],
            ),
            const SizedBox(height: 8),

            // Информация о создателе и датах
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (createdBy != null) ...[
                  Text(
                    'От: $createdBy',
                    style: const TextStyle(fontSize: 13, color: Colors.blue),
                  ),
                  const SizedBox(height: 4),
                ],
                if (createdAt != null) ...[
                  Text(
                    'Создано: ${_formatDateTime(createdAt)}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
                if (deadline != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Дедлайн: ${_formatDateTime(deadline)}',
                    style:
                        const TextStyle(fontSize: 12, color: Colors.deepOrange),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),

            // Фото если есть
            if (imageUrl != null && imageUrl.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                height: 120, // Фиксированная высота для предсказуемости
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    // Предполагается, что imageUrl это полный URL или путь от корня API
                    // Если это относительный путь, добавьте baseUrl
                    imageUrl.startsWith('http')
                        ? imageUrl
                        : '${ApiService.baseUrl}$imageUrl',
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Center(
                        child: CircularProgressIndicator(
                          value: loadingProgress.expectedTotalBytes != null
                              ? loadingProgress.cumulativeBytesLoaded /
                                  loadingProgress.expectedTotalBytes!
                              : null,
                        ),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        color: Colors.grey[200],
                        child: const Center(
                          child: Icon(Icons.broken_image, color: Colors.grey),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // --- Вспомогательные функции для форматирования ---
  static Color _getStatusColor(String status) {
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

  static String _getStatusText(String status) {
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

  static IconData _getPriorityIcon(String priority) {
    switch (priority.toLowerCase()) {
      case 'high':
        return Icons.arrow_upward;
      case 'low':
        return Icons.arrow_downward;
      default:
        return Icons.remove;
    }
  }

  static Color _getPriorityColor(String priority) {
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

  static String _getPriorityText(String priority) {
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

  static String _formatDateTime(String dateTimeStr) {
    try {
      // Пробуем стандартные форматы
      DateTime? dateTime;

      // Формат RFC 3339 / ISO 8601 с Z
      if (dateTimeStr.endsWith('Z')) {
        dateTime = DateTime.parse(dateTimeStr).toLocal();
      }
      // Формат RFC 3339 / ISO 8601 с смещением
      else if (dateTimeStr.contains('+') || dateTimeStr.contains('-')) {
        // Проверяем, есть ли секунды и миллисекунды
        if (dateTimeStr.length > 19) {
          // Скорее всего, формат вида 2025-08-15T07:03:34.962679228+05:00
          // Попробуем распарсить вручную или использовать DateFormat если пакет intl подключен
          // Для простоты, обрежем лишнее
          try {
            // Более грубый, но часто работающий способ для таких строк
            dateTime = DateTime.parse(dateTimeStr).toLocal();
          } catch (e) {
            // Если не удалось, возвращаем исходную строку
            return dateTimeStr;
          }
        } else {
          dateTime = DateTime.parse(dateTimeStr).toLocal();
        }
      }
      // Формат без смещения (может привести к неверной зоне, лучше указывать зону)
      else {
        dateTime = DateTime.parse(dateTimeStr).toLocal();
      }

      if (dateTime != null) {
        return '${dateTime.day.toString().padLeft(2, '0')}.${dateTime.month.toString().padLeft(2, '0')}.${dateTime.year} '
            '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
      }
    } catch (e) {
      debugPrint('Ошибка форматирования даты $dateTimeStr: $e');
      // Возвращаем исходную строку, если не удалось распарсить
      return dateTimeStr;
    }
    // На всякий случай, если parse не бросил исключение, но dateTime остался null
    return dateTimeStr;
  }
}
