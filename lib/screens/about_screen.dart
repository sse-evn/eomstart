import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart'; // Добавляем этот пакет

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String _version = '...';
  String _buildNumber = '...';

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
  }

  // Асинхронная функция для получения информации о версии приложения
  Future<void> _loadPackageInfo() async {
    final info = await PackageInfo.fromPlatform();
    setState(() {
      _version = info.version;
      _buildNumber = info.buildNumber;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('О приложении'),
        backgroundColor: Colors.green[700],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 40),
            // Иконка приложения
            Icon(Icons.bike_scooter_outlined,
                size: 80, color: Colors.green[700]),
            const SizedBox(height: 40),
            const Text(
              'Приложение для оператора микромобильности',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              'Версия: $_version',
              style: const TextStyle(fontSize: 16),
            ),
            Text(
              'Сборка: $_buildNumber',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 40),
            const Text(
              'Разработано @evn, @theYernar',
              style: TextStyle(fontSize: 14, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              '© 2025 Все права защищены',
              style: TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
