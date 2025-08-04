// screens/qr_scanner_screen.dart
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart'; // Добавлен импорт для MobileScanner
import 'package:shared_preferences/shared_preferences.dart'; // Добавлен импорт для SharedPreferences
import 'package:share_plus/share_plus.dart'; // Добавлен импорт для Share.share
import 'dart:async'; // Для Timer
import 'package:flutter/services.dart'; // Для Clipboard

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  MobileScannerController cameraController = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    torchEnabled: false,
  );

  List<String> _scannedNumbers = [];
  String _scanStatus = 'Ожидание сканирования...';
  Color _scanStatusColor = Colors.blueAccent;
  String? _lastScannedCode;
  Timer? _debounceTimer; // Для задержки сброса lastScannedCode

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

  /// Загружает сохраненные номера из SharedPreferences.
  Future<void> _loadScannedNumbers() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _scannedNumbers = prefs.getStringList('scooterScannedNumbers') ?? [];
    });
  }

  /// Сохраняет номера в SharedPreferences.
  Future<void> _saveScannedNumbers() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('scooterScannedNumbers', _scannedNumbers);
  }

  /// Извлекает номер самоката из различных форматов ссылок.
  String _extractNumberFromLink(String link) {
    // Whoosh
    RegExp whooshRegExp =
        RegExp(r'whoosh\.app\.link\/scooter\?scooter_code=([a-zA-Z0-9]+)');
    var whooshMatch = whooshRegExp.firstMatch(link);
    if (whooshMatch != null && whooshMatch.group(1) != null) {
      return whooshMatch.group(1)!;
    }

    // Urent (пример: urent.su/j/s.123456)
    RegExp urentRegExp = RegExp(r'ure\.su\/j\/s\.(\d+)');
    var urentMatch = urentRegExp.firstMatch(link);
    if (urentMatch != null && urentMatch.group(1) != null) {
      return urentMatch.group(1)!;
    }

    // Yandex (пример: go.yandex/scooters?number=789012)
    RegExp yandexRegExp = RegExp(r'go\.yandex\/scooters\?number=(\d+)');
    var yandexMatch = yandexRegExp.firstMatch(link);
    if (yandexMatch != null && yandexMatch.group(1) != null) {
      return yandexMatch.group(1)!;
    }

    // Lite (пример: lite.app.link/scooters?id=ABCD12)
    RegExp liteRegExp = RegExp(r'lite\.app\.link\/scooters\?id=([a-zA-Z0-9]+)');
    var liteMatch = liteRegExp.firstMatch(link);
    if (liteMatch != null && liteMatch.group(1) != null) {
      return liteMatch.group(1)!;
    }

    // Любой другой прямой номер или обычный текст
    return link.trim();
  }

  /// Добавляет отсканированный номер в список.
  void _addScannedNumber(String rawCode) {
    final String cleanedNumber = _extractNumberFromLink(rawCode);

    if (cleanedNumber.isEmpty || cleanedNumber.startsWith('http')) {
      setState(() {
        _scanStatus =
            'Не удалось распознать номер из "${rawCode.substring(0, rawCode.length > 30 ? 30 : rawCode.length)}..."';
        _scanStatusColor = Colors.red;
      });
      return;
    }

    if (!_scannedNumbers.contains(cleanedNumber)) {
      setState(() {
        _scannedNumbers.insert(0, cleanedNumber); // Добавляем в начало списка
        _scanStatus = 'Отсканирован: $cleanedNumber';
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

  /// Удаляет номер из списка по индексу.
  void _removeScannedNumber(int index) {
    setState(() {
      _scannedNumbers.removeAt(index);
      _scanStatus = 'Номер удален.';
      _scanStatusColor = Colors.red;
    });
    _saveScannedNumbers();
  }

  /// Копирует все номера в буфер обмена.
  void _copyAllNumbers() {
    if (_scannedNumbers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Список номеров пуст, нечего копировать.')),
      );
      return;
    }
    final allNumbersText = _scannedNumbers.join('\n');
    // Используем Clipboard для копирования
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

  /// Очищает весь список отсканированных номеров.
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

  /// Отправляет номера через системный диалог "Поделиться".
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
                  // Кнопка вспышки
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
                        // Добавлен return для обработки всех возможных состояний
                        return const Icon(Icons.flash_off, color: Colors.white);
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
                        // Добавлен return для обработки всех возможных состояний
                        return const Text('Включить вспышку',
                            style: TextStyle(color: Colors.white));
                      },
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          Colors.orange, // Оранжевый цвет для вспышки
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
                              'Список пуст. Отсканируйте первый номер!',
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
                      backgroundColor:
                          Colors.blue, // Или другой цвет для Telegram
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
