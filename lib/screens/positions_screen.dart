import 'package:flutter/material.dart';

class PositionsScreen extends StatefulWidget {
  final String? selectedPosition;
  const PositionsScreen({super.key, this.selectedPosition});

  @override
  State<PositionsScreen> createState() => _PositionsScreenState();
}

class _PositionsScreenState extends State<PositionsScreen> {
  final List<String> availablePositions = [
    'Экспедитор',
    'Скаут',
    'Грузчик',
    'Кладовщик',
  ];

  String? _currentSelectedPosition;

  @override
  void initState() {
    super.initState();
    _currentSelectedPosition = widget.selectedPosition;
  }

  void _onPositionTapped(String position) {
    setState(() {
      _currentSelectedPosition = position;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Должность'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.of(context).pop(_currentSelectedPosition);
          },
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _currentSelectedPosition = null;
              });
            },
            child: const Text('Сбросить'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: availablePositions.length,
              itemBuilder: (context, index) {
                final position = availablePositions[index];
                final isSelected = _currentSelectedPosition == position;
                return _buildPositionItem(position, isSelected);
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
                  Navigator.of(context).pop(_currentSelectedPosition);
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

  Widget _buildPositionItem(String position, bool isSelected) {
    return ListTile(
      title: Text(position),
      trailing: isSelected
          ? Icon(Icons.check_circle, color: Colors.green[700])
          : const Icon(Icons.circle_outlined),
      onTap: () {
        _onPositionTapped(position);
      },
    );
  }
}
