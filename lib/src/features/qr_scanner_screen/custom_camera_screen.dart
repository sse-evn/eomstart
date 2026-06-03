import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:micro_mobility_app/src/core/providers/language_provider.dart';
import 'package:flutter/services.dart';

enum CameraOverlayType {
  landscape,
  helmetSelfie,
}

class CustomCameraScreen extends StatefulWidget {
  final CameraOverlayType overlayType;

  const CustomCameraScreen({
    super.key,
    this.overlayType = CameraOverlayType.landscape,
  });

  @override
  State<CustomCameraScreen> createState() => _CustomCameraScreenState();
}

class _CustomCameraScreenState extends State<CustomCameraScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  List<CameraDescription> _backCameras = [];
  int _currentBackCameraIndex = 0;
  bool _isCameraInitialized = false;
  FlashMode _flashMode = FlashMode.off;
  double _minZoomLevel = 1.0;
  double _maxZoomLevel = 1.0;
  double _currentZoomLevel = 1.0;
  double _baseZoomLevel = 1.0;
  Offset? _focusPoint;
  Timer? _focusTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Разрешаем все ориентации на экране камеры, чтобы можно было удобно снимать в любой ориентации
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _initCamera();
  }

  bool _isDisposed = false;

  Future<void> _initCamera() async {
    if (_isDisposed) return;
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty || _isDisposed) return;

      _backCameras = _cameras
          .where((c) => c.lensDirection == CameraLensDirection.back)
          .toList();

      CameraDescription? selectedCamera;
      if (widget.overlayType == CameraOverlayType.helmetSelfie) {
        selectedCamera = _cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.front,
          orElse: () => _cameras.first,
        );
      } else {
        if (_backCameras.isNotEmpty) {
          if (_currentBackCameraIndex >= _backCameras.length) {
            _currentBackCameraIndex = 0;
          }
          selectedCamera = _backCameras[_currentBackCameraIndex];
        } else {
          selectedCamera = _cameras.first;
        }
      }

      final controller = CameraController(
        selectedCamera,
        ResolutionPreset
            .high, // Увеличили качество до High (1080p) для идеальной четкости
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await controller.initialize();

      if (_isDisposed) {
        await controller.dispose();
        return;
      }

      double minZoom = 1.0;
      double maxZoom = 1.0;
      try {
        minZoom = await controller.getMinZoomLevel();
        maxZoom = await controller.getMaxZoomLevel();
      } catch (e) {
        debugPrint('Error getting zoom levels: $e');
      }

      try {
        await controller.setFlashMode(_flashMode);
      } catch (e) {
        debugPrint('Error setting flash mode: $e');
      }

      try {
        if (widget.overlayType == CameraOverlayType.landscape) {
          // Разблокируем ориентацию съемки, чтобы снимок сохранялся в соответствии с тем, как пользователь держит телефон (и вертикально, и горизонтально)
          await controller.unlockCaptureOrientation();
        } else if (widget.overlayType == CameraOverlayType.helmetSelfie) {
          await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
        }
      } catch (e) {
        debugPrint('Error locking/unlocking capture orientation: $e');
      }

      if (mounted) {
        setState(() {
          _controller = controller;
          _isCameraInitialized = true;
          _minZoomLevel = minZoom;
          _maxZoomLevel = maxZoom;
          _currentZoomLevel = 1.0;
        });
      }
    } catch (e) {
      debugPrint('Error initializing camera: $e');
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    WidgetsBinding.instance.removeObserver(this);
    // Возвращаем принудительную портретную ориентацию для остального приложения
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    // Null out first so any incoming callbacks after dispose() are ignored
    _focusTimer?.cancel();
    final c = _controller;
    _controller = null;
    c?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
        // Null out first to prevent callbacks from hitting disposed controller
        final c = _controller;
        _controller = null;
        if (mounted) setState(() => _isCameraInitialized = false);
        c?.dispose();
        break;
      case AppLifecycleState.resumed:
        if (!_isDisposed) _initCamera();
        break;
      default:
        break;
    }
  }

  Future<void> _toggleFlash() async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    try {
      FlashMode newMode;
      if (_flashMode == FlashMode.off) {
        newMode = FlashMode.always;
      } else if (_flashMode == FlashMode.always) {
        newMode = FlashMode.torch;
      } else {
        newMode = FlashMode.off;
      }

      await _controller!.setFlashMode(newMode);
      if (mounted) {
        setState(() {
          _flashMode = newMode;
        });
      }
    } catch (e) {
      debugPrint('Error toggling flash: $e');
    }
  }

  void _handleScaleStart(ScaleStartDetails details) {
    _baseZoomLevel = _currentZoomLevel;
  }

  Future<void> _handleScaleUpdate(ScaleUpdateDetails details) async {
    if (_controller == null || !_isCameraInitialized) return;
    
    double zoomLevel = (_baseZoomLevel * details.scale).clamp(_minZoomLevel, _maxZoomLevel);
        
    if (zoomLevel == _currentZoomLevel) return;

    try {
      await _controller!.setZoomLevel(zoomLevel);
      if (mounted) {
        setState(() {
          _currentZoomLevel = zoomLevel;
        });
      }
    } catch (e) {
      debugPrint('Error scaling zoom: $e');
    }
  }

  void _handleTapToFocus(TapDownDetails details, BoxConstraints constraints) async {
    if (_controller == null || !_isCameraInitialized) return;

    final offset = Offset(
      details.localPosition.dx / constraints.maxWidth,
      details.localPosition.dy / constraints.maxHeight,
    );

    setState(() {
      _focusPoint = details.localPosition;
    });

    try {
      await _controller!.setFocusPoint(offset);
      await _controller!.setExposurePoint(offset);
    } catch (e) {
      debugPrint('Error setting focus: $e');
    }

    _focusTimer?.cancel();
    _focusTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _focusPoint = null;
        });
      }
    });
  }

  Future<void> _toggleZoom() async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    try {
      double targetZoom = 1.0;
      
      if ((_currentZoomLevel - 1.0).abs() < 0.1) {
        // Current is ~1.0x -> Go to 2.0x
        targetZoom = _maxZoomLevel >= 2.0 ? 2.0 : _maxZoomLevel;
      } else if (_currentZoomLevel > 1.1) {
        // Current is ~2.0x -> Go to 0.5x (if supported), else 1.0x
        if (_minZoomLevel < 1.0) {
          targetZoom = _minZoomLevel; 
        } else {
          targetZoom = 1.0;
        }
      } else {
        // Current is < 1.0x (e.g. 0.5x) -> Go to 1.0x
        targetZoom = 1.0;
      }

      await _controller!.setZoomLevel(targetZoom);
      if (mounted) {
        setState(() {
          _currentZoomLevel = targetZoom;
        });
      }
    } catch (e) {
      debugPrint('Error toggling zoom: $e');
    }
  }

  Future<void> _takePicture() async {
    if (!_controller!.value.isInitialized ||
        _controller!.value.isTakingPicture) {
      return;
    }

    try {
      final XFile photo = await _controller!.takePicture();
      if (mounted) {
        Navigator.pop(context, photo.path);
      }
    } catch (e) {
      debugPrint('Error taking picture: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isCameraInitialized || _controller == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: Center(
                child: AspectRatio(
                  aspectRatio:
                      MediaQuery.of(context).orientation == Orientation.portrait
                          ? 1 / _controller!.value.aspectRatio
                          : _controller!.value.aspectRatio,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return GestureDetector(
                        onScaleStart: _handleScaleStart,
                        onScaleUpdate: _handleScaleUpdate,
                        onTapDown: (details) => _handleTapToFocus(details, constraints),
                        child: Stack(
                          children: [
                            CameraPreview(_controller!),
                            if (_focusPoint != null)
                              Positioned(
                                left: _focusPoint!.dx - 25,
                                top: _focusPoint!.dy - 25,
                                child: Container(
                                  width: 50,
                                  height: 50,
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Colors.yellow, width: 2),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),

            if (widget.overlayType == CameraOverlayType.helmetSelfie)
              Positioned.fill(
                child: Opacity(
                  opacity: 0.6,
                  child: Image.asset(
                    'assets/pngegg.png',
                    fit: BoxFit.contain,
                  ),
                ),
              ),

            Positioned(
              top: 20,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding:
                      EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    widget.overlayType == CameraOverlayType.landscape
                        ? tr(context, 'Сделайте фото самоката для отчета', 'Есепке самокат суретін түсіріңіз')
                        : tr(context, 'Сделайте селфи в каске/шлеме', 'Каскада/шлемде селфи жасаңыз'),
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
            // Кнопка назад
            Positioned(
              top: 20,
              left: 20,
              child: IconButton(
                icon:
                    Icon(Icons.arrow_back, color: Colors.white, size: 30),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            // Кнопка вспышки
            Positioned(
              top: 20,
              right: 20,
              child: IconButton(
                icon: Icon(
                  _flashMode == FlashMode.off
                      ? Icons.flash_off
                      : _flashMode == FlashMode.always
                          ? Icons.flash_on
                          : Icons.highlight,
                  color: Colors.white,
                  size: 30,
                ),
                onPressed: _toggleFlash,
              ),
            ),
            // Кнопка переключения зума (1.0x / 2.0x)
            Positioned(
              bottom: 130,
              left: 0,
              right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: _toggleZoom,
                  child: Container(
                    padding:
                        EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white24, width: 1.5),
                    ),
                    child: Text(
                      _currentZoomLevel == 1.0
                          ? '1.0x'
                          : '${_currentZoomLevel.toStringAsFixed(1)}x',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Кнопка переключения физических камер (если есть ширик/телевик)
            if (widget.overlayType == CameraOverlayType.landscape && _backCameras.length > 1)
              Positioned(
                bottom: 130,
                right: 20,
                child: GestureDetector(
                  onTap: () async {
                    if (_isCameraInitialized) {
                      _currentBackCameraIndex = (_currentBackCameraIndex + 1) % _backCameras.length;
                      setState(() => _isCameraInitialized = false);
                      final oldController = _controller;
                      _controller = null;
                      await oldController?.dispose();
                      await _initCamera();
                    }
                  },
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white24, width: 1.5),
                    ),
                    child: Text(
                      'Объектив ${_currentBackCameraIndex + 1}',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),
            // Кнопка съемки
            Positioned(
              bottom: 30,
              left: 0,
              right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: _takePicture,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 4),
                      color: Colors.white.withOpacity(0.3),
                    ),
                    child: Center(
                      child: Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                        ),
                      ),
                    ),
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

class LandscapeOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black54
      ..style = PaintingStyle.fill;

    final isPortrait = size.height > size.width;
    double frameWidth, frameHeight;

    // Рамка всегда должна быть альбомной (горизонтальной)
    if (isPortrait) {
      frameWidth = size.width * 0.85;
      frameHeight = frameWidth * 0.75; // 4:3
    } else {
      frameHeight = size.height * 0.7;
      frameWidth = frameHeight * 1.33; // 4:3
    }

    final left = (size.width - frameWidth) / 2;
    // Сдвигаем рамку чуть выше центра
    final top = (size.height - frameHeight) / 2.5;

    final rect = Rect.fromLTWH(left, top, frameWidth, frameHeight);

    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(16)))
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(path, paint);

    final borderPaint = Paint()
      ..color = Colors.green
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(16)), borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class HelmetOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final dimPaint = Paint()
      ..color = Colors.black54
      ..style = PaintingStyle.fill;

    final cx = size.width / 2;
    final baseCY = size.height * 0.46;

    // === Голова: вертикальный овал ===
    final headW = size.width * 0.52;
    final headH = headW * 1.3;
    final headCY = baseCY + headH * 0.10; // опущен чуть ниже
    final headRect = Rect.fromCenter(
      center: Offset(cx, headCY),
      width: headW,
      height: headH,
    );

    // === Каска: широкий приплюснутый купол ===
    // Нижний край каски перекрывает верхнюю часть головы
    final helmetW = headW * 1.38;
    final helmetH = headW * 0.55; // высота купола (приплюснутый)
    final helmetBottomY =
        headCY - headH * 0.30; // каска опускается на 30% головы
    final helmetTopY = helmetBottomY - helmetH;
    final helmetRect = Rect.fromLTRB(
      cx - helmetW / 2,
      helmetTopY,
      cx + helmetW / 2,
      helmetBottomY,
    );

    // === Единый вырез = голова + каска, объединённые в один Path ===
    final cutoutPath = Path();
    cutoutPath.addOval(headRect);
    // Добавляем прямоугольник-мост между куполом и головой (заполняем зазор)
    cutoutPath.addRect(Rect.fromLTRB(
      cx - headW / 2,
      helmetBottomY,
      cx + headW / 2,
      headCY - headH / 2 + headH * 0.35,
    ));
    // Купол каски (верхний полукруг)
    cutoutPath.addArc(helmetRect, 3.1416, 3.1416);

    // Затемняем всё кроме выреза
    final dimPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addPath(cutoutPath, Offset.zero)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(dimPath, dimPaint);

    // === Зелёная обводка ===
    final border = Paint()
      ..color = Colors.green
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Нижняя дуга головы (видимая часть — от правого края каски до левого, снизу)
    canvas.drawArc(headRect, -0.35, 3.84, false, border);

    // Купол каски
    canvas.drawArc(helmetRect, 3.1416, 3.1416, false, border);

    // Поля каски (горизонтальные линии по бокам)
    final brimY = helmetBottomY;
    canvas.drawLine(
      Offset(cx - helmetW / 2 + 1, brimY),
      Offset(cx - headW / 2 - 2, brimY),
      border,
    );
    canvas.drawLine(
      Offset(cx + headW / 2 + 2, brimY),
      Offset(cx + helmetW / 2 - 1, brimY),
      border,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
