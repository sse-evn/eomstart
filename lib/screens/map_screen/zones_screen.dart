import 'package:flutter/material.dart';

class ZonesScreen extends StatefulWidget {
  final String? selectedZone;
  const ZonesScreen(
      {super.key,
      this.selectedZone,
      required Null Function(dynamic zone) onZoneSelected});

  @override
  State<ZonesScreen> createState() => _ZonesScreenState();
}

class _ZonesScreenState extends State<ZonesScreen> {
  final List<String> availableZones = [
    'Алматы дивизион 1',
    'Алматы дивизион 2',
    'Алматы дивизион 3',
    'Алматы 1 - зона 1',
    'Алматы 1 - зона 5',
    'Алматы 1 - зона 6',
    'Алматы 1 - зона 7',
    'Алматы 1 - зона 8',
    'Алматы 1 - зона 9',
    'Алматы 1 - зона 10',
    'Алматы 2 - зона 1',
    'Алматы 2 - зона 3',
  ];

  String? _currentSelectedZone;

  @override
  void initState() {
    super.initState();
    _currentSelectedZone = widget.selectedZone;
  }

  void _onZoneTapped(String zone) {
    setState(() {
      _currentSelectedZone = zone;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Техзоны'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.of(context).pop(_currentSelectedZone);
          },
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _currentSelectedZone = null;
              });
            },
            child: const Text('Сбросить'),
          ),
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {},
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Выбрано ${_currentSelectedZone != null ? '1' : '0'}',
                  style: const TextStyle(fontSize: 16),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: availableZones.length,
              itemBuilder: (context, index) {
                final zone = availableZones[index];
                final isSelected = _currentSelectedZone == zone;
                return _buildZoneItem(zone, isSelected);
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16.0),
            color: Colors.white,
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop(_currentSelectedZone);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[700],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text('Применить'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildZoneItem(String zone, bool isSelected) {
    return ListTile(
      title: Text(zone),
      trailing: isSelected
          ? Icon(Icons.check_circle, color: Colors.green[700])
          : const Icon(Icons.circle_outlined),
      onTap: () {
        _onZoneTapped(zone);
      },
    );
  }
}
