import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'map_screen/zones_screen.dart';

enum SlotSetupState {
  selfie,
  pickingDuration,
  pickingDetails,
}

class SlotSetupScreen extends StatefulWidget {
  final String employeePosition;
  final String? selectedZone;

  const SlotSetupScreen({
    super.key,
    required this.employeePosition,
    this.selectedZone,
  });

  @override
  State<SlotSetupScreen> createState() => _SlotSetupScreenState();
}

class _SlotSetupScreenState extends State<SlotSetupScreen> {
  SlotSetupState _state = SlotSetupState.selfie;
  File? _selfieImage;
  String? _selectedSlotTimeRange;
  String? _selectedZone;

  @override
  void initState() {
    super.initState();
    _selectedZone = widget.selectedZone;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _takeSelfie();
    });
  }

  Future<void> _takeSelfie() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.camera);
    if (image != null) {
      if (mounted) {
        setState(() {
          _selfieImage = File(image.path);
          _state = SlotSetupState.pickingDuration;
        });
      }
    } else {
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  void _openDurationSheet() {
    if (mounted) {
      setState(() {
        _state = SlotSetupState.pickingDuration;
      });
    }
  }

  void _openDetailsSheet() {
    if (mounted) {
      setState(() {
        _state = SlotSetupState.pickingDetails;
      });
    }
  }

  void _finishSetup() {
    if (_selectedSlotTimeRange != null &&
        _selectedZone != null &&
        _selfieImage != null) {
      Navigator.of(context).pop({
        'selectedSlotTimeRange': _selectedSlotTimeRange,
        'selectedZone': _selectedZone,
        'selfieImage': _selfieImage,
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_state == SlotSetupState.selfie) {
      return Scaffold(
        appBar: AppBar(title: const Text('Селфи для слота')),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Начать слот'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (_state == SlotSetupState.pickingDetails) {
              _openDurationSheet();
            } else {
              Navigator.of(context).pop();
            }
          },
        ),
      ),
      body: _buildCurrentStateView(),
    );
  }

  Widget _buildCurrentStateView() {
    switch (_state) {
      case SlotSetupState.pickingDuration:
        return _buildSlotDurationView();
      case SlotSetupState.pickingDetails:
        return _buildSlotDetailsView();
      case SlotSetupState.selfie:
      default:
        return Container();
    }
  }

  Widget _buildSlotDurationView() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Длительность слота',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          _buildDurationButton('7:00 - 15:00'),
          const SizedBox(height: 16),
          _buildDurationButton('15:00 - 23:00'),
          const SizedBox(height: 16),
          _buildDurationButton('7:00 - 23:00'),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed:
                  _selectedSlotTimeRange != null ? _openDetailsSheet : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green[700],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Далее'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDurationButton(String timeRange) {
    bool isSelected = _selectedSlotTimeRange == timeRange;
    return GestureDetector(
      onTap: () {
        if (mounted) {
          setState(() {
            _selectedSlotTimeRange = timeRange;
          });
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: isSelected ? Colors.green[700] : Colors.grey[200],
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? Colors.green[700]! : Colors.transparent,
            width: 2,
          ),
        ),
        child: Center(
          child: Text(
            timeRange,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.black,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSlotDetailsView() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Начать слот',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          Text('Jet KZ1 | Алматинский • Алматы',
              style: TextStyle(color: Colors.grey[700])),
          const SizedBox(height: 20),
          _buildDetailItem(
            icon: Icons.person,
            title: widget.employeePosition,
            subtitle: 'Должность',
            onTap: () {},
          ),
          const SizedBox(height: 10),
          _buildDetailItem(
            icon: Icons.location_on,
            title: _selectedZone ?? 'Не выбрано',
            subtitle: 'Техзоны',
            trailingText: _selectedZone != null ? '1' : '0',
            onTap: () async {
              final newSelectedZone = await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) =>
                      ZonesScreen(selectedZone: _selectedZone),
                ),
              );
              if (newSelectedZone != null) {
                if (mounted) {
                  setState(() {
                    _selectedZone = newSelectedZone;
                  });
                }
              }
            },
          ),
          const SizedBox(height: 30),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed:
                  (_selectedZone != null && _selectedSlotTimeRange != null)
                      ? _finishSetup
                      : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green[700],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Начать'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailItem({
    required IconData icon,
    required String title,
    String? subtitle,
    String? trailingText,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.green[700], size: 30),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(subtitle,
                        style:
                            const TextStyle(color: Colors.grey, fontSize: 14)),
                  ],
                ],
              ),
            ),
            if (trailingText != null) ...[
              const SizedBox(width: 10),
              CircleAvatar(
                radius: 12,
                backgroundColor: Colors.green[700],
                child: Text(
                  trailingText,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ],
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}
