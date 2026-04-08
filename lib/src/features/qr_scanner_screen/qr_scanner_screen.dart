import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'report_photos_screen.dart';

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final MobileScannerController cameraController = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    torchEnabled: false,
  );

  List<String> _scannedNumbers = [];
  String _scanStatus = 'Ожидание сканирования...';
  Color _scanStatusColor = Colors.blueAccent;
  String? _lastScannedCode;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _loadScannedNumbers();
  }

  @override
  void dispose() {
    cameraController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadScannedNumbers() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _scannedNumbers = prefs.getStringList('scooterScannedNumbers') ?? [];
    });
  }

  Future<void> _saveScannedNumbers() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('scooterScannedNumbers', _scannedNumbers);
  }

  String _extractNumberFromLink(String link) {
    final whooshRegExp =
        RegExp(r'whoosh\.app\.link\/scooter\?scooter_code=([a-zA-Z0-9]+)');
    final whooshMatch = whooshRegExp.firstMatch(link);
    if (whooshMatch != null && whooshMatch.group(1) != null) {
      return whooshMatch.group(1)!;
    }

    final wshRegExp = RegExp(r'wsh\.bike\?s=([a-zA-Z0-9]+)');
    final wshMatch = wshRegExp.firstMatch(link);
    if (wshMatch != null && wshMatch.group(1) != null) {
      return wshMatch.group(1)!;
    }

    final urentRegExp = RegExp(r'ure\.su\/j\/s\.(\d+)');
    final urentMatch = urentRegExp.firstMatch(link);
    if (urentMatch != null && urentMatch.group(1) != null) {
      return urentMatch.group(1)!;
    }

    final yandexRegExp = RegExp(r'go\.yandex\/scooters\?number=(\d+)');
    final yandexMatch = yandexRegExp.firstMatch(link);
    if (yandexMatch != null && yandexMatch.group(1) != null) {
      return yandexMatch.group(1)!;
    }

    final liteRegExp = RegExp(r'lite\.app\.link\/scooters\?id=([a-zA-Z0-9]+)');
    final liteMatch = liteRegExp.firstMatch(link);
    if (liteMatch != null && liteMatch.group(1) != null) {
      return liteMatch.group(1)!;
    }

    final boltRegExp = RegExp(r'scooters\.taxify\.eu\/qr\/([a-zA-Z0-9\-]+)');
    final boltMatch = boltRegExp.firstMatch(link);
    if (boltMatch != null && boltMatch.group(1) != null) {
      return boltMatch.group(1)!;
    }

    return link.trim();
  }

  void _addNumberManually() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Добавить номер вручную'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: "Введите номер самоката",
            ),
            autofocus: true,
            onSubmitted: (value) {
              Navigator.of(context).pop();
              if (value.trim().isNotEmpty) {
                _addScannedNumber(value.trim());
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                if (controller.text.trim().isNotEmpty) {
                  _addScannedNumber(controller.text.trim());
                }
              },
              child: const Text('Добавить'),
            ),
          ],
        );
      },
    );
  }

  void _addScannedNumber(String rawCode) {
    final cleanedNumber = _extractNumberFromLink(rawCode);

    if (cleanedNumber.isEmpty) {
      setState(() {
        _scanStatus = 'Не удалось добавить номер';
        _scanStatusColor = Colors.red;
      });
      return;
    }

    if (!_scannedNumbers.contains(cleanedNumber)) {
      setState(() {
        _scannedNumbers.insert(0, cleanedNumber);
        _scanStatus = 'Добавлен: $cleanedNumber';
        _scanStatusColor = Colors.green;
      });
      _saveScannedNumbers();
    } else {
      setState(() {
        _scanStatus = 'Номер "$cleanedNumber" уже в списке';
        _scanStatusColor = Colors.orange;
      });
    }

    _lastScannedCode = cleanedNumber;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(seconds: 2), () {
      _lastScannedCode = null;
    });
  }

  void _removeScannedNumber(int index) {
    setState(() {
      _scannedNumbers.removeAt(index);
      _scanStatus = 'Номер удалён';
      _scanStatusColor = Colors.red;
    });
    _saveScannedNumbers();
  }

  void _copyAllNumbers() {
    if (_scannedNumbers.isEmpty) return;
    final allNumbersText = _scannedNumbers.join('\n');
    Clipboard.setData(ClipboardData(text: allNumbersText));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Все номера скопированы')),
    );
  }

  Future<void> _clearAllScannedNumbers() async {
    final confirmClear = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Очистить список?'),
          content: const Text('Удалить все отсканированные номера?'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child:
                  const Text('Очистить', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );

    if (confirmClear == true) {
      setState(() {
        _scannedNumbers.clear();
        _scanStatus = 'Список очищен';
        _scanStatusColor = Colors.grey;
      });
      _saveScannedNumbers();
    }
  }

  void _goNext() {
    if (_scannedNumbers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Сначала отсканируй хотя бы один самокат')),
      );
      return;
    }

    final employeeName = 'Пользователь';
    final String? employeeUsername = null;
    final int? employeeTelegramId = null;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReportPhotosScreen(
          scooterNumbers: List<String>.from(_scannedNumbers),
          employeeName: employeeName,
          employeeUsername: employeeUsername,
          employeeTelegramId: employeeTelegramId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Сканер QR-кодов'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(8),
                child: Column(
                  children: [
                    Container(
                      margin: const EdgeInsets.all(8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.secondary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          AspectRatio(
                            aspectRatio: 1,
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: Colors.grey),
                              ),
                              clipBehavior: Clip.hardEdge,
                              child: MobileScanner(
                                controller: cameraController,
                                onDetect: (capture) {
                                  for (final barcode in capture.barcodes) {
                                    if (barcode.rawValue != null &&
                                        barcode.rawValue != _lastScannedCode) {
                                      _addScannedNumber(barcode.rawValue!);
                                    }
                                  }
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _scanStatus,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: _scanStatusColor,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () =>
                                      cameraController.toggleTorch(),
                                  icon: ValueListenableBuilder<TorchState>(
                                    valueListenable:
                                        cameraController.torchState,
                                    builder: (context, state, child) {
                                      return Icon(
                                        state == TorchState.on
                                            ? Icons.flashlight_off_rounded
                                            : Icons.flashlight_on_rounded,
                                        color: Colors.white,
                                      );
                                    },
                                  ),
                                  label: const Text(
                                    'Фонарик',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.orange,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: _addNumberManually,
                                  icon: const Icon(Icons.edit,
                                      color: Colors.white),
                                  label: const Text(
                                    'Вручную',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Container(
                      margin: const EdgeInsets.all(8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.secondary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Text(
                            'Всего: ${_scannedNumbers.length}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            height: 180,
                            child: _scannedNumbers.isEmpty
                                ? const Center(
                                    child: Text(
                                      'Список пуст. Отсканируй или добавь вручную.',
                                      textAlign: TextAlign.center,
                                    ),
                                  )
                                : ListView.builder(
                                    itemCount: _scannedNumbers.length,
                                    itemBuilder: (context, index) {
                                      final number = _scannedNumbers[index];
                                      return Card(
                                        child: ListTile(
                                          title: Text(number),
                                          trailing: IconButton(
                                            icon: const Icon(Icons.close,
                                                color: Colors.red),
                                            onPressed: () =>
                                                _removeScannedNumber(index),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: _scannedNumbers.isEmpty
                                      ? null
                                      : _clearAllScannedNumbers,
                                  icon: const Icon(Icons.delete_rounded),
                                  label: const Text('Очистить'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: _scannedNumbers.isEmpty
                                      ? null
                                      : _copyAllNumbers,
                                  icon: const Icon(Icons.copy_rounded),
                                  label: const Text('Копировать'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _goNext,
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('Далее: фото отчёта'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
