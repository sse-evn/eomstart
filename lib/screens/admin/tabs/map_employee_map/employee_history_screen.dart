import 'package:flutter/material.dart';
import 'package:micro_mobility_app/models/location_history_entry.dart';

class EmployeeHistoryScreen extends StatelessWidget {
  final String userId;
  final List<LocationHistoryEntry> history;

  const EmployeeHistoryScreen({
    super.key,
    required this.userId,
    required this.history,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('История сотрудника $userId'),
        backgroundColor: Colors.green[700],
      ),
      body: history.isEmpty
          ? const Center(child: Text('Нет данных'))
          : ListView.builder(
              itemCount: history.length,
              itemBuilder: (context, index) {
                final entry = history[index];
                final isLast = index == history.length - 1;
                return Card(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.blue[100],
                      child: Text('${index + 1}'),
                    ),
                    title: Text(
                      '${entry.timestamp.toLocal().hour.toString().padLeft(2, '0')}:'
                      '${entry.timestamp.toLocal().minute.toString().padLeft(2, '0')}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            'широта: ${entry.position.latitude.toStringAsFixed(6)}'),
                        Text(
                            'долгота: ${entry.position.longitude.toStringAsFixed(6)}'),
                        if (entry.battery != null)
                          Text('Батарея: ${entry.battery!.toInt()}%'),
                      ],
                    ),
                    trailing: Icon(
                      isLast ? Icons.flag : Icons.location_on,
                      color: isLast ? Colors.red : Colors.green,
                    ),
                  ),
                );
              },
            ),
    );
  }
}
