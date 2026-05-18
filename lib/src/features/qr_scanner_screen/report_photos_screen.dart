// import 'dart:convert';
// import 'dart:io';
// import 'dart:math' as math;
// import 'dart:typed_data';
// import 'dart:ui' as ui;

// import 'package:flutter/material.dart';
// import 'package:geolocator/geolocator.dart';
// import 'package:http/http.dart' as http;
// import 'package:http_parser/http_parser.dart';
// import 'package:image/image.dart' as img;
// import 'package:image_picker/image_picker.dart';
// import 'package:micro_mobility_app/src/core/config/app_config.dart';

// import 'custom_camera_screen.dart';

// class ReportPhotosScreen extends StatefulWidget {
//   final List<String> scooterNumbers;
//   final Map<String, int>? competitorCounts;
//   final String employeeName;
//   final String? employeeUsername;
//   final int? employeeTelegramId;

//   const ReportPhotosScreen({
//     super.key,
//     required this.scooterNumbers,
//     this.competitorCounts,
//     required this.employeeName,
//     this.employeeUsername,
//     this.employeeTelegramId,
//   });

//   @override
//   State<ReportPhotosScreen> createState() => _ReportPhotosScreenState();
// }

// class _ReportPhotosScreenState extends State<ReportPhotosScreen> {
//   final ImagePicker _picker = ImagePicker();
//   final TextEditingController _commentController = TextEditingController();

//   String _reportType = 'before';
//   final List<File> _photos = [];
//   bool _sending = false;
//   bool _isProcessing = false;

//   ThemeData get _theme => Theme.of(context);
//   ColorScheme get _colors => _theme.colorScheme;

//   Future<void> _pickImages() async {
//     if (_photos.length >= 10) {
//       _showMessage('Можно максимум 10 фото');
//       return;
//     }

//     final picked = await _picker.pickMultiImage();

//     if (picked.isEmpty) return;

//     final remain = 10 - _photos.length;
//     final selectedFiles = picked.take(remain).map((e) => File(e.path)).toList();

//     if (picked.length > remain) {
//       _showMessage('Добавлены только первые 10 фото');
//     }

//     if (mounted) setState(() => _isProcessing = true);
//     try {
//       final geoData = await _fetchGeoAndMapBytes();
//       final processed = await Future.wait(
//         selectedFiles.map((f) => _processPhotoWithOverlay(f, geoData)),
//       );
//       if (mounted) {
//         setState(() {
//           _photos.addAll(processed);
//         });
//       }
//     } finally {
//       if (mounted) setState(() => _isProcessing = false);
//     }
//   }

//   Future<void> _takePhoto() async {
//     if (_photos.length >= 10) {
//       _showMessage('Можно максимум 10 фото');
//       return;
//     }

//     final String? photoPath = await Navigator.push(
//       context,
//       MaterialPageRoute(builder: (_) => const CustomCameraScreen()),
//     );

//     if (photoPath == null) return;

//     if (mounted) setState(() => _isProcessing = true);
//     try {
//       final geoData = await _fetchGeoAndMapBytes();
//       final processedFile =
//           await _processPhotoWithOverlay(File(photoPath), geoData);
//       if (mounted) {
//         setState(() {
//           _photos.add(processedFile);
//         });
//       }
//     } finally {
//       if (mounted) setState(() => _isProcessing = false);
//     }
//   }

//   Future<Map<String, dynamic>> _fetchGeoAndMapBytes() async {
//     String locationStr = 'Гео: недоступно';
//     Position? currentPosition;
//     Uint8List? mapBytes;

//     try {
//       bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
//       if (serviceEnabled) {
//         LocationPermission permission = await Geolocator.checkPermission();
//         if (permission == LocationPermission.denied) {
//           permission = await Geolocator.requestPermission();
//         }
//         if (permission == LocationPermission.whileInUse ||
//             permission == LocationPermission.always) {
//           try {
//             currentPosition = await Geolocator.getCurrentPosition(
//               desiredAccuracy: LocationAccuracy.medium,
//               timeLimit: const Duration(seconds: 10),
//             );
//           } catch (e) {
//             currentPosition = await Geolocator.getLastKnownPosition();
//           }
//           if (currentPosition != null) {
//             locationStr =
//                 'Гео: ${currentPosition.latitude.toStringAsFixed(5)}, ${currentPosition.longitude.toStringAsFixed(5)}';
//           }
//         } else {
//           locationStr = 'Гео: доступ запрещён';
//         }
//       } else {
//         locationStr = 'Гео: сервис отключён';
//       }
//     } catch (_) {
//       locationStr = 'Гео: ошибка';
//     }

//     if (currentPosition != null) {
//       final lat = currentPosition.latitude;
//       final lng = currentPosition.longitude;

//       final int z = 15;
//       final int x = ((lng + 180.0) / 360.0 * (1 << z)).floor();
//       final int y = ((1.0 - math.log(math.tan(lat * math.pi / 180.0) + 1.0 / math.cos(lat * math.pi / 180.0)) / math.pi) / 2.0 * (1 << z)).floor();

//       final mapUrls = [
//         // 1. Yandex Static Maps (с красной меткой, 300x300)
//         'https://static-maps.yandex.ru/1.x/?ll=$lng,$lat&z=$z&l=map&size=300,300&pt=$lng,$lat,pm2rdm',
//         // 2. Yandex Com резервный
//         'https://static-maps.yandex.com/1.x/?ll=$lng,$lat&z=$z&l=map&size=300,300&pt=$lng,$lat,pm2rdm',
//         // 3. 2GIS Tile (без метки, 256x256)
//         'https://tile1.maps.2gis.com/tiles?x=$x&y=$y&z=$z&v=1',
//         // 4. OSM Tile (без метки, 256x256)
//         'https://a.tile.openstreetmap.org/$z/$x/$y.png',
//       ];

//       for (final mapUrl in mapUrls) {
//         try {
//           final response = await http
//               .get(Uri.parse(mapUrl))
//               .timeout(const Duration(seconds: 5));

//           if (response.statusCode == 200) {
//             mapBytes = response.bodyBytes;
//             break; // Успешно загрузили карту, выходим
//           }
//         } catch (e) {
//           debugPrint('Ошибка загрузки карты с $mapUrl: $e');
//         }
//       }
//     }

//     return {
//       'locationStr': locationStr,
//       'mapBytes': mapBytes,
//       'hasGeo': currentPosition != null,
//     };
//   }

//   Future<File> _processPhotoWithOverlay(
//       File imageFile, Map<String, dynamic> geoData) async {
//     final now = DateTime.now();
//     final timeStr =
//         '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year} '
//         '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

//     final String locationStr = geoData['locationStr'];
//     final Uint8List? mapBytes = geoData['mapBytes'];
//     final bool hasGeo = geoData['hasGeo'];

//     final bytes = await imageFile.readAsBytes();
//     final original = img.decodeImage(bytes);
//     if (original == null) return imageFile;

//     final oriented = img.bakeOrientation(original);
//     final resized = img.copyResize(oriented, width: 1280);

//     // Мини-карта Яндекс (правый нижний угол)
//     if (mapBytes != null) {
//       try {
//         final mapImg = img.decodeImage(mapBytes);
//         if (mapImg != null) {
//           img.drawRect(
//             resized,
//             x1: resized.width - 182,
//             y1: resized.height - 182,
//             x2: resized.width - 18,
//             y2: resized.height - 18,
//             color: img.ColorRgb8(255, 255, 255),
//             thickness: 2,
//           );
//           img.compositeImage(
//             resized,
//             mapImg,
//             dstX: resized.width - 180,
//             dstY: resized.height - 180,
//           );
//         }
//       } catch (e) {
//         debugPrint('Ошибка наложения мини-карты: $e');
//       }
//     }

//     // Текст: дата и гео
//     final textColor = img.ColorRgb8(255, 255, 255);
//     final shadowColor = img.ColorRgb8(0, 0, 0);
//     final font = img.arial24;
//     final textYOffset = hasGeo ? 210 : 40;
//     final bottomY = resized.height - textYOffset;
//     final timeX = resized.width - (timeStr.length * 15) - 20;
//     final locationX = resized.width - (locationStr.length * 15) - 20;

//     img.drawString(
//         resized,
//         font: font,
//         timeStr,
//         x: timeX + 1,
//         y: bottomY - 30 + 1,
//         color: shadowColor);
//     img.drawString(
//         resized,
//         font: font,
//         locationStr,
//         x: locationX + 1,
//         y: bottomY + 1,
//         color: shadowColor);
//     img.drawString(
//         resized,
//         font: font,
//         timeStr,
//         x: timeX,
//         y: bottomY - 30,
//         color: textColor);
//     img.drawString(
//         resized,
//         font: font,
//         locationStr,
//         x: locationX,
//         y: bottomY,
//         color: textColor);

//     final jpeg = img.encodeJpg(resized, quality: 88);
//     final outFile = File(
//         '${imageFile.path}_map_${DateTime.now().millisecondsSinceEpoch}.jpg');
//     return outFile.writeAsBytes(jpeg);
//   }

//   void _removePhoto(int index) {
//     setState(() {
//       _photos.removeAt(index);
//     });
//   }

//   void _showMessage(String text) {
//     if (!mounted) return;
//     ScaffoldMessenger.of(context).showSnackBar(
//       SnackBar(
//         content: Text(text),
//         behavior: SnackBarBehavior.floating,
//       ),
//     );
//   }

//   Future<void> _sendReport() async {
//     if (_photos.isEmpty) {
//       _showMessage('Добавь хотя бы одно фото');
//       return;
//     }

//     // Показываем уведомление, что процесс пошел
//     ScaffoldMessenger.of(context).showSnackBar(
//       const SnackBar(
//         content: Text('🚀 Отчёт отправляется в фоне...'),
//         backgroundColor: Colors.blue,
//         duration: Duration(seconds: 3),
//       ),
//     );

//     // Сразу закрываем экран, возвращая true
//     Navigator.of(context).pop(true);

//     // Запускаем саму отправку в фоне
//     _performBackgroundUpload(
//       reportType: _reportType,
//       comment: _commentController.text.trim(),
//       scooters: List<String>.from(widget.scooterNumbers),
//       competitorCounts: widget.competitorCounts,
//       employeeName: widget.employeeName,
//       employeeUsername: widget.employeeUsername,
//       employeeTelegramId: widget.employeeTelegramId,
//       photos: List<File>.from(_photos),
//     );
//   }

//   Future<void> _performBackgroundUpload({
//     required String reportType,
//     required String comment,
//     required List<String> scooters,
//     required Map<String, int>? competitorCounts,
//     required String employeeName,
//     required String? employeeUsername,
//     required int? employeeTelegramId,
//     required List<File> photos,
//   }) async {
//     try {
//       final uri = Uri.parse(AppConfig.reportUploadUrl);
//       final request = http.MultipartRequest('POST', uri);

//       request.headers['X-Report-Token'] = AppConfig.reportApiToken;
//       request.fields['report_type'] = reportType;
//       request.fields['comment'] = comment;
//       request.fields['scooters'] = jsonEncode(scooters);
//       if (competitorCounts != null && competitorCounts.isNotEmpty) {
//         request.fields['competitor_scooters'] = jsonEncode(competitorCounts);
//       }
//       request.fields['employee_name'] = employeeName;

//       if (employeeUsername != null && employeeUsername.trim().isNotEmpty) {
//         request.fields['employee_username'] = employeeUsername.trim();
//       }

//       if (employeeTelegramId != null) {
//         request.fields['employee_telegram_id'] = employeeTelegramId.toString();
//       }

//       for (final file in photos) {
//         request.files.add(
//           await http.MultipartFile.fromPath(
//             'photos',
//             file.path,
//             contentType: MediaType('image', 'jpeg'),
//           ),
//         );
//       }

//       final streamedResponse = await request.send();
//       final response = await http.Response.fromStream(streamedResponse);

//       if (response.statusCode >= 200 && response.statusCode < 300) {
//         debugPrint('Background report sent successfully');
//       } else {
//         debugPrint(
//             'Error sending background report: ${response.statusCode} ${response.body}');
//       }
//     } catch (e) {
//       debugPrint('Exception in background report upload: $e');
//     }
//   }

//   @override
//   void dispose() {
//     _commentController.dispose();
//     super.dispose();
//   }

//   Widget _sectionTitle(String text) {
//     return Padding(
//       padding: const EdgeInsets.only(bottom: 10),
//       child: Text(
//         text,
//         style: _theme.textTheme.titleMedium?.copyWith(
//           fontWeight: FontWeight.w800,
//           color: _colors.onSurface,
//         ),
//       ),
//     );
//   }

//   Widget _infoCard() {
//     final username = widget.employeeUsername?.trim() ?? '';

//     return ClipRRect(
//       borderRadius: BorderRadius.circular(24),
//       child: Stack(
//         children: [
//           // Glass effect background
//           Positioned.fill(
//             child: BackdropFilter(
//               filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
//               child: Container(
//                 decoration: BoxDecoration(
//                   color: _colors.primaryContainer.withOpacity(0.7),
//                   borderRadius: BorderRadius.circular(24),
//                   border: Border.all(
//                     color: _colors.primary.withOpacity(0.2),
//                     width: 1.5,
//                   ),
//                 ),
//               ),
//             ),
//           ),
//           Padding(
//             padding: const EdgeInsets.all(20),
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 Row(
//                   children: [
//                     Container(
//                       padding: const EdgeInsets.all(8),
//                       decoration: BoxDecoration(
//                         color: _colors.primary.withOpacity(0.2),
//                         borderRadius: BorderRadius.circular(12),
//                       ),
//                       child: Icon(Icons.person_outline_rounded,
//                           color: _colors.onPrimaryContainer, size: 24),
//                     ),
//                     const SizedBox(width: 12),
//                     Expanded(
//                       child: Column(
//                         crossAxisAlignment: CrossAxisAlignment.start,
//                         children: [
//                           Text(
//                             widget.employeeName,
//                             style: _theme.textTheme.titleLarge?.copyWith(
//                               fontWeight: FontWeight.w900,
//                               color: _colors.onPrimaryContainer,
//                               letterSpacing: -0.5,
//                             ),
//                           ),
//                           if (username.isNotEmpty)
//                             Text(
//                               '@$username',
//                               style: _theme.textTheme.bodyMedium?.copyWith(
//                                 color:
//                                     _colors.onPrimaryContainer.withOpacity(0.7),
//                                 fontWeight: FontWeight.w600,
//                               ),
//                             ),
//                         ],
//                       ),
//                     ),
//                   ],
//                 ),
//                 const Divider(height: 32, thickness: 0.5),
//                 Row(
//                   children: [
//                     Icon(Icons.electric_scooter,
//                         color: _colors.onPrimaryContainer.withOpacity(0.6),
//                         size: 20),
//                     const SizedBox(width: 8),
//                     Expanded(
//                       child: Text(
//                         widget.scooterNumbers.isEmpty
//                             ? 'Самокаты не выбраны'
//                             : 'Самокаты: ${widget.scooterNumbers.join(', ')}',
//                         style: _theme.textTheme.bodyMedium?.copyWith(
//                           color: _colors.onPrimaryContainer,
//                           fontWeight: FontWeight.w700,
//                         ),
//                       ),
//                     ),
//                   ],
//                 ),
//                 if (widget.competitorCounts != null &&
//                     widget.competitorCounts!.values.any((v) => v > 0)) ...[
//                   const SizedBox(height: 8),
//                   Row(
//                     crossAxisAlignment: CrossAxisAlignment.start,
//                     children: [
//                       Icon(Icons.compare_arrows_rounded,
//                           color: _colors.onPrimaryContainer.withOpacity(0.6),
//                           size: 20),
//                       const SizedBox(width: 8),
//                       Expanded(
//                         child: Text(
//                           'Введено вручную: ${widget.competitorCounts!.entries.where((e) => e.value > 0).map((e) => '${e.key}: ${e.value}').join(', ')}',
//                           style: _theme.textTheme.bodyMedium?.copyWith(
//                             color: _colors.onPrimaryContainer,
//                             fontWeight: FontWeight.w600,
//                           ),
//                         ),
//                       ),
//                     ],
//                   ),
//                 ],
//               ],
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildTypeButton({
//     required String value,
//     required String title,
//     required IconData icon,
//   }) {
//     final selected = _reportType == value;

//     return Expanded(
//       child: InkWell(
//         borderRadius: BorderRadius.circular(20),
//         onTap: _sending ? null : () => setState(() => _reportType = value),
//         child: AnimatedContainer(
//           duration: const Duration(milliseconds: 250),
//           curve: Curves.easeInOut,
//           padding: const EdgeInsets.symmetric(vertical: 20),
//           decoration: BoxDecoration(
//             gradient: selected
//                 ? LinearGradient(
//                     colors: [Colors.green[700]!, Colors.green[500]!],
//                     begin: Alignment.topLeft,
//                     end: Alignment.bottomRight,
//                   )
//                 : null,
//             color: selected
//                 ? null
//                 : _colors.surfaceContainerHighest.withOpacity(0.5),
//             borderRadius: BorderRadius.circular(20),
//             boxShadow: selected
//                 ? [
//                     BoxShadow(
//                       color: Colors.green.withOpacity(0.3),
//                       blurRadius: 10,
//                       offset: const Offset(0, 4),
//                     )
//                   ]
//                 : null,
//             border: Border.all(
//               color: selected ? Colors.transparent : _colors.outlineVariant,
//               width: 1.5,
//             ),
//           ),
//           child: Column(
//             children: [
//               Icon(
//                 icon,
//                 size: 28,
//                 color: selected ? Colors.white : _colors.onSurfaceVariant,
//               ),
//               const SizedBox(height: 8),
//               Text(
//                 title,
//                 style: _theme.textTheme.titleMedium?.copyWith(
//                   fontWeight: FontWeight.w900,
//                   color: selected ? Colors.white : _colors.onSurface,
//                 ),
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }

//   Widget _photoCard() {
//     final reportTitle = _reportType == 'before'
//         ? 'Фото ДО начала работы'
//         : 'Фото ПОСЛЕ завершения';

//     return Container(
//       padding: const EdgeInsets.all(20),
//       decoration: BoxDecoration(
//         color: _colors.surface,
//         borderRadius: BorderRadius.circular(24),
//         border: Border.all(color: _colors.outlineVariant.withOpacity(0.5)),
//         boxShadow: [
//           BoxShadow(
//             color: _colors.shadow.withOpacity(0.05),
//             blurRadius: 20,
//             offset: const Offset(0, 10),
//           ),
//         ],
//       ),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Row(
//             children: [
//               Icon(Icons.photo_library_rounded, color: Colors.green[700]),
//               const SizedBox(width: 12),
//               Expanded(
//                 child: Text(
//                   '$reportTitle (${_photos.length}/10)',
//                   style: _theme.textTheme.titleMedium?.copyWith(
//                     fontWeight: FontWeight.w900,
//                     color: _colors.onSurface,
//                   ),
//                 ),
//               ),
//             ],
//           ),
//           const SizedBox(height: 20),
//           Row(
//             children: [
//               Expanded(
//                 child: _actionButton(
//                   onPressed: _sending ? null : _takePhoto,
//                   icon: Icons.camera_alt_rounded,
//                   label: 'Камера',
//                   isPrimary: true,
//                 ),
//               ),
//             ],
//           ),
//           const SizedBox(height: 14),
//           if (_photos.isEmpty && !_isProcessing)
//             Container(
//               width: double.infinity,
//               padding: const EdgeInsets.all(20),
//               decoration: BoxDecoration(
//                 color: _colors.surfaceContainerHighest,
//                 borderRadius: BorderRadius.circular(16),
//                 border: Border.all(color: _colors.outlineVariant),
//               ),
//               child: Column(
//                 children: [
//                   Icon(
//                     Icons.image_not_supported_outlined,
//                     size: 34,
//                     color: _colors.onSurfaceVariant,
//                   ),
//                   const SizedBox(height: 8),
//                   Text(
//                     'Фото пока не добавлены',
//                     textAlign: TextAlign.center,
//                     style: _theme.textTheme.bodyLarge?.copyWith(
//                       fontWeight: FontWeight.w600,
//                       color: _colors.onSurface,
//                     ),
//                   ),
//                   const SizedBox(height: 4),
//                   Text(
//                     'Нужно минимум 1 фото',
//                     style: _theme.textTheme.bodySmall?.copyWith(
//                       color: _colors.onSurfaceVariant,
//                     ),
//                   ),
//                 ],
//               ),
//             )
//           else if (_photos.isNotEmpty || _isProcessing)
//             GridView.builder(
//               shrinkWrap: true,
//               physics: const NeverScrollableScrollPhysics(),
//               itemCount: _photos.length + (_isProcessing ? 1 : 0),
//               gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
//                 crossAxisCount: 3,
//                 mainAxisSpacing: 10,
//                 crossAxisSpacing: 10,
//                 childAspectRatio: 1,
//               ),
//               itemBuilder: (context, index) {
//                 if (_isProcessing && index == _photos.length) {
//                   // Пластина-загрузка
//                   return Container(
//                     decoration: BoxDecoration(
//                       color: _colors.surfaceContainerHighest,
//                       borderRadius: BorderRadius.circular(12),
//                       border: Border.all(color: _colors.outlineVariant),
//                     ),
//                     child: const Center(
//                       child: Column(
//                         mainAxisSize: MainAxisSize.min,
//                         children: [
//                           CircularProgressIndicator(strokeWidth: 2),
//                           SizedBox(height: 6),
//                           Text('загрузка...', style: TextStyle(fontSize: 10)),
//                         ],
//                       ),
//                     ),
//                   );
//                 }
//                 return _buildPhotoTile(index);
//               },
//             ),
//         ],
//       ),
//     );
//   }

//   Widget _buildPhotoTile(int index) {
//     return Stack(
//       children: [
//         Positioned.fill(
//           child: Container(
//             decoration: BoxDecoration(
//               borderRadius: BorderRadius.circular(18),
//               boxShadow: [
//                 BoxShadow(
//                   color: Colors.black.withOpacity(0.1),
//                   blurRadius: 8,
//                   offset: const Offset(0, 4),
//                 ),
//               ],
//             ),
//             child: ClipRRect(
//               borderRadius: BorderRadius.circular(18),
//               child: Image.file(
//                 _photos[index],
//                 fit: BoxFit.cover,
//               ),
//             ),
//           ),
//         ),
//         Positioned(
//           top: 8,
//           right: 8,
//           child: GestureDetector(
//             onTap: _sending ? null : () => _removePhoto(index),
//             child: Container(
//               padding: const EdgeInsets.all(4),
//               decoration: BoxDecoration(
//                 color: Colors.red.withOpacity(0.9),
//                 shape: BoxShape.circle,
//                 boxShadow: [
//                   BoxShadow(
//                     color: Colors.black.withOpacity(0.2),
//                     blurRadius: 4,
//                   ),
//                 ],
//               ),
//               child: const Icon(Icons.close, color: Colors.white, size: 16),
//             ),
//           ),
//         ),
//         Positioned(
//           bottom: 8,
//           left: 8,
//           child: Container(
//             padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
//             decoration: BoxDecoration(
//               color: Colors.black.withOpacity(0.6),
//               borderRadius: BorderRadius.circular(8),
//             ),
//             child: Text(
//               '${index + 1}',
//               style: const TextStyle(
//                 color: Colors.white,
//                 fontSize: 10,
//                 fontWeight: FontWeight.bold,
//               ),
//             ),
//           ),
//         ),
//       ],
//     );
//   }

//   Widget _actionButton({
//     required VoidCallback? onPressed,
//     required IconData icon,
//     required String label,
//     required bool isPrimary,
//   }) {
//     return InkWell(
//       onTap: onPressed,
//       borderRadius: BorderRadius.circular(16),
//       child: Container(
//         height: 54,
//         decoration: BoxDecoration(
//           color: isPrimary ? Colors.green[700] : Colors.transparent,
//           borderRadius: BorderRadius.circular(16),
//           border: isPrimary ? null : Border.all(color: _colors.outlineVariant),
//         ),
//         child: Row(
//           mainAxisAlignment: MainAxisAlignment.center,
//           children: [
//             Icon(icon,
//                 color: isPrimary ? Colors.white : _colors.onSurface, size: 20),
//             const SizedBox(width: 8),
//             Text(
//               label,
//               style: TextStyle(
//                 color: isPrimary ? Colors.white : _colors.onSurface,
//                 fontWeight: FontWeight.bold,
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }

//   Widget _commentField() {
//     return TextField(
//       controller: _commentController,
//       maxLines: 5,
//       enabled: !_sending,
//       style: TextStyle(color: _colors.onSurface),
//       decoration: InputDecoration(
//         hintText: 'Например: грязный, разбито крыло, нужна замена',
//         hintStyle: TextStyle(color: _colors.onSurfaceVariant),
//         filled: true,
//         fillColor: _colors.surfaceContainerLow,
//         border: OutlineInputBorder(
//           borderRadius: BorderRadius.circular(16),
//           borderSide: BorderSide(color: _colors.outlineVariant),
//         ),
//         enabledBorder: OutlineInputBorder(
//           borderRadius: BorderRadius.circular(16),
//           borderSide: BorderSide(color: _colors.outlineVariant),
//         ),
//         focusedBorder: OutlineInputBorder(
//           borderRadius: BorderRadius.circular(16),
//           borderSide: BorderSide(
//             color: _colors.primary,
//             width: 2,
//           ),
//         ),
//       ),
//     );
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Stack(children: [
//       Scaffold(
//         appBar: AppBar(
//           title: const Text('Фотоотчёт'),
//           centerTitle: true,
//         ),
//         body: SafeArea(
//           child: Column(
//             children: [
//               Expanded(
//                 child: ListView(
//                   padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
//                   children: [
//                     _infoCard(),
//                     const SizedBox(height: 24),
//                     _sectionTitle('Шаг 1: Выберите время съёмки'),
//                     Row(
//                       children: [
//                         _buildTypeButton(
//                           value: 'before',
//                           title: 'ДО работы',
//                           icon: Icons.photo_camera_back_outlined,
//                         ),
//                         const SizedBox(width: 12),
//                         _buildTypeButton(
//                           value: 'after',
//                           title: 'ПОСЛЕ работы',
//                           icon: Icons.task_alt_rounded,
//                         ),
//                       ],
//                     ),
//                     const SizedBox(height: 24),
//                     _sectionTitle('Шаг 2: Сделайте фотографии'),
//                     _photoCard(),
//                     const SizedBox(height: 24),
//                     _sectionTitle('Шаг 3: Напишите комментарий (если нужно)'),
//                     _commentField(),
//                     const SizedBox(height: 24),
//                   ],
//                 ),
//               ),
//               SafeArea(
//                 top: false,
//                 child: Padding(
//                   padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
//                   child: InkWell(
//                     onTap: _sending ? null : _sendReport,
//                     borderRadius: BorderRadius.circular(22),
//                     child: AnimatedContainer(
//                       duration: const Duration(milliseconds: 300),
//                       height: 64,
//                       width: double.infinity,
//                       decoration: BoxDecoration(
//                         gradient: _sending
//                             ? LinearGradient(
//                                 colors: [Colors.grey[700]!, Colors.grey[600]!])
//                             : LinearGradient(
//                                 colors: [
//                                   Colors.green[700]!,
//                                   Colors.green[500]!
//                                 ],
//                                 begin: Alignment.topLeft,
//                                 end: Alignment.bottomRight,
//                               ),
//                         borderRadius: BorderRadius.circular(22),
//                         boxShadow: [
//                           BoxShadow(
//                             color: (_sending ? Colors.grey : Colors.green)
//                                 .withOpacity(0.3),
//                             blurRadius: 15,
//                             offset: const Offset(0, 8),
//                           ),
//                         ],
//                       ),
//                       child: Center(
//                         child: _sending
//                             ? const CircularProgressIndicator(
//                                 color: Colors.white)
//                             : Row(
//                                 mainAxisAlignment: MainAxisAlignment.center,
//                                 children: [
//                                   const Icon(Icons.send_rounded,
//                                       color: Colors.white),
//                                   const SizedBox(width: 12),
//                                   Text(
//                                     'Отправить отчёт',
//                                     style:
//                                         _theme.textTheme.titleMedium?.copyWith(
//                                       color: Colors.white,
//                                       fontWeight: FontWeight.w900,
//                                       letterSpacing: 0.5,
//                                     ),
//                                   ),
//                                 ],
//                               ),
//                       ),
//                     ),
//                   ),
//                 ),
//               ),
//             ],
//           ),
//         ),
//       )
//     ]);
//   }
// }
