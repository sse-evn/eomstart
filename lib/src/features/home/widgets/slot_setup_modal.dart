import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:micro_mobility_app/src/core/providers/language_provider.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:micro_mobility_app/src/core/themes/colors.dart';
import 'package:micro_mobility_app/src/core/providers/shift_provider.dart' show ShiftProvider;
import 'package:micro_mobility_app/src/core/services/api_service.dart' show ApiService;
import 'package:provider/provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:micro_mobility_app/src/features/home/bloc/shift_bloc.dart';
import 'package:micro_mobility_app/src/features/home/bloc/shift_event.dart';
import 'package:micro_mobility_app/src/features/home/bloc/shift_state.dart';
import 'package:micro_mobility_app/src/features/qr_scanner_screen/custom_camera_screen.dart';

class SlotSetupModal extends StatefulWidget {
  const SlotSetupModal({super.key});
  @override
  State<SlotSetupModal> createState() => _SlotSetupModalState();
}

class _SlotSetupModalState extends State<SlotSetupModal> {
  final _storage = const FlutterSecureStorage();
  final _picker = ImagePicker();
  final _apiService = ApiService();

  String? _selectedTime;
  String? _position;
  String? _zone;
  XFile? _selfie;
  bool _isLoading = false;
  bool _hasActiveShift = false;
  bool _backendConflict = false;
  List<String> _timeSlots = [];
  List<String> _zones = [];
  String? _token;
  dynamic _activeShift;

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  Future<void> _initializeData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      _token = await _storage.read(key: 'jwt_token');
      if (_token == null) throw Exception(tr(context, 'Требуется авторизация', 'Авторизация қажет'));

      final provider = Provider.of<ShiftProvider>(context, listen: false);
      final activeShift = await provider.getActiveShift();
      if (activeShift != null) {
        setState(() {
          _hasActiveShift = true;
          _backendConflict = true;
          _activeShift = activeShift;
        });
        return;
      }

      final profile = await _retryApiCall(() => _apiService.getUserProfile(_token!));
      String? positionFromProfile;
      for (var key in ['position', 'job_title', 'role', 'dolzhnost', tr(context, 'должность', 'лауазымы')]) {
        if (profile.containsKey(key) && profile[key] != null) {
          positionFromProfile = profile[key].toString();
          break;
        }
      }

      final serverZones = await _retryApiCall(() => _apiService.getAvailableZones(_token!));
      final serverTimeSlots = await _retryApiCall(() => _apiService.getAvailableTimeSlotsForStart(_token!));
      
      // Сортировка зон: сначала числа по возрастанию, затем все остальное
      final uniqueZones = serverZones.toSet().toList();
      uniqueZones.sort((a, b) {
        final aInt = int.tryParse(a);
        final bInt = int.tryParse(b);
        if (aInt != null && bInt != null) return aInt.compareTo(bInt);
        if (aInt != null) return -1;
        if (bInt != null) return 1;
        return a.compareTo(b);
      });

      final defaultZone = uniqueZones.isNotEmpty ? uniqueZones.first : null;

      if (mounted) {
        setState(() {
          _zones = uniqueZones;
          _timeSlots = serverTimeSlots.toSet().toList();
          _position = positionFromProfile ?? tr(context, 'Не указана', 'Көрсетілмеген');
          _zone = defaultZone;
          _selectedTime = _timeSlots.isNotEmpty ? _timeSlots.first : null;
        });
      }
    } catch (e) {
      if (mounted) {
        final errorMessage = e.toString().contains('502')
            ? tr(context, 'Сервер временно недоступен (502). Пожалуйста, попробуйте позже.', 'Сервер уақытша қолжетімсіз (502). Кейінірек қайталап көріңіз.')
            : tr(context, 'Не удалось загрузить данные: ${e.toString()}', 'Деректерді жүктеу мүмкін болмады: ${e.toString()}');
        _showError(errorMessage);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<T> _retryApiCall<T>(Future<T> Function() apiCall) async {
    const maxRetries = 3;
    const retryDelay = Duration(seconds: 2);
    for (var i = 0; i < maxRetries; i++) {
      try {
        return await apiCall();
      } catch (e) {
        if (e.toString().contains('502') && i < maxRetries - 1) {
          await Future.delayed(retryDelay);
          continue;
        }
        rethrow;
      }
    }
    throw Exception('API call failed after $maxRetries retries');
  }

  Future<void> _takeSelfie() async {
    if (_isLoading) return;
    try {
      final String? photoPath = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const CustomCameraScreen(
            overlayType: CameraOverlayType.helmetSelfie,
          ),
        ),
      );
      if (photoPath != null && mounted) setState(() => _selfie = XFile(photoPath));
    } catch (e) {
      if (mounted) _showError(tr(context, 'Не удалось открыть камеру', 'Камераны ашу мүмкін болмады'));
    }
  }

  Future<void> _finish() async {
    if (_hasActiveShift) {
      await _endShift();
    } else {
      await _startNewShift();
    }
  }
  Future<void> _startNewShift() async {
    if (_selfie == null || _token == null) return;
    
    setState(() => _isLoading = true);
    final bloc = BlocProvider.of<ShiftBloc>(context);
    
    try {
      final processedFile = await _processSelfieWithOverlay(File(_selfie!.path));
      
      bloc.add(StartShiftRequested(
        slotTimeRange: _selectedTime!,
        position: _position!,
        zone: _zone!,
        selfie: XFile(processedFile.path),
      ));

      // Ждем изменения состояния BLoC
      final nextState = await bloc.stream.firstWhere(
        (state) => state is ShiftActive || state is ShiftError
      ).timeout(const Duration(seconds: 15), onTimeout: () => ShiftError(tr(context, 'Превышено время ожидания ответа от сервера', 'Сервер жауабын күту уақыты асып кетті')));

      if (mounted) {
        setState(() => _isLoading = false);
        if (nextState is ShiftActive) {
          Navigator.pop(context, true);
          _showSuccess(tr(context, 'Смена успешно открыта', 'Ауысым сәтті ашылды'));
        } else if (nextState is ShiftError) {
          _showError(tr(context, 'Ошибка открытия смены: ${nextState.message}', 'Ауысымды ашу қатесі: ${nextState.message}'));
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showError(tr(context, 'Ошибка: ${e.toString()}', 'Қате: ${e.toString()}'));
      }
    }
  }

  Future<void> _endShift() async {
    if (_token == null) { _showError(tr(context, 'Требуется авторизация', 'Авторизация қажет')); return; }
    try {
      final bloc = BlocProvider.of<ShiftBloc>(context);
      bloc.add(EndShiftRequested());
      
      if (mounted) {
        setState(() {
          _hasActiveShift = false;
          _backendConflict = false;
          _activeShift = null;
        });
        Navigator.pop(context, true);
        _showSuccess(tr(context, 'Запрос на завершение смены отправлен', 'Ауысымды аяқтау сұрауы жіберілді'));
      }
    } catch (e) {
      if (mounted) _showError(tr(context, 'Ошибка при отправке запроса: ${e.toString()}', 'Сұрау жіберу қатесі: ${e.toString()}'));
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: Colors.red,
      behavior: SnackBarBehavior.floating,
    ));
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: Colors.green,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDarkMode = theme.brightness == Brightness.dark;
    
    return PopScope(
      canPop: !_isLoading,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          left: 20,
          right: 20,
          top: 10,
        ),
        decoration: BoxDecoration(
          color: isDarkMode ? Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 20,
              offset: Offset(0, -5),
            )
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle for modal
            Container(
              width: 40,
              height: 4,
              margin: EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            
            Text(
              _hasActiveShift ? tr(context, 'Завершить смену', 'Ауысымды аяқтау') : tr(context, 'Начать новую смену', 'Жаңа ауысым бастау'),
              style: TextStyle(
                fontSize: 22, 
                fontWeight: FontWeight.w900, 
                color: isDarkMode ? Colors.white : Colors.black,
                letterSpacing: -0.5,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 24),
            
            Flexible(
              child: _isLoading
                ? Padding(
                    padding: EdgeInsets.all(40.0),
                    child: CircularProgressIndicator(),
                  )
                : SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_hasActiveShift) 
                          _buildActiveShiftInfo(theme) 
                        else 
                          _buildNewShiftForm(theme, isDarkMode),
                        SizedBox(height: 24),
                        _buildActionButton(theme),
                        SizedBox(height: 8),
                      ],
                    ),
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Future<File> _processSelfieWithOverlay(File imageFile) async {
    final now = DateTime.now();
    final timeStr = '${now.day}.${now.month}.${now.year} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    String locationStr = tr(context, 'Гео: недоступно', 'Гео: қолжетімсіз');
    Position? currentPosition;

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (serviceEnabled) {
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
          currentPosition = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium, timeLimit: const Duration(seconds: 8));
          locationStr = tr(context, 'Гео: ${currentPosition.latitude.toStringAsFixed(5)}, ${currentPosition.longitude.toStringAsFixed(5)}', 'Гео: ${currentPosition.latitude.toStringAsFixed(5)}, ${currentPosition.longitude.toStringAsFixed(5)}');
        } else {
          locationStr = tr(context, 'Гео: доступ запрещён', 'Гео: рұқсат жоқ');
        }
      } else {
        locationStr = tr(context, 'Гео: сервис отключён', 'Гео: сервис өшірілген');
      }
    } catch (_) { locationStr = tr(context, 'Гео: ошибка', 'Гео: қате'); }

    final bytes = await imageFile.readAsBytes();
    final original = img.decodeImage(bytes);
    if (original == null) throw Exception(tr(context, 'Не удалось декодировать изображение', 'Суретті оқу мүмкін болмады'));
    
    final oriented = img.bakeOrientation(original);
    final resized = img.copyResize(oriented, width: 800);
    
    // 🗺️ ДОБАВЛЕНИЕ МИНИ-КАРТЫ
    if (currentPosition != null) {
      try {
        final lat = currentPosition.latitude;
        final lng = currentPosition.longitude;
        final mapUrl = 'https://static-maps.yandex.ru/1.x/?ll=$lng,$lat&z=15&l=map&size=160,160&pt=$lng,$lat,pm2rdm';
        final response = await http.get(Uri.parse(mapUrl)).timeout(const Duration(seconds: 5));
        
        if (response.statusCode == 200) {
          final mapImg = img.decodeImage(response.bodyBytes);
          if (mapImg != null) {
            // Рамка для карты
            img.drawRect(
              resized,
              x1: resized.width - 182,
              y1: resized.height - 182,
              x2: resized.width - 18,
              y2: resized.height - 18,
              color: img.ColorRgb8(255, 255, 255),
              thickness: 2,
            );
            
            img.compositeImage(
              resized,
              mapImg,
              dstX: resized.width - 180,
              dstY: resized.height - 180,
            );
          }
        }
      } catch (e) {
        debugPrint(tr(context, 'Ошибка загрузки мини-карты: $e', 'Мини-картаны жүктеу қатесі: $e'));
      }
    }

    final textColor = img.ColorRgb8(255, 255, 255);
    final shadowColor = img.ColorRgb8(0, 0, 0);
    final font = img.arial24;

    final timeX = resized.width - (timeStr.length * 15) - 20;
    final locationX = resized.width - (locationStr.length * 15) - 20;
    
    final textYOffset = currentPosition != null ? 210 : 40;
    final bottomY = resized.height - textYOffset;

    // Тень
    img.drawString(resized, font: font, timeStr, x: timeX + 1, y: bottomY - 30 + 1, color: shadowColor);
    img.drawString(resized, font: font, locationStr, x: locationX + 1, y: bottomY + 1, color: shadowColor);
    
    // Текст
    img.drawString(resized, font: font, timeStr, x: timeX, y: bottomY - 30, color: textColor);
    img.drawString(resized, font: font, locationStr, x: locationX, y: bottomY, color: textColor);

    final jpeg = img.encodeJpg(resized, quality: 90);
    final tempFile = File('${imageFile.path}_overlay_${DateTime.now().millisecondsSinceEpoch}.jpg');
    return await tempFile.writeAsBytes(jpeg);
  }

  Widget _buildActiveShiftInfo(ThemeData theme) {
    if (_activeShift == null) return SizedBox.shrink();
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.red.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, 
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
              SizedBox(width: 12),
              Text(tr(context, 'Внимание!', 'Назар аударыңыз!'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red[800])),
            ],
          ),
          SizedBox(height: 12),
          Text(tr(context, 'У вас уже есть активная смена. Вы не можете начать новую, пока не завершите текущую.', 'Сізде белсенді ауысым бар. Ағымдағыны аяқтамай жаңасын бастай алмайсыз.'), 
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          SizedBox(height: 16),
          Divider(color: Colors.red.withOpacity(0.1)),
          SizedBox(height: 16),
          if (_activeShift['slot_time_range'] != null) 
            _buildInfoRow(Icons.access_time, tr(context, 'Время', 'Уақыты'), _activeShift['slot_time_range']),
          if (_activeShift['zone'] != null) 
            _buildInfoRow(Icons.location_on_outlined, tr(context, 'Зона', 'Аймақ'), _activeShift['zone']),
          if (_activeShift['position'] != null) 
            _buildInfoRow(Icons.work_outline, tr(context, 'Должность', 'Лауазым'), _activeShift['position']),
        ]
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8.0),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey[600]),
          SizedBox(width: 8),
          Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          SizedBox(width: 8),
          Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildNewShiftForm(ThemeData theme, bool isDarkMode) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Selfie Area
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDarkMode ? Colors.white.withOpacity(0.05) : Colors.grey[50],
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: isDarkMode ? Colors.white.withOpacity(0.1) : Colors.grey[200]!),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(Icons.camera_alt_outlined, size: 20),
                  SizedBox(width: 10),
                  Text(tr(context, 'Фото-подтверждение', 'Сурет-растау'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ],
              ),
              SizedBox(height: 20),
              _selfie != null ? _buildSelfiePreview() : _buildSelfiePlaceholder(isDarkMode),
              SizedBox(height: 20),
              _buildSelfieButton(isDarkMode),
            ],
          ),
        ),
        SizedBox(height: 20),
        
        // Time Slot Area
        if (_timeSlots.isEmpty) 
          _buildNoTimeSlotsWarning(isDarkMode) 
        else 
          _buildTimeSlotsSelection(isDarkMode),
        
        SizedBox(height: 20),
        
        // Zone and Position
        LayoutBuilder(
          builder: (context, constraints) {
            final bool isNarrow = constraints.maxWidth < 350;
            if (isNarrow) {
              return Column(
                children: [
                  _buildInputWrapper(
                    isDarkMode,
                    tr(context, 'Зона', 'Аймақ'),
                    Icons.location_on_outlined,
                    _buildZoneDropdown(isDarkMode),
                  ),
                  SizedBox(height: 16),
                  _buildInputWrapper(
                    isDarkMode,
                    tr(context, 'Должность', 'Лауазым'),
                    Icons.work_outline,
                    _buildPositionField(isDarkMode),
                  ),
                ],
              );
            }
            return Row(
              children: [
                Expanded(
                  child: _buildInputWrapper(
                    isDarkMode,
                    tr(context, 'Зона', 'Аймақ'),
                    Icons.location_on_outlined,
                    _buildZoneDropdown(isDarkMode),
                  ),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: _buildInputWrapper(
                    isDarkMode,
                    tr(context, 'Должность', 'Лауазым'),
                    Icons.work_outline,
                    _buildPositionField(isDarkMode),
                  ),
                ),
              ],
            );
          }
        ),
      ],
    );
  }

  Widget _buildInputWrapper(bool isDarkMode, String label, IconData icon, Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(left: 4, bottom: 8),
          child: Row(
            children: [
              Icon(icon, size: 14, color: Colors.grey[600]),
              SizedBox(width: 6),
              Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey[600])),
            ],
          ),
        ),
        child,
      ],
    );
  }

  Widget _buildPositionField(bool isDarkMode) {
    return TextFormField(
      initialValue: _position ?? tr(context, 'Не указана', 'Көрсетілмеген'),
      readOnly: true,
      decoration: InputDecoration(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        filled: true,
        fillColor: isDarkMode ? Colors.white.withOpacity(0.05) : Colors.grey[100],
      ),
      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    );
  }

  Widget _buildNoTimeSlotsWarning(bool isDarkMode) => Container(
        padding: EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.orange.withOpacity(0.1),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.orange.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), shape: BoxShape.circle),
              child: Icon(Icons.access_time_filled, color: Colors.orange, size: 28),
            ),
            SizedBox(height: 16),
            Text(tr(context, 'Сейчас не время начала смены', 'Қазір ауысым бастау уақыты емес'), 
              textAlign: TextAlign.center, 
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.orange)),
            SizedBox(height: 8),
            Text(tr(context, 'Начало смены доступно только в пределах выбранных слотов.', 'Ауысымды бастау тек таңдалған слоттар ішінде мүмкін.'), 
              textAlign: TextAlign.center, 
              style: TextStyle(color: Colors.grey[600], fontSize: 13)),
            SizedBox(height: 12),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isDarkMode ? Colors.white.withOpacity(0.05) : Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(tr(context, 'Слоты: 07:00–15:00, 15:00–23:00', 'Слоттар: 07:00–15:00, 15:00–23:00'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            ),
          ],
        ),
      );

  Widget _buildTimeSlotsSelection(bool isDarkMode) => Container(
        width: double.infinity,
        padding: EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDarkMode ? Colors.white.withOpacity(0.05) : Colors.grey[50],
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: isDarkMode ? Colors.white.withOpacity(0.1) : Colors.grey[200]!),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.history_toggle_off, size: 20),
                SizedBox(width: 10),
                Text(tr(context, 'Выберите слот', 'Слотты таңдаңыз'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ],
            ),
            SizedBox(height: 16),
            Wrap(
              spacing: 8.0,
              runSpacing: 8.0,
              children: _timeSlots.map((slot) {
                final isSelected = _selectedTime == slot;
                return GestureDetector(
                  onTap: _isLoading ? null : () { if (mounted) setState(() => _selectedTime = slot); },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.green : (isDarkMode ? Colors.white.withOpacity(0.05) : Colors.white),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isSelected ? Colors.green : (isDarkMode ? Colors.white.withOpacity(0.1) : Colors.grey[300]!)),
                      boxShadow: isSelected ? [BoxShadow(color: Colors.green.withOpacity(0.3), blurRadius: 8, offset: Offset(0, 4))] : [],
                    ),
                    child: Text(slot, 
                      style: TextStyle(
                        color: isSelected ? Colors.white : (isDarkMode ? Colors.white : Colors.black),
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        fontSize: 13,
                      )),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      );

  Widget _buildSelfiePreview() => Stack(
        alignment: Alignment.center,
        children: [
          Container(
            height: 180,
            width: 180,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 15)],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: Image.file(File(_selfie!.path), fit: BoxFit.cover),
            ),
          ),
          Positioned(
            top: -5,
            right: -5,
            child: IconButton(
              onPressed: () { if (mounted) setState(() => _selfie = null); },
              icon: Container(
                padding: EdgeInsets.all(4),
                decoration: BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                child: Icon(Icons.close, color: Colors.white, size: 14),
              ),
            ),
          ),
        ],
      );

  Widget _buildSelfiePlaceholder(bool isDarkMode) => Container(
        height: 180,
        width: 180,
        decoration: BoxDecoration(
          color: isDarkMode ? Colors.white.withOpacity(0.02) : Colors.white,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: isDarkMode ? Colors.white.withOpacity(0.1) : Colors.grey[300]!, style: BorderStyle.none),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_outline, size: 64, color: isDarkMode ? Colors.grey[700] : Colors.grey[300]),
            SizedBox(height: 8),
            Text(tr(context, 'Нет фото', 'Сурет жоқ'), style: TextStyle(color: Colors.grey[500], fontSize: 12, fontWeight: FontWeight.bold)),
          ],
        ),
      );

  Widget _buildSelfieButton(bool isDarkMode) => SizedBox(
    width: double.infinity,
    child: ElevatedButton.icon(
          onPressed: _isLoading ? null : _takeSelfie,
          icon: Icon(Icons.add_a_photo_outlined, size: 20),
          label: Text(tr(context, 'Сделать селфи', 'Селфи жасау'), style: TextStyle(fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
            padding: EdgeInsets.symmetric(vertical: 16),
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
  );

  Widget _buildZoneDropdown(bool isDarkMode) {
    final validZone = _zones.contains(_zone) ? _zone : (_zones.isNotEmpty ? _zones.first : null);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.white.withOpacity(0.05) : Colors.grey[100],
        borderRadius: BorderRadius.circular(16),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: validZone,
          isExpanded: true,
          menuMaxHeight: 350,
          items: _zones.map((item) => DropdownMenuItem(
            value: item, 
            child: Container(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Text(item, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600))
            )
          )).toList(),
          onChanged: _isLoading ? null : (String? value) { if (mounted && value != null) setState(() => _zone = value); },
          dropdownColor: isDarkMode ? Color(0xFF2C2C2C) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          icon: Icon(Icons.keyboard_arrow_down_rounded),
        ),
      ),
    );
  }

  Widget _buildActionButton(ThemeData theme) {
    bool canSubmit = !_isLoading && !_hasActiveShift && _selectedTime != null && _selfie != null && _position != null && _zone != null;
    final isEnded = _hasActiveShift;
    
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          if (canSubmit || isEnded)
            BoxShadow(
              color: (isEnded ? Colors.red : Colors.green).withOpacity(0.3),
              blurRadius: 12,
              offset: Offset(0, 6),
            )
        ],
      ),
      child: ElevatedButton(
        onPressed: (isEnded || canSubmit) ? _finish : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: isEnded ? Colors.red : (canSubmit ? Colors.green : Colors.grey[300]),
          foregroundColor: Colors.white,
          disabledBackgroundColor: theme.brightness == Brightness.dark ? Colors.white.withOpacity(0.05) : Colors.grey[200],
          padding: EdgeInsets.symmetric(vertical: 18),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
        child: _isLoading
            ? SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Row(
                mainAxisAlignment: MainAxisAlignment.center, 
                children: [
                  Icon(isEnded ? Icons.power_settings_new : Icons.verified_user_outlined, size: 20),
                  SizedBox(width: 10),
                  Text(
                    isEnded ? tr(context, 'Завершить смену', 'Ауысымды аяқтау') : (canSubmit ? tr(context, 'Начать смену', 'Ауысымды бастау') : tr(context, 'Заполните данные', 'Деректерді толтырыңыз')), 
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 0.2),
                  ),
                ],
              ),
      ),
    );
  }
}
