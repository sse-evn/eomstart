import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:async';
import 'package:flutter/services.dart';

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

    // 🔹 WSH (https://wsh.bike?s=AB0696)
    RegExp wshRegExp = RegExp(r'wsh\.bike\?s=([a-zA-Z0-9]+)');
    var wshMatch = wshRegExp.firstMatch(link);
    if (wshMatch != null && wshMatch.group(1) != null) {
      return wshMatch.group(1)!;
    }

    RegExp urentRegExp = RegExp(r'ure\.su\/j\/s\.(\d+)');
    var urentMatch = urentRegExp.firstMatch(link);
    if (urentMatch != null && urentMatch.group(1) != null) {
      return urentMatch.group(1)!;
    }

    RegExp yandexRegExp = RegExp(r'go\.yandex\/scooters\?number=(\d+)');
    var yandexMatch = yandexRegExp.firstMatch(link);
    if (yandexMatch != null && yandexMatch.group(1) != null) {
      return yandexMatch.group(1)!;
    }

    RegExp liteRegExp = RegExp(r'lite\.app\.link\/scooters\?id=([a-zA-Z0-9]+)');
    var liteMatch = liteRegExp.firstMatch(link);
    if (liteMatch != null && liteMatch.group(1) != null) {
      return liteMatch.group(1)!;
    }

    RegExp boltRegExp = RegExp(r'scooters\.taxify\.eu\/qr\/([a-zA-Z0-9\-]+)');
    var boltMatch = boltRegExp.firstMatch(link);
    if (boltMatch != null && boltMatch.group(1) != null) {
      return boltMatch.group(1)!;
    }

    return link.trim();
  }

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
    final String cleanedNumber = _extractNumberFromLink(rawCode);

    if (cleanedNumber.isEmpty) {
      setState(() {
        _scanStatus =
            'Не удалось добавить номер из "${rawCode.length > 30 ? '${rawCode.substring(0, 30)}...' : rawCode}"';
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
        
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(8.0),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Column(
                    children: [
                      // === Сканер ===
                      Container(
                        margin: const EdgeInsets.all(8.0),
                        padding: const EdgeInsets.all(12.0),
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
                            const SizedBox(height: 12),
                            AspectRatio(
                              aspectRatio: 1.0,
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(18),
                                  border:
                                      Border.all(color: Colors.grey, width: 1),
                                ),
                                clipBehavior: Clip.hardEdge,
                                child: MobileScanner(
                                  
                                  controller: cameraController,
                                  onDetect: (capture) {
                                    final barcodes = capture.barcodes;
                                    for (final barcode in barcodes) {
                                      if (barcode.rawValue != null &&
                                          barcode.rawValue !=
                                              _lastScannedCode) {
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
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
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
                                          size: 18,
                                        );
                                      },
                                    ),
                                    label: ValueListenableBuilder<TorchState>(
                                      valueListenable:
                                          cameraController.torchState,
                                      builder: (context, state, child) {
                                        return Text(
                                          state == TorchState.on
                                              ? 'Выкл'
                                              : 'Вкл',
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12),
                                        );
                                      },
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.orange,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(8)),
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 12),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: _addNumberManually,
                                    icon: const Icon(Icons.edit,
                                        color: Colors.white, size: 18),
                                    label: const Text('Вручную',
                                        style: TextStyle(
                                            color: Colors.white, fontSize: 12)),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.blue,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(8)),
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 12),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // === Список номеров ===
                      Container(
                        margin: const EdgeInsets.all(8.0),
                        padding: const EdgeInsets.all(12.0),
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
                            Column(
                              children: [
                                Text(
                                  'Всего: ${_scannedNumbers.length}',
                                  style: TextStyle(
                                    color: const Color(0xFF34495E),
                                    fontSize:
                                        MediaQuery.of(context).size.width > 400
                                            ? 18
                                            : 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),

                               

                                // Text(
                                //   'Номера',
                                //   style: TextStyle(
                                //     color: const Color(0xFF34495E),
                                //     fontSize:
                                //         MediaQuery.of(context).size.width > 400
                                //             ? 18
                                //             : 16,
                                //     fontWeight: FontWeight.bold,
                                //   ),
                                //   textAlign: TextAlign.center,
                                // ),

                              ],
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              height: 150,
                              child: _scannedNumbers.isEmpty
                                  ? const Center(
                                      child: Text(
                                        'Список пуст. Отсканируйте или добавьте вручную!',
                                        style: TextStyle(
                                            color: Colors.grey, fontSize: 14),
                                        textAlign: TextAlign.center,
                                      ),
                                    )
                                  : ListView.builder(
                                      itemCount: _scannedNumbers.length,
                                      itemBuilder: (context, index) {
                                        final number = _scannedNumbers[index];
                                        return Card(
                                          margin: const EdgeInsets.symmetric(
                                              vertical: 2),
                                          child: ListTile(
                                            title: Text(number,
                                                style: const TextStyle(
                                                    fontSize: 14)),
                                            trailing: IconButton(
                                              icon: const Icon(Icons.close,
                                                  color: Colors.red, size: 18),
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
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(8)),
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 12),
                                    ),
                                    icon: Icon(Icons.delete_rounded),
                                    label: const Text('Очистить',
                                        style: TextStyle(
                                            color: Colors.white, fontSize: 14)),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: _scannedNumbers.isEmpty
                                        ? null
                                        : _copyAllNumbers,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(8)),
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 12),
                                    ),

                                    icon: Icon(Icons.copy_rounded),
                                    label: const Text('Копировать',
                                        style: TextStyle(
                                            color: Colors.white, fontSize: 14)),
                                  ),
                                ),
                              ],
                            ),
                            // const SizedBox(height: 12),
                            // ElevatedButton(
                            //   onPressed: _scannedNumbers.isEmpty
                            //       ? null
                            //       : _sendToTelegram,
                            //   style: ElevatedButton.styleFrom(
                            //     backgroundColor: Colors.blue,
                            //     shape: RoundedRectangleBorder(
                            //         borderRadius: BorderRadius.circular(8)),
                            //     padding:
                            //         const EdgeInsets.symmetric(vertical: 12, horizontal: 18),
                            //   ),
                            //   child: const Text('Отправить в Telegram',
                            //       style: TextStyle(
                            //           color: Colors.white, fontSize: 14)),
                            // ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
