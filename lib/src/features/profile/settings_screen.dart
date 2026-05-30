// lib/screens/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:micro_mobility_app/src/core/providers/language_provider.dart';
import 'package:provider/provider.dart';
import 'package:micro_mobility_app/src/core/providers/settings_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

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

            // Переключатель уведомлений
            // Card(
            //   elevation: 1,
            //   shape: RoundedRectangleBorder(
            //     borderRadius: BorderRadius.circular(12),
            //   ),
            //   child: SwitchListTile(
            //     activeColor: primaryColor,
            //     contentPadding: EdgeInsets.symmetric(horizontal: 16),
            //     title: Text(tr(context, 'Уведомления', 'Хабарламалар')),
            //     subtitle: Text(
            //       settingsProvider.notificationsEnabled
            //           ? tr(context, 'Вы получаете уведомления', 'Сіз хабарламалар аласыз')
            //           : tr(context, 'Уведомления отключены', 'Хабарламалар өшірілді'),
            //       style: TextStyle(fontSize: 12),
            //     ),
            //     value: settingsProvider.notificationsEnabled,
            //     onChanged: (value) {
            //       settingsProvider.toggleNotifications(value);
            //       ScaffoldMessenger.of(context).showSnackBar(
            //         SnackBar(
            //           backgroundColor: primaryColor,
            //           content: Text(
            //             value
            //                 ? tr(context, 'Уведомления включены', 'Хабарламалар қосылды')
            //                 : tr(context, 'Уведомления отключены', 'Хабарламалар өшірілді'),
            //             style: TextStyle(color: Colors.white),
            //           ),
            //           duration: const Duration(seconds: 2),
            //           behavior: SnackBarBehavior.floating,
            //           shape: RoundedRectangleBorder(
            //             borderRadius: BorderRadius.circular(8),
            //           ),
            //         ),
            //       );
            //     },
            //     secondary: Icon(
            //       settingsProvider.notificationsEnabled
            //           ? Icons.notifications
            //           : Icons.notifications_off,
            //       color: primaryColor,
            //     ),
            //     shape: RoundedRectangleBorder(
            //       borderRadius: BorderRadius.circular(12),
            //     ),
            //   ),
            // ),
          ],
        ),
      ),
    );
  }
}
