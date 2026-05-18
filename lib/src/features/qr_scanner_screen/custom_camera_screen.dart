import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
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

class _CustomCameraScreenState extends State<CustomCameraScreen> with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _isCameraInitialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.overlayType == CameraOverlayType.landscape) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
    _initCamera();
  }

  bool _isDisposed = false;

  Future<void> _initCamera() async {
    if (_isDisposed) return;
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty || _isDisposed) return;

      CameraDescription? selectedCamera;
      if (widget.overlayType == CameraOverlayType.helmetSelfie) {
        selectedCamera = _cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.front,
          orElse: () => _cameras.first,
        );
      } else {
        selectedCamera = _cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.back,
          orElse: () => _cameras.first,
        );
      }

      final controller = CameraController(
        selectedCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await controller.initialize();

      if (_isDisposed) {
        await controller.dispose();
        return;
      }

      if (mounted) {
        setState(() {
          _controller = controller;
          _isCameraInitialized = true;
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
    if (widget.overlayType == CameraOverlayType.landscape) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    }
    // Null out first so any incoming callbacks after dispose() are ignored
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

  Future<void> _takePicture() async {
    if (!_controller!.value.isInitialized || _controller!.value.isTakingPicture) {
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
              child: ClipRect(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isPortrait = constraints.maxHeight > constraints.maxWidth;
                    final effectiveRatio = isPortrait
                        ? (1 / _controller!.value.aspectRatio)
                        : _controller!.value.aspectRatio;
                    final screenRatio = constraints.maxWidth / constraints.maxHeight;
                    final scale = screenRatio > effectiveRatio
                        ? screenRatio / effectiveRatio
                        : effectiveRatio / screenRatio;

                    return Transform.scale(
                      scale: scale,
                      child: Center(
                        child: CameraPreview(_controller!),
                      ),
                    );
                  },
                ),
              ),
            ),
            if (widget.overlayType == CameraOverlayType.landscape)
              Positioned.fill(
                child: CustomPaint(painter: LandscapeOverlayPainter()),
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
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    widget.overlayType == CameraOverlayType.landscape 
                        ? 'Поверните телефон горизонтально\nдля отчета'
                        : 'Сделайте селфи в каске/шлеме',
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
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
                icon: const Icon(Icons.arrow_back, color: Colors.white, size: 30),
                onPressed: () => Navigator.pop(context),
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
                        decoration: const BoxDecoration(
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
      ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(16)))
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(path, paint);

    final borderPaint = Paint()
      ..color = Colors.green
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
      
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(16)), borderPaint);
  }

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
    final helmetBottomY = headCY - headH * 0.30; // каска опускается на 30% головы
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
