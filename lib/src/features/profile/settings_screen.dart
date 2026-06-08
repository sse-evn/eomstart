// lib/screens/settings_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:micro_mobility_app/src/core/providers/language_provider.dart';
import 'package:provider/provider.dart';
import 'package:micro_mobility_app/src/core/providers/settings_provider.dart';
import 'package:path_provider/path_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _clearCache(BuildContext context, Color primaryColor) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final tempDir = await getTemporaryDirectory();
      if (tempDir.existsSync()) {
        final files = tempDir.listSync();
        for (var file in files) {
          try {
            file.deleteSync(recursive: true);
          } catch (e) {
            // Игнорируем ошибки удаления отдельных файлов
          }
        }
      }
      
      // На Android часто много мусора скапливается в кэше приложения (Documents не трогаем, там могут быть важные данные)
    } catch (e) {
      debugPrint("Error clearing cache: $e");
    }

    if (context.mounted) {
      Navigator.pop(context); // Закрываем диалог загрузки
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: primaryColor,
          content: Text(
            tr(context, 'Кэш успешно очищен', 'Кэш сәтті тазартылды'),
            style: const TextStyle(color: Colors.white),
          ),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsProvider = Provider.of<SettingsProvider>(context);
    final isDarkMode = settingsProvider.currentBrightness == Brightness.dark;

    const primaryColor = Color(0xFF388E3C); // Единый основной цвет приложения

    return Scaffold(
      appBar: AppBar(
        title: Text(
          tr(context, 'Настройки', 'Баптаулар'),
          style: TextStyle(
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: primaryColor,
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: const TextTheme(
          headlineSmall: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ).headlineSmall,
      ),
      body: Container(
        color: Theme.of(context).colorScheme.surface,
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, 24, 16, 32),
          children: [
            // Заголовок секции
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                tr(context, 'Основные настройки', 'Негізгі баптаулар'),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: primaryColor,
                ),
              ),
            ),
            SizedBox(height: 8),

            // Переключатель темы
            Card(
              elevation: 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: SwitchListTile(
                activeThumbColor: primaryColor,
                contentPadding: EdgeInsets.symmetric(horizontal: 16),
                title: Text(tr(context, 'Тёмная тема', 'Қараңғы тақырып')),
                subtitle: Text(
                  isDarkMode ? tr(context, 'Темная тема включена', 'Қараңғы тақырып қосылды') : tr(context, 'Светлая тема', 'Жарық тақырып'),
                  style: TextStyle(fontSize: 12),
                ),
                value: isDarkMode,
                onChanged: (value) {
                  settingsProvider.toggleTheme();
                },
                secondary: Icon(
                  isDarkMode ? Icons.dark_mode : Icons.light_mode,
                  color: primaryColor,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),

            SizedBox(height: 16),

            // Очистка кэша
            Card(
              elevation: 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListTile(
                contentPadding: EdgeInsets.symmetric(horizontal: 16),
                title: Text(tr(context, 'Очистить кэш приложения', 'Қолданба кэшін тазарту')),
                subtitle: Text(
                  tr(context, 'Освобождает место (фото, временные файлы)', 'Орын босатады (фотосуреттер, уақытша файлдар)'),
                  style: TextStyle(fontSize: 12),
                ),
                leading: Icon(
                  Icons.delete_outline,
                  color: Colors.redAccent,
                ),
                onTap: () => _clearCache(context, primaryColor),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),

            // SizedBox(height: 16),
            // Переключатель уведомлений (закомментирован как в оригинале)
          ],
        ),
      ),
    );
  }
}
