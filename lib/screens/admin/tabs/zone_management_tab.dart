import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:micro_mobility_app/services/api_service.dart';

class ZoneManagementTab extends StatefulWidget {
  const ZoneManagementTab({super.key});

  @override
  State<ZoneManagementTab> createState() => _ZoneManagementTabState();
}

class _ZoneManagementTabState extends State<ZoneManagementTab> {
  final ApiService _apiService = ApiService();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  late Future<List<Zone>> _zonesFuture;
  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _zonesFuture = _loadZones();
  }

  Future<List<Zone>> _loadZones() async {
    final token = await _storage.read(key: 'jwt_token');
    if (token == null) return [];
    final data = await _apiService.getAvailableZonesRaw(token);
    return data.map((e) => Zone(id: e['id'], name: e['name'])).toList();
  }

  Future<void> _addZone() async {
    final name = _controller.text.trim();
    if (name.isEmpty) return;

    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token == null) return;

      await _apiService.createZone(token, name);
      setState(() {
        _zonesFuture = _loadZones();
        _controller.clear();
      });
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    }
  }

  Future<void> _deleteZone(int zoneId) async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token == null) return;

      await _apiService.deleteZone(token, zoneId);
      setState(() {
        _zonesFuture = _loadZones();
      });
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.primaryColor;

    return RefreshIndicator(
      onRefresh: () async {
        setState(() {
          _zonesFuture = _loadZones();
        });
      },
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Управление зонами',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Добавление, удаление и редактирование зон по номерам',
              style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.all(0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Добавить зону',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: primaryColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          decoration: const InputDecoration(
                            hintText: 'Номер зоны (1, 2, 3...)',
                            border: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.all(Radius.circular(12)),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: _addZone,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text(
                          'Добавить',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'Существующие зоны',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            FutureBuilder<List<Zone>>(
              future: _zonesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final zones = snapshot.data ?? [];
                if (zones.isEmpty) {
                  return Card(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        children: [
                          Icon(Icons.grid_3x3,
                              size: 64, color: primaryColor.withOpacity(0.3)),
                          const SizedBox(height: 16),
                          const Text(
                            'Нет зон',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Добавьте первую зону',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 14, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: zones.length,
                  itemBuilder: (context, index) {
                    final zone = zones[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: primaryColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Center(
                            child: Text(
                              zone.name,
                              style: TextStyle(
                                  color: primaryColor,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        title: Text('Зона ${zone.name}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _deleteZone(zone.id),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class Zone {
  final int id;
  final String name;
  Zone({required this.id, required this.name});
}
