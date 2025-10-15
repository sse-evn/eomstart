// lib/screens/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:micro_mobility_app/settings_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settingsProvider = Provider.of<SettingsProvider>(context);
    final isDarkMode = settingsProvider.currentBrightness == Brightness.dark;

    const primaryColor = Color(0xFF388E3C); // Единый основной цвет приложения

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Настройки',
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
        color: Theme.of(context).colorScheme.background,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
          children: [
            // Заголовок секции
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Основные настройки',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: primaryColor,
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Переключатель темы
            Card(
              elevation: 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: SwitchListTile(
                activeColor: primaryColor,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                title: const Text('Тёмная тема'),
                subtitle: Text(
                  isDarkMode ? 'Темная тема включена' : 'Светлая тема',
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

            const SizedBox(height: 16),

            // Переключатель уведомлений
            // Card(
            //   elevation: 1,
            //   shape: RoundedRectangleBorder(
            //     borderRadius: BorderRadius.circular(12),
            //   ),
            //   child: SwitchListTile(
            //     activeColor: primaryColor,
            //     contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            //     title: const Text('Уведомления'),
            //     subtitle: Text(
            //       settingsProvider.notificationsEnabled
            //           ? 'Вы получаете уведомления'
            //           : 'Уведомления отключены',
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
            //                 ? 'Уведомления включены'
            //                 : 'Уведомления отключены',
            //             style: const TextStyle(color: Colors.white),
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
