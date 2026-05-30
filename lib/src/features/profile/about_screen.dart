import 'package:flutter/material.dart';
import 'package:micro_mobility_app/src/core/providers/language_provider.dart';
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
        title: Text(tr(context, 'О приложении', 'Қосымша туралы')),
        backgroundColor: Colors.green[700],
      ),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(height: 40),
            // Иконка приложения
            Icon(Icons.bike_scooter_outlined,
                size: 80, color: Colors.green[700]),
            SizedBox(height: 40),
            Text(
              tr(context, 'Приложение для оператора микромобильности', 'Микромобильділік операторына арналған қосымша'),
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 10),
            Text(
              tr(context, 'Версия: $_version', 'Нұсқасы: $_version'),
              style: TextStyle(fontSize: 16),
            ),
            Text(
              tr(context, 'Сборка: $_buildNumber', 'Құрастыру: $_buildNumber'),
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 40),
            Text(
              tr(context, 'Разработано @evn, @theYernar', 'Әзірлеген @evn, @theYernar'),
              style: TextStyle(fontSize: 14, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 8),
            Text(
              tr(context, '© 2026 Все права защищены', '© 2026 Барлық құқықтар қорғалған'),
              style: TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
