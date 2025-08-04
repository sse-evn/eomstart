import 'package:flutter/material.dart';
import 'about_screen.dart'; // Укажите правильный путь
import 'login_screen.dart'; // Укажите правильный путь
import 'settings_screen.dart'; // Укажите правильный путь

// Модель для данных сотрудника
class Employee {
  final String name;
  final String position;
  final String imageUrl;

  Employee(
      {required this.name, required this.position, required this.imageUrl});
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Future<Employee> _fetchEmployeeData() async {
    await Future.delayed(const Duration(seconds: 2));
    return Employee(
      name: 'Иван Иванов',
      position: 'Скаут',
      imageUrl: 'https://cdn-icons-png.flaticon.com/512/149/149071.png',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Профиль'),
        centerTitle: true,
        backgroundColor: Colors.green[700],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // --- Секция профиля сотрудника ---
            FutureBuilder<Employee>(
              future: _fetchEmployeeData(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40.0),
                    child: Center(child: CircularProgressIndicator()),
                  );
                } else if (snapshot.hasError) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40.0),
                    child: Center(
                      child: Text('Ошибка загрузки данных',
                          style: TextStyle(color: Colors.red)),
                    ),
                  );
                } else if (snapshot.hasData) {
                  final employee = snapshot.data!;
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        vertical: 40.0, horizontal: 24.0),
                    decoration: BoxDecoration(
                      color: Colors.green[50],
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(30),
                        bottomRight: Radius.circular(30),
                      ),
                    ),
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 60,
                          backgroundImage: NetworkImage(employee.imageUrl),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          employee.name,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          employee.position,
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.green[700],
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  );
                } else {
                  return const SizedBox.shrink();
                }
              },
            ),

            const SizedBox(height: 20),

            // --- Секция общих настроек ---
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Настройки',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 10),
            // Кнопка "Настройки"
            _buildSettingsItem(
              context,
              icon: Icons.settings,
              title: 'Настройки',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const SettingsScreen()),
                );
              },
            ),
            // Кнопка "Уведомления"
            _buildSettingsItem(
              context,
              icon: Icons.notifications,
              title: 'Уведомления',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const SettingsScreen()),
                );
              },
            ),

            const Divider(),

            // --- Секция "О приложении" и выход ---
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Другое',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 10),
            // Кнопка "О приложении"
            _buildSettingsItem(
              context,
              icon: Icons.info,
              title: 'О приложении',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const AboutScreen()),
                );
              },
            ),
            // Кнопка "Выйти"
            _buildSettingsItem(
              context,
              icon: Icons.logout,
              title: 'Выйти',
              color: Colors.red,
              onTap: () {
                // Здесь мы не просто переходим на экран, а заменяем текущий экран
                // на экран входа, чтобы пользователь не мог вернуться назад по кнопке "назад"
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // Вспомогательный метод для создания элемента списка настроек
  Widget _buildSettingsItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    Color? color,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: color ?? Colors.grey[700]),
      title: Text(title, style: TextStyle(color: color ?? Colors.black87)),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: onTap,
    );
  }
}
