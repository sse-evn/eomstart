// lib/screens/admin/map_upload_screen.dart
import 'dart:io' show File;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class MapUploadScreen extends StatefulWidget {
  const MapUploadScreen({super.key});

  @override
  State<MapUploadScreen> createState() => _MapUploadScreenState();
}

class _MapUploadScreenState extends State<MapUploadScreen> {
  XFile? _uploadedMap;

  Future<void> _pickMap() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _uploadedMap = image;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Карта загружена')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          ElevatedButton.icon(
            onPressed: _pickMap,
            icon: const Icon(Icons.upload),
            label: const Text('Загрузить карту зон'),
          ),
          const SizedBox(height: 20),
          if (_uploadedMap != null)
            Image.file(
              File(_uploadedMap!.path),
              height: 300,
              fit: BoxFit.contain,
            )
          else
            const Text('Карта не загружена'),
        ],
      ),
    );
  }
}
