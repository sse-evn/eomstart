import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show ClipboardData, Clipboard;
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image/image.dart' as img;
import 'package:micro_mobility_app/src/core/config/app_config.dart';
import 'package:micro_mobility_app/src/core/providers/shift_provider.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'custom_camera_screen.dart';

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
  Map<String, int> _competitorCounts = {
    'Yandex': 0,
    'Jet': 0,
    'Whoosh': 0,
    'Bolt': 0,
  };
  String _scanStatus = 'Ожидание сканирования...';
  Color _scanStatusColor = Colors.blueAccent;
  String? _lastScannedCode;
  Timer? _debounceTimer;

  // New combined variables
  bool _isQrScannerOpen = false;
  String? _targetBrandForScan;
  final TextEditingController _commentController = TextEditingController();
  String _reportType = 'before';
  final List<File> _photos = [];
  bool _sending = false;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _loadScannedNumbers();
  }

  @override
  void dispose() {
    cameraController.dispose();
    _debounceTimer?.cancel();
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _loadScannedNumbers() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _scannedNumbers = prefs.getStringList('scooterScannedNumbers') ?? [];
      final compStr = prefs.getString('scooterCompetitorCounts');
      if (compStr != null) {
        try {
          final Map<String, dynamic> decoded = jsonDecode(compStr);
          _competitorCounts =
              decoded.map((key, value) => MapEntry(key, value as int));
        } catch (_) {}
      }
    });
  }

  Future<void> _saveScannedNumbers() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('scooterScannedNumbers', _scannedNumbers);
    await prefs.setString(
        'scooterCompetitorCounts', jsonEncode(_competitorCounts));
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

    final yandexRegExp = RegExp(r'go\.yandex\/scooters\?number=([a-zA-Z0-9]+)');
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

    final detectedBrand = _detectBrandFromLink(rawCode) ?? _detectBrandFromText(rawCode);
    if (detectedBrand != null) {
      String cleanVal = cleanedNumber;
      final upper = rawCode.toUpperCase().trim();
      if (detectedBrand == 'BOLT' && upper.startsWith('BOLT')) {
        cleanVal = rawCode.substring(4).trim();
      } else if (detectedBrand == 'WHOOSH' && upper.startsWith('WHOOSH')) {
        cleanVal = rawCode.substring(6).trim();
      } else if (detectedBrand == 'WHOOSH' && upper.startsWith('WSH')) {
        cleanVal = rawCode.substring(3).trim();
      } else if (detectedBrand == 'JET' && upper.startsWith('JET')) {
        cleanVal = rawCode.substring(3).trim();
      } else if (detectedBrand == 'YANDEX' && upper.startsWith('YANDEX')) {
        cleanVal = rawCode.substring(6).trim();
      }
      
      if (cleanVal.isEmpty) cleanVal = cleanedNumber;
      
      _registerScooterForBrand(detectedBrand, cleanVal);
      return;
    }

    if (_targetBrandForScan != null) {
      final brand = _targetBrandForScan!;
      setState(() {
        _targetBrandForScan = null;
      });
      _registerScooterForBrand(brand, cleanedNumber);
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
    final item = _scannedNumbers[index];
    setState(() {
      _scannedNumbers.removeAt(index);
      _scanStatus = 'Номер удалён';
      _scanStatusColor = Colors.red;

      if (item.startsWith('[')) {
        final closeBracket = item.indexOf(']');
        if (closeBracket != -1) {
          final brand = item.substring(1, closeBracket);
          if (_competitorCounts.containsKey(brand)) {
            final current = _competitorCounts[brand] ?? 0;
            if (current > 0) {
              _competitorCounts[brand] = current - 1;
            }
          }
        }
      }
    });
    _saveScannedNumbers();
  }

  void _copyAllNumbers() {
    final hasCounts = _competitorCounts.values.any((v) => v > 0);
    if (_scannedNumbers.isEmpty && !hasCounts) return;

    final List<String> allLines = [];
    if (_scannedNumbers.isNotEmpty) allLines.addAll(_scannedNumbers);
    _competitorCounts.forEach((key, value) {
      if (value > 0) allLines.add('$key: $value');
    });

    final allNumbersText = allLines.join('\n');
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
        _competitorCounts.updateAll((key, value) => 0);
        _scanStatus = 'Список очищен';
        _scanStatusColor = Colors.grey;
      });
      _saveScannedNumbers();
    }
  }

  void _clearCompetitorCounts() {
    setState(() {
      _competitorCounts.updateAll((key, value) => 0);
      _scannedNumbers.removeWhere((item) => item.startsWith('['));
    });
    _saveScannedNumbers();
  }

  void _registerScooterForBrand(String brand, String number) {
    final fullLabel = '[$brand] $number';
    if (_scannedNumbers.contains(fullLabel) || _scannedNumbers.contains(number)) {
      _showMessage('Этот самокат уже добавлен!');
      return;
    }

    setState(() {
      _scannedNumbers.insert(0, fullLabel);
      _competitorCounts[brand] = (_competitorCounts[brand] ?? 0) + 1;
      _scanStatus = 'Добавлен $brand: $number';
      _scanStatusColor = Colors.green;
    });
    _saveScannedNumbers();
  }

  void _removeLastScooterForBrand(String brand) {
    final prefix = '[$brand]';
    int indexToRemove = -1;
    for (int i = _scannedNumbers.length - 1; i >= 0; i--) {
      if (_scannedNumbers[i].startsWith(prefix)) {
        indexToRemove = i;
        break;
      }
    }

    setState(() {
      if (indexToRemove != -1) {
        _scannedNumbers.removeAt(indexToRemove);
      }
      final currentCount = _competitorCounts[brand] ?? 0;
      if (currentCount > 0) {
        _competitorCounts[brand] = currentCount - 1;
      }
    });
    _saveScannedNumbers();
  }

  String? _detectBrandFromLink(String link) {
    if (link.contains('whoosh.app.link') || link.contains('wsh.bike') || link.contains('wsh.app.link')) {
      return 'WHOOSH';
    }
    if (link.contains('scooters.taxify.eu')) {
      return 'BOLT';
    }
    if (link.contains('go.yandex') || link.contains('yandex')) {
      return 'YANDEX';
    }
    if (link.contains('ure.su') || link.contains('lite.app.link') || link.contains('jet')) {
      return 'JET';
    }
    return null;
  }

  String? _detectBrandFromText(String text) {
    final upper = text.toUpperCase().trim();
    if (upper.startsWith('BOLT')) return 'BOLT';
    if (upper.startsWith('WSH') || upper.startsWith('WHOOSH')) return 'WHOOSH';
    if (upper.startsWith('JET')) return 'JET';
    if (upper.startsWith('YANDEX')) return 'YANDEX';
    return null;
  }

  void _incrementBrandWithQuickLabel(String brand) {
    setState(() {
      _scannedNumbers.insert(0, '[$brand]');
      _competitorCounts[brand] = (_competitorCounts[brand] ?? 0) + 1;
      _scanStatus = 'Добавлен $brand';
      _scanStatusColor = Colors.green;
    });
    _saveScannedNumbers();
  }

  Future<void> _resetFormState() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Сбросить форму?'),
          content: const Text('Все введённые данные, список самокатов, конкурентов и фотографии будут удалены.'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Сбросить', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      setState(() {
        _photos.clear();
        _commentController.clear();
        _reportType = 'before';
        _scannedNumbers.clear();
        _competitorCounts.updateAll((key, value) => 0);
        _scanStatus = 'Ожидание сканирования...';
        _scanStatusColor = Colors.blueAccent;
      });
      _saveScannedNumbers();
      _showMessage('Форма успешно очищена');
    }
  }

  // Unified report photo methods
  Future<void> _takePhoto() async {
    if (_photos.length >= 10) {
      _showMessage('Можно максимум 10 фото');
      return;
    }

    final String? photoPath = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CustomCameraScreen()),
    );

    if (photoPath == null) return;

    if (mounted) setState(() => _isProcessing = true);
    try {
      final geoData = await _fetchGeoAndMapBytes();
      final processedFile =
          await _processPhotoWithOverlay(File(photoPath), geoData);
      if (mounted) {
        setState(() {
          _photos.add(processedFile);
        });
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<Map<String, dynamic>> _fetchGeoAndMapBytes() async {
    String locationStr = 'Гео: недоступно';
    Position? currentPosition;
    Uint8List? mapBytes;

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (serviceEnabled) {
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (permission == LocationPermission.whileInUse ||
            permission == LocationPermission.always) {
          try {
            currentPosition = await Geolocator.getCurrentPosition(
              desiredAccuracy: LocationAccuracy.medium,
              timeLimit: const Duration(seconds: 10),
            );
          } catch (e) {
            currentPosition = await Geolocator.getLastKnownPosition();
          }
          if (currentPosition != null) {
            locationStr =
                'Гео: ${currentPosition.latitude.toStringAsFixed(5)}, ${currentPosition.longitude.toStringAsFixed(5)}';
          }
        } else {
          locationStr = 'Гео: доступ запрещён';
        }
      } else {
        locationStr = 'Гео: сервис отключён';
      }
    } catch (_) {
      locationStr = 'Гео: ошибка';
    }

    if (currentPosition != null) {
      final lat = currentPosition.latitude;
      final lng = currentPosition.longitude;

      final int z = 15;
      final int x = ((lng + 180.0) / 360.0 * (1 << z)).floor();
      final int y = ((1.0 -
                  math.log(math.tan(lat * math.pi / 180.0) +
                          1.0 / math.cos(lat * math.pi / 180.0)) /
                      math.pi) /
              2.0 *
              (1 << z))
          .floor();

      final mapUrls = [
        'https://static-maps.yandex.ru/1.x/?ll=$lng,$lat&z=$z&l=map&size=300,300&pt=$lng,$lat,pm2rdm',
        'https://static-maps.yandex.com/1.x/?ll=$lng,$lat&z=$z&l=map&size=300,300&pt=$lng,$lat,pm2rdm',
        'https://tile1.maps.2gis.com/tiles?x=$x&y=$y&z=$z&v=1',
        'https://a.tile.openstreetmap.org/$z/$x/$y.png',
      ];

      for (final mapUrl in mapUrls) {
        try {
          final response = await http
              .get(Uri.parse(mapUrl))
              .timeout(const Duration(seconds: 5));

          if (response.statusCode == 200) {
            mapBytes = response.bodyBytes;
            break;
          }
        } catch (e) {
          debugPrint('Ошибка загрузки карты с $mapUrl: $e');
        }
      }
    }

    return {
      'locationStr': locationStr,
      'mapBytes': mapBytes,
      'hasGeo': currentPosition != null,
    };
  }

  Future<File> _processPhotoWithOverlay(
      File imageFile, Map<String, dynamic> geoData) async {
    final now = DateTime.now();
    final timeStr =
        '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    final String locationStr = geoData['locationStr'];
    final Uint8List? mapBytes = geoData['mapBytes'];

    final bytes = await imageFile.readAsBytes();
    final original = img.decodeImage(bytes);
    if (original == null) return imageFile;

    final oriented = img.bakeOrientation(original);
    final resized = img.copyResize(oriented, width: 1280);

    // Dynamic map overlay strictly on the bottom-left corner and larger
    if (mapBytes != null) {
      try {
        final mapImg = img.decodeImage(mapBytes);
        if (mapImg != null) {
          final mapW = mapImg.width;
          final mapH = mapImg.height;

          img.drawRect(
            resized,
            x1: 18,
            y1: resized.height - mapH - 22,
            x2: 22 + mapW,
            y2: resized.height - 18,
            color: img.ColorRgb8(255, 255, 255),
            thickness: 2,
          );
          img.compositeImage(
            resized,
            mapImg,
            dstX: 20,
            dstY: resized.height - mapH - 20,
          );
        }
      } catch (e) {
        debugPrint('Ошибка наложения мини-карты: $e');
      }
    }

    // Text: date and geo on bottom right
    final textColor = img.ColorRgb8(255, 255, 255);
    final shadowColor = img.ColorRgb8(0, 0, 0);
    final font = img.arial24;
    const textYOffset = 40;
    final bottomY = resized.height - textYOffset;
    final timeX = resized.width - (timeStr.length * 15) - 20;
    final locationX = resized.width - (locationStr.length * 15) - 20;

    img.drawString(
        resized,
        font: font,
        timeStr,
        x: timeX + 1,
        y: bottomY - 30 + 1,
        color: shadowColor);
    img.drawString(
        resized,
        font: font,
        locationStr,
        x: locationX + 1,
        y: bottomY + 1,
        color: shadowColor);
    img.drawString(
        resized,
        font: font,
        timeStr,
        x: timeX,
        y: bottomY - 30,
        color: textColor);
    img.drawString(
        resized,
        font: font,
        locationStr,
        x: locationX,
        y: bottomY,
        color: textColor);

    final jpeg = img.encodeJpg(resized, quality: 88);
    final outFile = File(
        '${imageFile.path}_map_${DateTime.now().millisecondsSinceEpoch}.jpg');
    return outFile.writeAsBytes(jpeg);
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _sendReport() async {
    final hasCounts = _competitorCounts.values.any((v) => v > 0);
    if (_scannedNumbers.isEmpty && !hasCounts) {
      _showMessage('Сначала отсканируйте или добавьте хотя бы один самокат');
      return;
    }

    if (_photos.isEmpty) {
      _showMessage('Добавьте хотя бы одно фото');
      return;
    }

    setState(() {
      _sending = true;
    });

    final shiftProvider = context.read<ShiftProvider>();
    final profile = shiftProvider.profile ?? {};

    final firstName = profile['firstName'] ?? profile['first_name'];
    final username = profile['username'];
    final telegramId = profile['telegram_id'];

    final employeeName =
        firstName?.toString() ?? username?.toString() ?? 'Пользователь';
    final String? employeeUsername = username?.toString();
    final int? employeeTelegramId = (telegramId is int)
        ? telegramId
        : int.tryParse(telegramId?.toString() ?? '');

    shiftProvider.updateLastReportTime(DateTime.now());
    _showMessage('🚀 Отчёт отправляется в фоне...');

    // Trigger upload
    _performBackgroundUpload(
      reportType: _reportType,
      comment: _commentController.text.trim(),
      scooters: List<String>.from(_scannedNumbers),
      competitorCounts: Map<String, int>.from(_competitorCounts),
      employeeName: employeeName,
      employeeUsername: employeeUsername,
      employeeTelegramId: employeeTelegramId,
      photos: List<File>.from(_photos),
    );

    // Reset view completely
    setState(() {
      _photos.clear();
      _commentController.clear();
      _reportType = 'before';
      _sending = false;
      _scannedNumbers.clear();
      _competitorCounts.updateAll((key, value) => 0);
    });
    _saveScannedNumbers();
  }

  Future<void> _performBackgroundUpload({
    required String reportType,
    required String comment,
    required List<String> scooters,
    required Map<String, int>? competitorCounts,
    required String employeeName,
    required String? employeeUsername,
    required int? employeeTelegramId,
    required List<File> photos,
  }) async {
    try {
      final uri = Uri.parse(AppConfig.reportUploadUrl);
      final request = http.MultipartRequest('POST', uri);

      request.headers['X-Report-Token'] = AppConfig.reportApiToken;
      request.fields['report_type'] = reportType;
      request.fields['comment'] = comment;
      request.fields['scooters'] = jsonEncode(scooters);
      if (competitorCounts != null && competitorCounts.isNotEmpty) {
        request.fields['competitor_scooters'] = jsonEncode(competitorCounts);
      }
      request.fields['employee_name'] = employeeName;

      if (employeeUsername != null && employeeUsername.trim().isNotEmpty) {
        request.fields['employee_username'] = employeeUsername.trim();
      }

      if (employeeTelegramId != null) {
        request.fields['employee_telegram_id'] = employeeTelegramId.toString();
      }

      for (final file in photos) {
        request.files.add(
          await http.MultipartFile.fromPath(
            'photos',
            file.path,
            contentType: MediaType('image', 'jpeg'),
          ),
        );
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        debugPrint('Background report sent successfully');
      } else {
        debugPrint(
            'Error sending background report: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      debugPrint('Exception in background report upload: $e');
    }
  }

  // Widgets
  Widget _infoCard() {
    final shiftProvider = context.read<ShiftProvider>();
    final profile = shiftProvider.profile ?? {};
    final firstName =
        profile['firstName'] ?? profile['first_name'] ?? 'Пользователь';
    final username = profile['username'] ?? '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.green[800]!, Colors.green[600]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.green.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.assignment_rounded, color: Colors.white, size: 24),
              SizedBox(width: 8),
              Text(
                'Создание отчёта',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Сотрудник: $firstName ${username.isNotEmpty ? "(@$username)" : ""}',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionRowWidget() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _isQrScannerOpen = !_isQrScannerOpen;
                });
              },
              icon: Icon(
                _isQrScannerOpen
                    ? Icons.qr_code_rounded
                    : Icons.qr_code_scanner_rounded,
                size: 18,
              ),
              label: Text(
                _isQrScannerOpen ? 'Скрыть QR' : 'Сканировать QR',
                style: const TextStyle(fontSize: 12),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    _isQrScannerOpen ? Colors.orange : Colors.green[700],
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _addNumberManually,
              icon: const Icon(Icons.edit_rounded, size: 18),
              label: const Text('Вручную', style: TextStyle(fontSize: 12)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[600],
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _qrScannerWidget() {
    if (!_isQrScannerOpen) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green[700]!, width: 2),
      ),
      clipBehavior: Clip.hardEdge,
      child: Stack(
        children: [
          SizedBox(
            height: 250,
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
          Positioned(
            bottom: 8,
            right: 8,
            child: ValueListenableBuilder<TorchState>(
              valueListenable: cameraController.torchState,
              builder: (context, state, child) {
                return FloatingActionButton.small(
                  backgroundColor: Colors.black54,
                  onPressed: () => cameraController.toggleTorch(),
                  child: Icon(
                    state == TorchState.on
                        ? Icons.flashlight_off_rounded
                        : Icons.flashlight_on_rounded,
                    color: Colors.white,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Map<String, int> _getSummaryCounts() {
    final Map<String, int> summary = {
      'Yandex': 0,
      'Jet': 0,
      'Whoosh': 0,
      'Bolt': 0,
    };
    int ownCount = 0;
    
    for (final num in _scannedNumbers) {
      bool matched = false;
      for (final brand in summary.keys) {
        if (num.toLowerCase().startsWith('[${brand.toLowerCase()}]')) {
          summary[brand] = (summary[brand] ?? 0) + 1;
          matched = true;
          break;
        }
      }
      if (!matched) {
        ownCount++;
      }
    }
    
    summary['Jet'] = (summary['Jet'] ?? 0) + ownCount;
    return summary;
  }

  Widget _scannedListWidget() {
    final total = _scannedNumbers.length;
    if (total == 0) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final summary = _getSummaryCounts();
    final List<String> parts = [];
    summary.forEach((brand, count) {
      if (count > 0) {
        parts.add('$brand: $count');
      }
    });

    final visibleNumbers = _scannedNumbers.asMap().entries.where((entry) {
      final val = entry.value;
      final isGeneric = val.startsWith('[') && !val.contains(' ');
      return !isGeneric;
    }).toList();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.grey[800]! : Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Список самокатов',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    if (parts.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        parts.join('   •   '),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.greenAccent[400] : Colors.green[700],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              GestureDetector(
                onTap: _clearAllScannedNumbers,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.delete_rounded, size: 16, color: Colors.redAccent),
                    SizedBox(width: 4),
                    Text(
                      'Очистить',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.redAccent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (visibleNumbers.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: visibleNumbers.map((entry) {
                final index = entry.key;
                final number = entry.value;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey[800] : Colors.green[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDark ? Colors.grey[700]! : Colors.green[100]!,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.electric_scooter_rounded, size: 14, color: isDark ? Colors.white70 : Colors.green[700]),
                      const SizedBox(width: 6),
                      Text(
                        number,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.green[900],
                        ),
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: () => _removeScannedNumber(index),
                        child: Icon(
                          Icons.close,
                          size: 14,
                          color: isDark ? Colors.white30 : Colors.green[700],
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _copyAllNumbers,
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: const Text('Копировать список', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: isDark ? Colors.grey[800] : Colors.green[50],
                foregroundColor: isDark ? Colors.white : Colors.green[700],
                elevation: 0,
                minimumSize: const Size(double.infinity, 38),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _competitorsInlineWidget() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final keys = _competitorCounts.keys.toList();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.grey[100],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.grey[800]! : Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Конкуренты рядом',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              if (_competitorCounts.values.any((v) => v > 0))
                GestureDetector(
                  onTap: _clearCompetitorCounts,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.delete_sweep_rounded, size: 16, color: Colors.redAccent),
                      SizedBox(width: 4),
                      Text(
                        'Сбросить',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.redAccent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (keys.isNotEmpty) Expanded(child: _buildCompetitorCard(keys[0], isDark)),
              if (keys.length > 1) const SizedBox(width: 10),
              if (keys.length > 1) Expanded(child: _buildCompetitorCard(keys[1], isDark)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (keys.length > 2) Expanded(child: _buildCompetitorCard(keys[2], isDark)),
              if (keys.length > 3) const SizedBox(width: 10),
              if (keys.length > 3) Expanded(child: _buildCompetitorCard(keys[3], isDark)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCompetitorCard(String key, bool isDark) {
    final count = _competitorCounts[key] ?? 0;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.grey[800]! : Colors.grey[300]!,
        ),
      ),
      child: Column(
        children: [
          Text(
            key,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: () => _removeLastScooterForBrand(key),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey[800] : Colors.red[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.remove, size: 16, color: Colors.red[700]),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => _incrementBrandWithQuickLabel(key),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey[800] : Colors.green[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.add, size: 16, color: Colors.green[700]),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTypeButton(
      {required String value, required String title, required IconData icon}) {
    final selected = _reportType == value;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bg = selected
        ? Colors.green[700]
        : (isDark ? Colors.grey[900] : Colors.white);
    final borderCol = selected
        ? Colors.transparent
        : (isDark ? Colors.grey[800]! : Colors.grey[300]!);
    final textCol =
        selected ? Colors.white : (isDark ? Colors.white70 : Colors.black87);
    final iconCol =
        selected ? Colors.white : (isDark ? Colors.white54 : Colors.grey[600]);

    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() {
            _reportType = value;
          });
        },
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: borderCol,
              width: 1.5,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 24,
                color: iconCol,
              ),
              const SizedBox(height: 6),
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: textCol,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _photosWidget() {
    final reportTitle = _reportType == 'before'
        ? 'Фото ДО начала работы'
        : 'Фото ПОСЛЕ завершения';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: isDark ? Colors.grey[800]! : Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$reportTitle (${_photos.length}/10)',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              if (_isProcessing)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _sending ? null : _takePhoto,
            icon: const Icon(Icons.camera_alt_rounded),
            label: const Text('Сделать фото'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green[700],
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 44),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 12),
          if (_photos.isEmpty && !_isProcessing)
            Container(
              padding: const EdgeInsets.all(16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[850] : Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
                    style: BorderStyle.solid),
              ),
              child: const Text('Нет добавленных фотографий',
                  style: TextStyle(color: Colors.grey, fontSize: 12)),
            ),
          if (_photos.isNotEmpty || _isProcessing) ...[
            const SizedBox(height: 10),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: _photos.length + (_isProcessing ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _photos.length && _isProcessing) {
                  return Container(
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey[850] : Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Center(
                      child: CircularProgressIndicator(),
                    ),
                  );
                }

                final file = _photos[index];
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        image: DecorationImage(
                          image: FileImage(file),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    Positioned(
                      top: -6,
                      right: -6,
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _photos.removeAt(index);
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close,
                              color: Colors.white, size: 12),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _commentWidget() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: isDark ? Colors.grey[800]! : Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Комментарий (необязательно)',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _commentController,
            maxLines: 2,
            style: TextStyle(
                fontSize: 14, color: isDark ? Colors.white : Colors.black87),
            decoration: InputDecoration(
              hintText: 'Опишите детали...',
              hintStyle:
                  TextStyle(color: isDark ? Colors.white30 : Colors.grey[400]),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Создание отчёта'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.redAccent),
            tooltip: 'Очистить всё',
            onPressed: _resetFormState,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _infoCard(),
                    const SizedBox(height: 12),

                    // Actions row (Scan / Manual)
                    _actionRowWidget(),

                    // Expandable QR Scanner view
                    _qrScannerWidget(),

                    // Scan Status Text
                    if (_isQrScannerOpen) ...[
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6.0),
                          child: Text(
                            _scanStatus,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: _scanStatusColor,
                            ),
                          ),
                        ),
                      ),
                    ],

                    // Competitors inline widget
                    _competitorsInlineWidget(),

                    const SizedBox(height: 12),
                    const Text(
                      'Выберите время съёмки',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _buildTypeButton(
                          value: 'before',
                          title: 'ДО работы',
                          icon: Icons.photo_camera_back_outlined,
                        ),
                        const SizedBox(width: 8),
                        _buildTypeButton(
                          value: 'after',
                          title: 'ПОСЛЕ работы',
                          icon: Icons.task_alt_rounded,
                        ),
                      ],
                    ),

                    // Photos widget
                    _photosWidget(),

                    // Comment widget
                    _commentWidget(),

                    // Scanned List View
                    _scannedListWidget(),
                  ],
                ),
              ),
            ),

            // Submit Button
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _sending ? null : _sendReport,
                  icon: _sending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded),
                  label: Text(
                    _sending ? 'Отправка...' : 'Отправить отчёт',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[700],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 2,
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
