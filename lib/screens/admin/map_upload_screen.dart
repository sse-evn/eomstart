// lib/screens/admin/map_upload_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

class MapUploadScreen extends StatefulWidget {
  final Function(File) onGeoJsonLoaded;

  const MapUploadScreen({super.key, required this.onGeoJsonLoaded});

  @override
  State<MapUploadScreen> createState() => _MapUploadScreenState();
}

class _MapUploadScreenState extends State<MapUploadScreen> {
  File? _uploadedGeoJson;

  Future<void> _pickGeoJson() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['geojson', 'json'],
    );

    if (result != null) {
      final pickedFile = File(result.files.single.path!);

      // Сохраним файл во временную директорию, чтобы он остался доступен
      final appDir = await getTemporaryDirectory();
      final newFile = File('${appDir.path}/custom_zone.geojson');
      final savedFile = await pickedFile.copy(newFile.path);

      setState(() {
        _uploadedGeoJson = savedFile;
      });

      // Вызываем обратный вызов, чтобы передать файл в MapScreen
      widget.onGeoJsonLoaded(savedFile);

      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('GeoJSON загружен и передан')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ElevatedButton.icon(
            onPressed: _pickGeoJson,
            icon: const Icon(Icons.upload_file),
            label: const Text('Загрузить GeoJSON карту'),
          ),
          const SizedBox(height: 20),
          if (_uploadedGeoJson != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text('Файл: ${_uploadedGeoJson!.path.split('/').last}'),
              ),
            )
          else
            const Text('Файл GeoJSON не загружен'),
        ],
      ),
    );
  }
}
