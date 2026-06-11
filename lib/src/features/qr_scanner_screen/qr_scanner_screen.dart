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
import 'package:micro_mobility_app/src/core/providers/language_provider.dart';
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
  late MobileScannerController cameraController;

  List<String> _scannedNumbers = [];
  Map<String, int> _competitorCounts = {
    'Yandex': 0,
    'Jet': 0,
    'Whoosh': 0,
    'Bolt': 0,
  };

  late final ValueNotifier<String> _scanStatus;
  final ValueNotifier<Color> _scanStatusColor =
      ValueNotifier<Color>(Colors.blueAccent);

  String? _lastScannedCode;
  Timer? _debounceTimer;

  final TextEditingController _commentController = TextEditingController();
  String _reportType = 'before';
  final List<File> _photos = [];
  bool _sending = false;
  bool _isProcessing = false;
  bool _flashOn = false;
  bool _useLegacyDesign = false;
  bool _isQrScannerOpen = false;

  @override
  void initState() {
    super.initState();
    _scanStatus = ValueNotifier<String>(
        tr(context, 'Ожидание сканирования...', 'Сканерлеуді күту...'));
    cameraController = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      torchEnabled: false,
    );
    _commentController.addListener(_saveBackup);
    _loadBackup();
  }

  @override
  void dispose() {
    _commentController.removeListener(_saveBackup);
    try {
      cameraController.dispose();
    } catch (_) {}
    _debounceTimer?.cancel();
    _commentController.dispose();
    _scanStatus.dispose();
    _scanStatusColor.dispose();
    super.dispose();
  }

  Future<void> _loadBackup() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _useLegacyDesign = prefs.getBool('use_legacy_design') ?? false;
      _scannedNumbers = prefs.getStringList('backup_scannedNumbers') ?? [];
      final compStr = prefs.getString('backup_competitorCounts');
      if (compStr != null) {
        try {
          final Map<String, dynamic> decoded = jsonDecode(compStr);
          _competitorCounts =
              decoded.map((key, value) => MapEntry(key, value as int));
        } catch (_) {}
      }
      _commentController.text = prefs.getString('backup_comment') ?? '';
      _reportType = prefs.getString('backup_reportType') ?? 'before';
      final photoPaths = prefs.getStringList('backup_photos') ?? [];
      for (final p in photoPaths) {
        if (File(p).existsSync()) {
          _photos.add(File(p));
        }
      }
      _flashOn = prefs.getBool('backup_flash') ?? false;
    });
  }

  Future<void> _saveBackup() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('backup_scannedNumbers', _scannedNumbers);
    await prefs.setString(
        'backup_competitorCounts', jsonEncode(_competitorCounts));
    await prefs.setString('backup_comment', _commentController.text);
    await prefs.setString('backup_reportType', _reportType);
    await prefs.setStringList(
        'backup_photos', _photos.map((f) => f.path).toList());
    await prefs.setBool('backup_flash', _flashOn);
  }

  Future<void> _clearBackupAndReset() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(tr(context, 'Сбросить форму?',
              'Форманы бастапқыға қайтару керек пе?')),
          content: Text(tr(
              context,
              'Все введённые данные, список самокатов, конкурентов и фотографии будут удалены.',
              'Барлық енгізілген деректер, самокаттар тізімі, бәсекелестер және суреттер жойылады.')),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(tr(context, 'Отмена', 'Болдырмау')),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(tr(context, 'Сбросить', 'Бастапқыға қайтару'),
                  style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('backup_scannedNumbers');
      await prefs.remove('backup_competitorCounts');
      await prefs.remove('backup_comment');
      await prefs.remove('backup_reportType');
      await prefs.remove('backup_photos');

      setState(() {
        _photos.clear();
        _commentController.clear();
        _reportType = 'before';
        _scannedNumbers.clear();
        _competitorCounts.updateAll((key, value) => 0);
        _scanStatus.value =
            tr(context, 'Ожидание сканирования...', 'Сканерлеуді күту...');
        _scanStatusColor.value = Colors.blueAccent;
      });
      _showMessage(
          tr(context, 'Форма успешно очищена', 'Форма сәтті тазартылды'));
    }
  }

  void _updateStatus(String msg, Color col) {
    _scanStatus.value = msg;
    _scanStatusColor.value = col;
  }

  String _extractNumberFromLink(String link) {
    final whooshRegExp =
        RegExp(r'whoosh\.app\.link\/scooter\?scooter_code=([a-zA-Z0-9]+)');
    final whooshMatch = whooshRegExp.firstMatch(link);
    if (whooshMatch != null && whooshMatch.group(1) != null)
      return whooshMatch.group(1)!;

    final wshRegExp = RegExp(r'wsh\.bike\?s=([a-zA-Z0-9]+)');
    final wshMatch = wshRegExp.firstMatch(link);
    if (wshMatch != null && wshMatch.group(1) != null)
      return wshMatch.group(1)!;

    final urentRegExp = RegExp(r'ure\.su\/j\/s\.(\d+)');
    final urentMatch = urentRegExp.firstMatch(link);
    if (urentMatch != null && urentMatch.group(1) != null)
      return urentMatch.group(1)!;

    final yandexRegExp = RegExp(r'go\.yandex\/scooters\?number=([a-zA-Z0-9]+)');
    final yandexMatch = yandexRegExp.firstMatch(link);
    if (yandexMatch != null && yandexMatch.group(1) != null)
      return yandexMatch.group(1)!;

    final liteRegExp = RegExp(r'lite\.app\.link\/scooters\?id=([a-zA-Z0-9]+)');
    final liteMatch = liteRegExp.firstMatch(link);
    if (liteMatch != null && liteMatch.group(1) != null)
      return liteMatch.group(1)!;

    final boltRegExp = RegExp(r'scooters\.taxify\.eu\/qr\/([a-zA-Z0-9\-]+)');
    final boltMatch = boltRegExp.firstMatch(link);
    if (boltMatch != null && boltMatch.group(1) != null)
      return boltMatch.group(1)!;

    return link.trim();
  }

  void _addNumberManually() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(tr(context, 'Ввод номеров', 'Нөмірлерді енгізу')),
          content: TextField(
            controller: controller,
            maxLines: 5,
            decoration: InputDecoration(
              hintText: tr(
                  context,
                  "Введите номера через пробел или с новой строки",
                  "Нөмірлерді бос орын немесе жаңа жол арқылы енгізіңіз"),
              border: OutlineInputBorder(),
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(tr(context, 'Отмена', 'Болдырмау')),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                final text = controller.text.trim();
                if (text.isNotEmpty) {
                  final lines = text.split(RegExp(r'[\n\s,]+'));
                  for (final line in lines) {
                    if (line.trim().isNotEmpty) {
                      _addScannedNumber(line.trim());
                    }
                  }
                }
              },
              child: Text(tr(context, 'Добавить', 'Қосу')),
            ),
          ],
        );
      },
    );
  }

  String _normalizeBrand(String brand) {
    final upper = brand.toUpperCase().trim();
    if (upper == 'BOLT') return 'Bolt';
    if (upper == 'WHOOSH' || upper == 'WSH') return 'Whoosh';
    if (upper == 'JET') return 'Jet';
    if (upper == 'YANDEX') return 'Yandex';
    return brand;
  }

  void _addScannedNumber(String rawCode) {
    final trimmedInput = rawCode.trim();
    if (trimmedInput.isEmpty) {
      _updateStatus(tr(context, 'Пустой ввод', 'Бос мәлімет'), Colors.red);
      return;
    }

    final batchRegExp = RegExp(
        r'\b(whoosh|jet|bolt|yandex|вуш|джет|болт|яндекс|w|j|b|y)\s+(\d+)\b',
        caseSensitive: false);
    final batchMatch = batchRegExp.firstMatch(trimmedInput);
    if (batchMatch != null) {
      final serviceAlias = batchMatch.group(1)!.toLowerCase();
      final quantity = int.tryParse(batchMatch.group(2)!) ?? 0;

      String? brand;
      if (serviceAlias == 'yandex' ||
          serviceAlias == tr(context, 'яндекс', 'яндекс') ||
          serviceAlias == 'y')
        brand = 'Yandex';
      else if (serviceAlias == 'whoosh' ||
          serviceAlias == tr(context, 'вуш', 'вуш') ||
          serviceAlias == 'w')
        brand = 'Whoosh';
      else if (serviceAlias == 'jet' ||
          serviceAlias == tr(context, 'джет', 'джет') ||
          serviceAlias == 'j')
        brand = 'Jet';
      else if (serviceAlias == 'bolt' ||
          serviceAlias == tr(context, 'болт', 'болт') ||
          serviceAlias == 'b') brand = 'Bolt';

      if (brand != null && quantity > 0) {
        final upperBrand = brand.toUpperCase();
        final normKey = _normalizeBrand(brand);
        setState(() {
          for (int i = 0; i < quantity; i++) {
            _scannedNumbers.insert(0, '[$upperBrand]');
          }
          _competitorCounts[normKey] =
              (_competitorCounts[normKey] ?? 0) + quantity;
        });
        _updateStatus(
            tr(context, 'Добавлено $normKey: $quantity шт.',
                '$normKey қосылды: $quantity дана.'),
            Colors.green);
        _saveBackup();
        return;
      }
    }

    final cleanedNumber = _extractNumberFromLink(trimmedInput);
    if (cleanedNumber.isEmpty) {
      _updateStatus(
          tr(context, 'Не удалось добавить номер',
              'Нөмірді қосу мүмкін болмады'),
          Colors.red);
      return;
    }

    String? detectedBrand = _detectBrandFromLink(trimmedInput);
    String detectedCode = cleanedNumber;

    if (detectedBrand == null) {
      final yandexMatch =
          RegExp(r'\bY\d{5}\b', caseSensitive: false).firstMatch(trimmedInput);
      final wooshMatch =
          RegExp(r'\b([a-zA-Zа-яА-Я]{2}\d{4})\b').firstMatch(trimmedInput);
      final jetMatch =
          RegExp(r'\b(\d{6}|\d{3}-\d{3}|J\d{5})\b', caseSensitive: false).firstMatch(trimmedInput);
      final boltMatch = RegExp(r'\b(\d{4})\b').firstMatch(trimmedInput);

      if (yandexMatch != null) {
        detectedBrand = 'Yandex';
        detectedCode = yandexMatch.group(0)!;
      } else if (wooshMatch != null) {
        detectedBrand = 'Whoosh';
        detectedCode = wooshMatch.group(1) ?? wooshMatch.group(0)!;
      } else if (jetMatch != null) {
        detectedBrand = 'Jet';
        detectedCode = jetMatch.group(1) ?? jetMatch.group(0)!;
      } else if (boltMatch != null) {
        detectedBrand = 'Bolt';
        detectedCode = boltMatch.group(1) ?? boltMatch.group(0)!;
      } else {
        detectedBrand = _detectBrandFromText(trimmedInput);
      }
    }

    if (detectedBrand != null) {
      final normalizedBrand = _normalizeBrand(detectedBrand);
      String cleanVal = detectedCode;
      final upper = trimmedInput.toUpperCase();
      if (normalizedBrand == 'Bolt' && upper.startsWith('BOLT'))
        cleanVal = trimmedInput.substring(4).trim();
      else if (normalizedBrand == 'Whoosh' && upper.startsWith('WHOOSH'))
        cleanVal = trimmedInput.substring(6).trim();
      else if (normalizedBrand == 'Whoosh' && upper.startsWith('WSH'))
        cleanVal = trimmedInput.substring(3).trim();
      else if (normalizedBrand == 'Jet' && upper.startsWith('JET'))
        cleanVal = trimmedInput.substring(3).trim();
      else if (normalizedBrand == 'Yandex' && upper.startsWith('YANDEX'))
        cleanVal = trimmedInput.substring(6).trim();

      if (cleanVal.isEmpty) cleanVal = detectedCode;
      _registerScooterForBrand(normalizedBrand, cleanVal);
      return;
    }

    if (!_scannedNumbers.contains(cleanedNumber)) {
      setState(() {
        _scannedNumbers.insert(0, cleanedNumber);
      });
      _updateStatus(
          tr(context, 'Добавлен: $cleanedNumber', 'Қосылды: $cleanedNumber'),
          Colors.green);
      _saveBackup();
    } else {
      _updateStatus('Номер "$cleanedNumber" уже в списке', Colors.orange);
    }
  }

  void _removeScannedNumber(int index) {
    final item = _scannedNumbers[index];
    setState(() {
      _scannedNumbers.removeAt(index);
      if (item.startsWith('[')) {
        final closeBracket = item.indexOf(']');
        if (closeBracket != -1) {
          final rawBrand = item.substring(1, closeBracket);
          final normKey = _normalizeBrand(rawBrand);
          if (_competitorCounts.containsKey(normKey)) {
            final current = _competitorCounts[normKey] ?? 0;
            if (current > 0) _competitorCounts[normKey] = current - 1;
          }
        }
      }
    });
    _saveBackup();
  }

  void _copyAllNumbers() {
    final hasCounts = _competitorCounts.values.any((v) => v > 0);
    if (_scannedNumbers.isEmpty && !hasCounts) return;

    final List<String> allLines = [];
    if (_scannedNumbers.isNotEmpty) allLines.addAll(_scannedNumbers);
    _competitorCounts.forEach((key, value) {
      if (value > 0) allLines.add('$key: $value');
    });

    Clipboard.setData(ClipboardData(text: allLines.join('\n')));
    _showMessage(
        tr(context, 'Все номера скопированы', 'Барлық нөмірлер көшірілді'));
  }

  void _clearCompetitorCounts() {
    setState(() {
      _competitorCounts.updateAll((key, value) => 0);
      _scannedNumbers.removeWhere((item) => item.startsWith('['));
    });
    _saveBackup();
  }

  void _registerScooterForBrand(String brand, String number) {
    final normKey = _normalizeBrand(brand);
    final upperBrand = normKey.toUpperCase();
    final fullLabel = '[$upperBrand] $number';
    if (_scannedNumbers.contains(fullLabel) ||
        _scannedNumbers.contains(number)) {
      _showMessage(
          tr(context, 'Этот самокат уже добавлен!', 'Бұл самокат қосылған!'));
      return;
    }

    setState(() {
      _scannedNumbers.insert(0, fullLabel);
      _competitorCounts[normKey] = (_competitorCounts[normKey] ?? 0) + 1;
    });
    _updateStatus(
        tr(context, 'Добавлен $normKey: $number', '$normKey қосылды: $number'),
        Colors.green);
    _saveBackup();
  }

  void _removeLastScooterForBrand(String brand) {
    final normKey = _normalizeBrand(brand);
    final upperBrand = normKey.toUpperCase();
    final prefix = '[$upperBrand]';
    int indexToRemove = -1;
    for (int i = _scannedNumbers.length - 1; i >= 0; i--) {
      if (_scannedNumbers[i].startsWith(prefix)) {
        indexToRemove = i;
        break;
      }
    }
    setState(() {
      if (indexToRemove != -1) _scannedNumbers.removeAt(indexToRemove);
      final currentCount = _competitorCounts[normKey] ?? 0;
      if (currentCount > 0) _competitorCounts[normKey] = currentCount - 1;
    });
    _saveBackup();
  }

  String? _detectBrandFromLink(String link) {
    if (link.contains('whoosh.app.link') ||
        link.contains('wsh.bike') ||
        link.contains('wsh.app.link')) return 'WHOOSH';
    if (link.contains('scooters.taxify.eu')) return 'BOLT';
    if (link.contains('go.yandex') || link.contains('yandex')) return 'YANDEX';
    if (link.contains('ure.su') ||
        link.contains('lite.app.link') ||
        link.contains('jet')) return 'JET';
    return null;
  }

  String? _detectBrandFromText(String text) {
    final upper = text.toUpperCase().trim();
    if (upper.startsWith('BOLT')) return 'BOLT';
    if (upper.startsWith('WSH') || upper.startsWith('WHOOSH')) return 'WHOOSH';
    if (upper.startsWith('JET')) return 'JET';
    if (upper.startsWith('YANDEX')) return 'YANDEX';

    if (RegExp(r'^\d{4}$').hasMatch(upper)) return 'BOLT';
    if (RegExp(r'^[A-Z]{2}\d{4}$').hasMatch(upper)) return 'WHOOSH';
    if (RegExp(r'^Y\d{5}$').hasMatch(upper)) return 'YANDEX';
    if (RegExp(r'^\d{6}$').hasMatch(upper) || RegExp(r'^J\d{5}$').hasMatch(upper)) return 'JET';

    return null;
  }

  void _incrementBrandWithQuickLabel(String brand) {
    final normKey = _normalizeBrand(brand);
    final upperBrand = normKey.toUpperCase();
    setState(() {
      _scannedNumbers.insert(0, '[$upperBrand]');
      _competitorCounts[normKey] = (_competitorCounts[normKey] ?? 0) + 1;
    });
    _updateStatus(
        tr(context, 'Добавлен $normKey', '$normKey қосылды'), Colors.green);
    _saveBackup();
  }

  Future<void> _takePhoto() async {
    if (_photos.length >= 10) {
      _showMessage(tr(
          context, 'Можно максимум 10 фото', 'Ең көбі 10 сурет қосуға болады'));
      return;
    }

    try {
      await cameraController.stop();
    } catch (_) {}

    final String? photoPath = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CustomCameraScreen()),
    );

    try {
      if (_isQrScannerOpen) {
        await cameraController.start();
      }
    } catch (_) {}

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
        _saveBackup();
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<Map<String, dynamic>> _fetchGeoAndMapBytes() async {
    String locationStr = tr(context, 'Гео: недоступно', 'Гео: қолжетімсіз');
    Position? currentPosition;
    Uint8List? mapBytes;

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (serviceEnabled) {
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied)
          permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.whileInUse ||
            permission == LocationPermission.always) {
          try {
            currentPosition = await Geolocator.getCurrentPosition(
                desiredAccuracy: LocationAccuracy.medium,
                timeLimit: const Duration(seconds: 10));
          } catch (e) {
            currentPosition = await Geolocator.getLastKnownPosition();
          }
          if (currentPosition != null)
            locationStr = tr(
                context,
                'Гео: ${currentPosition.latitude.toStringAsFixed(5)}, ${currentPosition.longitude.toStringAsFixed(5)}',
                'Гео: ${currentPosition.latitude.toStringAsFixed(5)}, ${currentPosition.longitude.toStringAsFixed(5)}');
        } else {
          locationStr = tr(context, 'Гео: доступ запрещён', 'Гео: рұқсат жоқ');
        }
      } else {
        locationStr =
            tr(context, 'Гео: сервис отключён', 'Гео: сервис өшірілген');
      }
    } catch (_) {
      locationStr = tr(context, 'Гео: ошибка', 'Гео: қате');
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
        'https://static-maps.yandex.ru/1.x/?ll=$lng,$lat&z=$z&l=map&size=450,450&pt=$lng,$lat,pm2rdm',
        'https://static-maps.yandex.com/1.x/?ll=$lng,$lat&z=$z&l=map&size=450,450&pt=$lng,$lat,pm2rdm',
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
        } catch (_) {}
      }
    }
    return {
      'locationStr': locationStr,
      'mapBytes': mapBytes,
      'hasGeo': currentPosition != null
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

    var oriented = img.bakeOrientation(original);
    final resized = img.copyResize(oriented, width: 1280);

    if (mapBytes != null) {
      try {
        var mapImg = img.decodeImage(mapBytes);
        if (mapImg != null) {
          mapImg = img.copyResize(mapImg, width: 450);
          final mapW = mapImg.width;
          final mapH = mapImg.height;
          img.drawRect(resized,
              x1: 18,
              y1: resized.height - mapH - 22,
              x2: 22 + mapW,
              y2: resized.height - 18,
              color: img.ColorRgb8(255, 255, 255),
              thickness: 2);
          img.compositeImage(resized, mapImg,
              dstX: 20, dstY: resized.height - mapH - 20);
        }
      } catch (_) {}
    }

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
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.only(bottom: 80, left: 16, right: 16),
        duration: const Duration(milliseconds: 2000),
      ),
    );
  }

  Future<void> _sendReport() async {
    final shiftProvider = context.read<ShiftProvider>();
    final hasCounts = _competitorCounts.values.any((v) => v > 0);

    if (_scannedNumbers.isEmpty && !hasCounts) {
      _showMessage(tr(
          context,
          'Сначала отсканируйте или добавьте хотя бы один самокат',
          'Алдымен кем дегенде бір самокат қосыңыз не сканерлеңіз'));
      return;
    }
    if (_photos.isEmpty) {
      _showMessage(tr(context, 'Добавьте хотя бы одно фото',
          'Кем дегенде бір сурет қосыңыз'));
      return;
    }

    setState(() {
      _sending = true;
    });
    var profile = shiftProvider.profile;
    if (profile == null || profile.isEmpty) {
      profile = await shiftProvider.loadProfile() ?? {};
    }
    
    final firstName = profile['firstName'] ?? profile['first_name'];
    final username = profile['username'];
    final telegramId = profile['telegram_id'];

    final fallbackUsername = shiftProvider.currentUsername ?? shiftProvider.activeShift?.username;
    final employeeUsername = username?.toString() ?? fallbackUsername;
    
    String employeeName = firstName?.toString() ?? '';
    if (employeeName.isEmpty || employeeName.trim() == '') {
      employeeName = employeeUsername ?? 'Сотрудник';
    }

    final employeeTelegramId = (telegramId is int)
        ? telegramId
        : int.tryParse(telegramId?.toString() ?? '');

    shiftProvider.updateLastReportTime(DateTime.now());
    _showMessage(tr(context, '🚀 Отчёт отправляется в фоне...',
        '🚀 Есеп фондық режимде жіберілуде...'));

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

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('backup_scannedNumbers');
    await prefs.remove('backup_competitorCounts');
    await prefs.remove('backup_comment');
    await prefs.remove('backup_reportType');
    await prefs.remove('backup_photos');

    setState(() {
      _photos.clear();
      _commentController.clear();
      _reportType = 'before';
      _sending = false;
      _scannedNumbers.clear();
      _competitorCounts.updateAll((key, value) => 0);
    });
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
          await http.MultipartFile.fromPath('photos', file.path,
              contentType: MediaType('image', 'jpeg')),
        );
      }
      final response = await http.Response.fromStream(await request.send());
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

  void _showAddScootersSheet() {
    FocusScope.of(context).unfocus();
    if (_flashOn) {
      Future.delayed(const Duration(milliseconds: 500), () async {
        try {
          await cameraController.toggleTorch();
        } catch (_) {}
      });
    }

    _isQrScannerOpen = true;

    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;
          return Container(
              height: MediaQuery.of(ctx).size.height * 0.88,
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[900] : Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(children: [
                Container(
                  margin: EdgeInsets.only(top: 12, bottom: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey[400],
                      borderRadius: BorderRadius.circular(2)),
                ),
                Text(tr(context, 'Добавление самокатов', 'Самокаттарды қосу'),
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                SizedBox(height: 12),
                Expanded(
                    child: SingleChildScrollView(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Column(children: [
                          _qrScannerWidget(),
                          ValueListenableBuilder<String>(
                              valueListenable: _scanStatus,
                              builder: (context, status, child) {
                                return Padding(
                                  padding: EdgeInsets.symmetric(vertical: 8.0),
                                  child: Center(
                                    child: Text(status,
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                            color: _scanStatusColor.value)),
                                  ),
                                );
                              }),
                          SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.pop(ctx);
                                _addNumberManually();
                              },
                              icon: Icon(Icons.edit_rounded),
                              label: Text(
                                  tr(context, 'Ввести номера вручную',
                                      'Нөмірлерді қолмен енгізу'),
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue[600],
                                foregroundColor: Colors.white,
                                padding: EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14)),
                              ),
                            ),
                          ),
                          SizedBox(height: 16),
                          _competitorsInlineWidget(),
                          SizedBox(height: 32),
                        ])))
              ]));
        }).then((_) {
      _isQrScannerOpen = false;
      try {
        cameraController.stop();
      } catch (_) {}
      setState(() {});
    });
  }

  Widget _qrScannerWidget() {
    return Container(
      height: 250,
      margin: EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green[700]!, width: 2),
      ),
      clipBehavior: Clip.hardEdge,
      child: Stack(
        children: [
          MobileScanner(
            controller: cameraController,
            onDetect: (capture) {
              if (_sending || _isProcessing) return;
              for (final barcode in capture.barcodes) {
                if (barcode.rawValue != null &&
                    barcode.rawValue != _lastScannedCode) {
                  _lastScannedCode = barcode.rawValue;
                  _addScannedNumber(barcode.rawValue!);
                  _debounceTimer?.cancel();
                  _debounceTimer = Timer(const Duration(seconds: 2), () {
                    if (mounted) {
                      setState(() {
                        _lastScannedCode = null;
                      });
                    }
                  });
                }
              }
            },
          ),
          Positioned(
            bottom: 8,
            right: 8,
            child: StatefulBuilder(builder: (context, setLocalState) {
              return FloatingActionButton.small(
                backgroundColor: Colors.black54,
                onPressed: () async {
                  try {
                    await cameraController.toggleTorch();
                  } catch (_) {}
                  setLocalState(() {
                    _flashOn = !_flashOn;
                  });
                  _saveBackup();
                },
                child: Icon(
                  _flashOn
                      ? Icons.flashlight_on_rounded
                      : Icons.flashlight_off_rounded,
                  color: Colors.white,
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _competitorsInlineWidget() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final keys = _competitorCounts.keys.toList();

    return StatefulBuilder(builder: (context, setSheetState) {
      return Container(
        margin: EdgeInsets.symmetric(vertical: 8),
        padding: EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? Colors.grey[900] : Colors.grey[100],
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
                    tr(context, 'Конкуренты рядом',
                        'Жақын маңдағы бәсекелестер'),
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                if (_competitorCounts.values.any((v) => v > 0))
                  GestureDetector(
                    onTap: () {
                      _clearCompetitorCounts();
                      setSheetState(() {});
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.delete_sweep_rounded,
                            size: 16, color: Colors.redAccent),
                        SizedBox(width: 4),
                        Text(tr(context, 'Сбросить', 'Бастапқыға қайтару'),
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.redAccent,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
              ],
            ),
            SizedBox(height: 12),
            Row(
              children: [
                if (keys.isNotEmpty)
                  Expanded(
                      child:
                          _buildCompetitorCard(keys[0], isDark, setSheetState)),
                if (keys.length > 1) SizedBox(width: 10),
                if (keys.length > 1)
                  Expanded(
                      child:
                          _buildCompetitorCard(keys[1], isDark, setSheetState)),
              ],
            ),
            SizedBox(height: 10),
            Row(
              children: [
                if (keys.length > 2)
                  Expanded(
                      child:
                          _buildCompetitorCard(keys[2], isDark, setSheetState)),
                if (keys.length > 3) SizedBox(width: 10),
                if (keys.length > 3)
                  Expanded(
                      child:
                          _buildCompetitorCard(keys[3], isDark, setSheetState)),
              ],
            ),
          ],
        ),
      );
    });
  }

  Widget _buildCompetitorCard(
      String key, bool isDark, void Function(void Function()) setSheetState) {
    final count = _competitorCounts[key] ?? 0;
    return Container(
      padding: EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: isDark ? Colors.grey[800]! : Colors.grey[300]!),
      ),
      child: Column(
        children: [
          Text(key,
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: isDark ? Colors.white : Colors.black87)),
          SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: () {
                  _removeLastScooterForBrand(key);
                  setSheetState(() {});
                },
                child: Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: isDark ? Colors.grey[800] : Colors.red[50],
                      borderRadius: BorderRadius.circular(8)),
                  child: Icon(Icons.remove, size: 16, color: Colors.red[700]),
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 14),
                child: Text('$count',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87)),
              ),
              GestureDetector(
                onTap: () {
                  _incrementBrandWithQuickLabel(key);
                  setSheetState(() {});
                },
                child: Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: isDark ? Colors.grey[800] : Colors.green[50],
                      borderRadius: BorderRadius.circular(8)),
                  child: Icon(Icons.add, size: 16, color: Colors.green[700]),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoCard() {
    final shiftProvider = context.read<ShiftProvider>();
    final profile = shiftProvider.profile ?? {};
    final firstName = profile['firstName'] ??
        profile['first_name'] ??
        tr(context, 'Пользователь', 'Қолданушы');
    final username = profile['username'] ?? '';

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16),
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
              offset: Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.assignment_rounded, color: Colors.white, size: 24),
              SizedBox(width: 8),
              Text(tr(context, 'Создание отчёта', 'Есеп жасау'),
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18)),
            ],
          ),
          SizedBox(height: 8),
          Text(
              'Сотрудник: $firstName ${username.isNotEmpty ? "(@$username)" : ""}',
              style: TextStyle(color: Colors.white70, fontSize: 14)),
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
      'Other': 0
    };
    for (final num in _scannedNumbers) {
      final clean = num.trim();
      final upper = clean.toUpperCase();
      bool matched = false;
      for (final brand in ['Yandex', 'Jet', 'Whoosh', 'Bolt']) {
        if (upper.startsWith('[${brand.toUpperCase()}]')) {
          summary[brand] = (summary[brand] ?? 0) + 1;
          matched = true;
          break;
        }
      }
      if (!matched) {
        String rawNum = upper;
        if (upper.startsWith('[')) {
          final closeIdx = upper.indexOf(']');
          if (closeIdx != -1) rawNum = upper.substring(closeIdx + 1).trim();
        }
        if (RegExp(r'^\d{4}$').hasMatch(rawNum))
          summary['Bolt'] = (summary['Bolt'] ?? 0) + 1;
        else if (RegExp(r'^[A-Z]{2}\d{4}$').hasMatch(rawNum))
          summary['Whoosh'] = (summary['Whoosh'] ?? 0) + 1;
        else if (RegExp(r'^Y\d{5}$').hasMatch(rawNum))
          summary['Yandex'] = (summary['Yandex'] ?? 0) + 1;
        else if (RegExp(r'^\d{6}$').hasMatch(rawNum))
          summary['Jet'] = (summary['Jet'] ?? 0) + 1;
        else
          summary['Other'] = (summary['Other'] ?? 0) + 1;
      }
    }
    return summary;
  }

  Widget _scannedListWidget() {
    final total = _scannedNumbers.length;
    if (total == 0) return SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final summary = _getSummaryCounts();
    final List<String> parts = [];
    summary.forEach((brand, count) {
      if (count > 0) parts.add('$brand: $count');
    });

    final visibleNumbers = _scannedNumbers
        .asMap()
        .entries
        .where((entry) =>
            !entry.value.startsWith('[') || entry.value.contains(' '))
        .toList();

    return Container(
      margin: EdgeInsets.symmetric(vertical: 8),
      padding: EdgeInsets.all(16),
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr(context, 'Список самокатов', 'Самокаттар тізімі'),
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                    if (parts.isNotEmpty) ...[
                      SizedBox(height: 6),
                      Text(parts.join('   •   '),
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: isDark
                                  ? Colors.greenAccent[400]
                                  : Colors.green[700])),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (visibleNumbers.isNotEmpty) ...[
            SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: visibleNumbers.map((entry) {
                final index = entry.key;
                final number = entry.value;
                return Container(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey[800] : Colors.green[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: isDark ? Colors.grey[700]! : Colors.green[100]!),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.electric_scooter_rounded,
                          size: 14,
                          color: isDark ? Colors.white70 : Colors.green[700]),
                      SizedBox(width: 6),
                      Text(number,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color:
                                  isDark ? Colors.white : Colors.green[900])),
                      SizedBox(width: 6),
                      GestureDetector(
                        onTap: () => _removeScannedNumber(index),
                        child: Icon(Icons.close,
                            size: 14,
                            color: isDark ? Colors.white30 : Colors.green[700]),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _photosActionWidget() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(tr(context, 'Фотографии отчета', 'Есеп суреттері'),
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _sending || _isProcessing
                ? null
                : () {
                    FocusScope.of(context).unfocus();
                    setState(() {
                      _reportType = 'before';
                    });
                    _saveBackup();
                    _takePhoto();
                  },
            icon: Icon(Icons.photo_camera_back_outlined),
            label: Text(tr(context, 'Добавить ДО', 'ДЕЙІН сурет қосу')),
            style: ElevatedButton.styleFrom(
              backgroundColor: _reportType == 'before'
                  ? Colors.green[700]
                  : Colors.grey[400],
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 56),
              padding: EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        SizedBox(width: 8),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _sending || _isProcessing
                ? null
                : () {
                    FocusScope.of(context).unfocus();
                    setState(() {
                      _reportType = 'after';
                    });
                    _saveBackup();
                    _takePhoto();
                  },
            icon: Icon(Icons.task_alt_rounded),
            label: Text(tr(context, 'Добавить ПОСЛЕ', 'СОҢғы сурет қосу')),
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  _reportType == 'after' ? Colors.green[700] : Colors.grey[400],
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 56),
              padding: EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ]),
      SizedBox(height: 12),
      _photosGridWidget(),
    ]);
  }

  Widget _photosGridWidget() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? Colors.grey[900] : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border:
              Border.all(color: isDark ? Colors.grey[800]! : Colors.grey[200]!),
        ),
        child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(
                tr(context, 'Загружено фото: ${_photos.length}/10',
                    'Жүктелген сурет: ${_photos.length}/10'),
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            if (_isProcessing)
              SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2)),
          ]),
          if (_photos.isEmpty && !_isProcessing)
            Padding(
              padding: EdgeInsets.only(top: 16),
              child: Text(
                  tr(context, 'Нет добавленных фотографий',
                      'Қосылған суреттер жоқ'),
                  style: TextStyle(color: Colors.grey, fontSize: 13)),
            ),
          if (_photos.isNotEmpty || _isProcessing)
            Padding(
                padding: EdgeInsets.only(top: 16),
                child: GridView.builder(
                    shrinkWrap: true,
                    physics: NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemCount: _photos.length + (_isProcessing ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _photos.length && _isProcessing) {
                        return Container(
                          decoration: BoxDecoration(
                              color:
                                  isDark ? Colors.grey[850] : Colors.grey[100],
                              borderRadius: BorderRadius.circular(12)),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      final file = _photos[index];
                      return Stack(clipBehavior: Clip.none, children: [
                        GestureDetector(
                          onTap: () {
                            showDialog(
                                context: context,
                                builder: (_) => Dialog.fullscreen(
                                    backgroundColor: Colors.black,
                                    child: Stack(children: [
                                      InteractiveViewer(
                                          child:
                                              Center(child: Image.file(file))),
                                      Positioned(
                                          top: 40,
                                          right: 20,
                                          child: IconButton(
                                            icon: Icon(Icons.close,
                                                color: Colors.white, size: 30),
                                            onPressed: () =>
                                                Navigator.pop(context),
                                          ))
                                    ])));
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              image: DecorationImage(
                                  image: FileImage(file), fit: BoxFit.cover),
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
                                  _saveBackup();
                                },
                                child: Container(
                                  padding: EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                      color: Colors.red,
                                      shape: BoxShape.circle),
                                  child: Icon(Icons.close,
                                      color: Colors.white, size: 12),
                                )))
                      ]);
                    }))
        ]));
  }

  Widget _commentWidget() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: EdgeInsets.symmetric(vertical: 8),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: isDark ? Colors.grey[800]! : Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              tr(context, 'Комментарий (необязательно)',
                  'Пікір (міндетті емес)'),
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          SizedBox(height: 8),
          TextField(
            controller: _commentController,
            maxLines: 2,
            style: TextStyle(
                fontSize: 14, color: isDark ? Colors.white : Colors.black87),
            decoration: InputDecoration(
              hintText:
                  tr(context, 'Опишите детали...', 'Мәліметтерді жазыңыз...'),
              hintStyle:
                  TextStyle(color: isDark ? Colors.white30 : Colors.grey[400]),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: EdgeInsets.all(12),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleQrScanner() async {
    final nextState = !_isQrScannerOpen;
    setState(() {
      _isQrScannerOpen = nextState;
    });
    try {
      if (nextState) {
        if (_flashOn) {
          Future.delayed(const Duration(milliseconds: 500), () async {
            try {
              await cameraController.toggleTorch();
            } catch (_) {}
          });
        }
      } else {
        try {
          await cameraController.stop();
        } catch (_) {}
      }
    } catch (_) {}
  }

  Widget _actionRowWidget() {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _toggleQrScanner,
              icon: Icon(
                  _isQrScannerOpen
                      ? Icons.qr_code_rounded
                      : Icons.qr_code_scanner_rounded,
                  size: 18),
              label: Text(
                  _isQrScannerOpen
                      ? tr(context, 'Скрыть QR', 'QR жасыру')
                      : tr(context, 'Сканировать QR', 'QR сканерлеу'),
                  style: TextStyle(fontSize: 12)),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    _isQrScannerOpen ? Colors.orange : Colors.green[700],
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          SizedBox(width: 6),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _addNumberManually,
              icon: Icon(Icons.edit_rounded, size: 18),
              label: Text(tr(context, 'Вручную', 'Қолмен'),
                  style: TextStyle(fontSize: 12)),
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

  Widget _buildLegacyScannerAndCompetitors() {
    return Column(
      children: [
        _actionRowWidget(),
        if (_isQrScannerOpen) _qrScannerWidget(),
        if (_isQrScannerOpen)
          ValueListenableBuilder<String>(
              valueListenable: _scanStatus,
              builder: (context, status, child) {
                return Padding(
                  padding: EdgeInsets.symmetric(vertical: 6.0),
                  child: Center(
                    child: Text(status,
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: _scanStatusColor.value)),
                  ),
                );
              }),
        _competitorsInlineWidget(),
      ],
    );
  }

  Widget _buildLegacyTypeButton(
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
          _saveBackup();
        },
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderCol, width: 1.5),
          ),
          child: Column(
            children: [
              Icon(icon, size: 24, color: iconCol),
              SizedBox(height: 6),
              Text(title,
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: textCol)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLegacyPhotosActionWidget() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tr(context, 'Выберите время съёмки', 'Түсіру уақытын таңдаңыз'),
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        SizedBox(height: 8),
        Row(
          children: [
            _buildLegacyTypeButton(
                value: 'before',
                title: tr(context, 'ДО работы', 'Жұмысқа ДЕЙІН'),
                icon: Icons.photo_camera_back_outlined),
            SizedBox(width: 8),
            _buildLegacyTypeButton(
                value: 'after',
                title: tr(context, 'ПОСЛЕ работы', 'Жұмыстан СОҢ'),
                icon: Icons.task_alt_rounded),
          ],
        ),
        SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: _sending || _isProcessing
              ? null
              : () {
                  FocusScope.of(context).unfocus();
                  _takePhoto();
                },
          icon: Icon(Icons.camera_alt_rounded),
          label: Text(tr(context, 'Сделать фото', 'Суретке түсіру')),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green[700],
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 44),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        SizedBox(height: 12),
        _photosGridWidget(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'Создание отчёта', 'Есеп жасау')),
        centerTitle: true,
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'toggle_design') {
                final newValue = !_useLegacyDesign;
                SharedPreferences.getInstance().then(
                    (prefs) => prefs.setBool('use_legacy_design', newValue));
                setState(() {
                  _useLegacyDesign = newValue;
                });
              } else if (value == 'clear') {
                _clearBackupAndReset();
              }
            },
            itemBuilder: (BuildContext context) => [
              PopupMenuItem(
                value: 'toggle_design',
                child: Row(
                  children: [
                    Icon(_useLegacyDesign ? Icons.toggle_on : Icons.toggle_off,
                        color: Colors.blue),
                    SizedBox(width: 8),
                    Text(_useLegacyDesign
                        ? tr(context, 'Новый дизайн', 'Жаңа дизайн')
                        : tr(context, 'Старый дизайн', 'Ескі дизайн')),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'clear',
                child: Row(
                  children: [
                    Icon(Icons.refresh_rounded, color: Colors.redAccent),
                    SizedBox(width: 8),
                    Text(tr(context, 'Очистить всё', 'Барлығын өшіру')),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _infoCard(),
                    SizedBox(height: 12),
                    if (_useLegacyDesign)
                      _buildLegacyScannerAndCompetitors()
                    else
                      Column(
                        children: [
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _showAddScootersSheet,
                              icon: Icon(Icons.qr_code_scanner_rounded),
                              label: Text(
                                  tr(context, 'Добавить самокаты',
                                      'Самокаттар қосу'),
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue[700],
                                foregroundColor: Colors.white,
                                minimumSize: const Size.fromHeight(56),
                                padding: EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14)),
                              ),
                            ),
                          ),
                          SizedBox(height: 8),
                        ],
                      ),
                    _scannedListWidget(),
                    SizedBox(height: 8),
                    if (_useLegacyDesign)
                      _buildLegacyPhotosActionWidget()
                    else
                      _photosActionWidget(),
                    _commentWidget(),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: (_sending || _isProcessing) ? null : _sendReport,
                  icon: _sending
                      ? SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : Icon(Icons.send_rounded, size: 24),
                  label: Text(
                    _sending
                        ? tr(context, 'Отправка...', 'Жіберілуде...')
                        : tr(context, 'Отправить отчёт', 'Есеп жіберу'),
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[700],
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(60),
                    padding: EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
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
