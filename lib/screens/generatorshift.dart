// screens/qr_scanner_screen.dart
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:async';
import 'package:flutter/services.dart';

class Generatorshift extends StatefulWidget {
  const Generatorshift({super.key});

  @override
  State<Generatorshift> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<Generatorshift> {
  MobileScannerController cameraController = MobileScannerController(
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
    // Whoosh
    RegExp whooshRegExp =
        RegExp(r'whoosh\.app\.link\/scooter\?scooter_code=([a-zA-Z0-9]+)');
    var whooshMatch = whooshRegExp.firstMatch(link);
    if (whooshMatch != null && whooshMatch.group(1) != null) {
      return whooshMatch.group(1)!;
    }

    // Urent
    RegExp urentRegExp = RegExp(r'ure\.su\/j\/s\.(\d+)');
    var urentMatch = urentRegExp.firstMatch(link);
    if (urentMatch != null && urentMatch.group(1) != null) {
      return urentMatch.group(1)!;
    }

    // Yandex
    RegExp yandexRegExp = RegExp(r'go\.yandex\/scooters\?number=(\d+)');
    var yandexMatch = yandexRegExp.firstMatch(link);
    if (yandexMatch != null && yandexMatch.group(1) != null) {
      return yandexMatch.group(1)!;
    }

    // Lite
    RegExp liteRegExp = RegExp(r'lite\.app\.link\/scooters\?id=([a-zA-Z0-9]+)');
    var liteMatch = liteRegExp.firstMatch(link);
    if (liteMatch != null && liteMatch.group(1) != null) {
      return liteMatch.group(1)!;
    }

    // Bolt
    RegExp boltRegExp = RegExp(r'scooters\.taxify\.eu\/qr\/([a-zA-Z0-9\-]+)');
    var boltMatch = boltRegExp.firstMatch(link);
    if (boltMatch != null && boltMatch.group(1) != null) {
      return boltMatch.group(1)!;
    }

    // Если не распознали как ссылку, возвращаем как есть (возможно, это уже номер)
    return link.trim();
  }

  // Новый метод для добавления номера вручную
  void _addNumberManually() {
    TextEditingController _controller = TextEditingController();
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Добавить номер вручную'),
          content: TextField(
            controller: _controller,
            decoration:
                const InputDecoration(hintText: "Введите номер самоката"),
            autofocus: true,
            // Добавляем обработчик нажатия Enter
            onSubmitted: (value) {
              Navigator.of(context).pop(); // Закрываем диалог
              if (value.trim().isNotEmpty) {
                _addScannedNumber(value.trim()); // Добавляем номер
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
                if (_controller.text.trim().isNotEmpty) {
                  _addScannedNumber(_controller.text.trim());
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
    // Сначала пытаемся извлечь номер, даже если это уже строка
    final String cleanedNumber = _extractNumberFromLink(rawCode);

    if (cleanedNumber.isEmpty) {
      setState(() {
        _scanStatus =
            'Не удалось добавить номер из "${rawCode.substring(0, rawCode.length > 30 ? 30 : rawCode.length)}..."';
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
        _scanStatus = 'Номер "$cleanedNumber" уже в списке.';
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
      _scanStatus = 'Номер удален.';
      _scanStatusColor = Colors.red;
    });
    _saveScannedNumbers();
  }

  void _copyAllNumbers() {
    if (_scannedNumbers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Список номеров пуст, нечего копировать.')),
      );
      return;
    }
    final allNumbersText = _scannedNumbers.join('\n');
    Clipboard.setData(ClipboardData(text: allNumbersText)).then((_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Все номера скопированы!')),
      );
    }).catchError((e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка при копировании: $e')),
      );
    });
  }

  Future<void> _clearAllScannedNumbers() async {
    final bool? confirmClear = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Очистить список?'),
          content: const Text(
              'Вы уверены, что хотите очистить весь список отсканированных номеров? Это действие необратимо.'),
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
        _scanStatus = 'Список очищен.';
        _scanStatusColor = Colors.grey;
      });
      _saveScannedNumbers();
    }
  }

  void _sendToTelegram() {
    if (_scannedNumbers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Список номеров пуст, нечего отправлять.')),
      );
      return;
    }
    final textToSend =
        "Отсканированные номера самокатов:\n\n" + _scannedNumbers.join('\n');
    Share.share(textToSend, subject: 'Номера самокатов');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Сканер QR-кодов'),
        centerTitle: true,
        backgroundColor: Colors.green[700],
        automaticallyImplyLeading: false,
        actions: [
          // Добавляем кнопку в AppBar для ручного ввода
          IconButton(
            icon: const Icon(Icons.add, color: Colors.white),
            tooltip: 'Добавить номер вручную',
            onPressed: _addNumberManually,
          ),
        ],
      ),
      body: Column(
        children: [
          // Секция сканера
          Expanded(
            flex: 2,
            child: Container(
              margin: const EdgeInsets.all(16.0),
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12.0),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.1),
                    spreadRadius: 1,
                    blurRadius: 5,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                children: [
                  const Text(
                    'Сканировать QR-код',
                    style: TextStyle(
                      color: Color(0xFF34495E),
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 15),
                  Expanded(
                    child: MobileScanner(
                      controller: cameraController,
                      onDetect: (capture) {
                        final List<Barcode> barcodes = capture.barcodes;
                        for (final barcode in barcodes) {
                          if (barcode.rawValue != null &&
                              barcode.rawValue != _lastScannedCode) {
                            _addScannedNumber(barcode.rawValue!);
                          }
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 15),
                  Text(
                    _scanStatus,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: _scanStatusColor,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed: () => cameraController.toggleTorch(),
                    icon: ValueListenableBuilder<TorchState>(
                      valueListenable: cameraController.torchState,
                      builder: (context, state, child) {
                        switch (state) {
                          case TorchState.off:
                            return const Icon(Icons.flash_off,
                                color: Colors.white);
                          case TorchState.on:
                            return const Icon(Icons.flash_on,
                                color: Colors.white);
                        }
                      },
                    ),
                    label: ValueListenableBuilder<TorchState>(
                      valueListenable: cameraController.torchState,
                      builder: (context, state, child) {
                        switch (state) {
                          case TorchState.off:
                            return const Text('Включить вспышку',
                                style: TextStyle(color: Colors.white));
                          case TorchState.on:
                            return const Text('Выключить вспышку',
                                style: TextStyle(color: Colors.white));
                        }
                      },
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                    ),
                  ),
                  // Добавляем кнопку ручного ввода под сканером
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed: _addNumberManually,
                    icon: const Icon(Icons.edit, color: Colors.white),
                    label: const Text('Ввести номер вручную',
                        style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Секция списка номеров
          Expanded(
            flex: 1,
            child: Container(
              margin:
                  const EdgeInsets.only(left: 16.0, right: 16.0, bottom: 16.0),
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12.0),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.1),
                    spreadRadius: 1,
                    blurRadius: 5,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                children: [
                  const Text(
                    'Номера',
                    style: TextStyle(
                      color: Color(0xFF34495E),
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: _scannedNumbers.isEmpty
                        ? const Center(
                            child: Text(
                              'Список пуст. Отсканируйте первый номер или добавьте вручную!',
                              style: TextStyle(color: Colors.grey),
                              textAlign: TextAlign.center,
                            ),
                          )
                        : ListView.builder(
                            itemCount: _scannedNumbers.length,
                            itemBuilder: (context, index) {
                              final number = _scannedNumbers[index];
                              return Card(
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                elevation: 0.5,
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
                  const SizedBox(height: 15),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed:
                              _scannedNumbers.isEmpty ? null : _copyAllNumbers,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text('Копировать все',
                              style: TextStyle(color: Colors.white)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _scannedNumbers.isEmpty
                              ? null
                              : _clearAllScannedNumbers,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text('Очистить список',
                              style: TextStyle(color: Colors.white)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: _scannedNumbers.isEmpty ? null : _sendToTelegram,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('Отправить в Telegram',
                        style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
