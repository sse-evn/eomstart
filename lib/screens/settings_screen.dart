import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:micro_mobility_app/settings_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settingsProvider = Provider.of<SettingsProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Настройки'),
        backgroundColor: Colors.green[700],
      ),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('Темная тема'),
            value: settingsProvider.currentBrightness == Brightness.dark,
            onChanged: (bool value) {
              settingsProvider.toggleTheme();
            },
            secondary: Icon(
              settingsProvider.currentBrightness == Brightness.dark
                  ? Icons.dark_mode
                  : Icons.light_mode,
            ),
          ),
          // Новый переключатель для уведомлений
          SwitchListTile(
            title: const Text('Уведомления'),
            value: settingsProvider.notificationsEnabled,
            onChanged: (bool value) {
              settingsProvider.toggleNotifications(value);
              // Показываем локальное уведомление (SnackBar)
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    value ? 'Уведомления включены' : 'Уведомления выключены',
                  ),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            secondary: Icon(
              settingsProvider.notificationsEnabled
                  ? Icons.notifications
                  : Icons.notifications_off,
            ),
          ),
        ],
      ),
    );
  }
}
