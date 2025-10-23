// import 'package:geolocator/geolocator.dart';

// class LocationService {
//   /// Определяет текущее местоположение пользователя.
//   /// Запрашивает разрешения и возвращает [Position].
//   Future<Position> determinePosition() async {
//     bool serviceEnabled;
//     LocationPermission permission;

//     // Проверяем, включена ли геолокация
//     serviceEnabled = await Geolocator.isLocationServiceEnabled();
//     if (!serviceEnabled) {
//       throw Exception('Службы геолокации отключены.');
//     }

//     // Проверяем разрешения
//     permission = await Geolocator.checkPermission();
//     if (permission == LocationPermission.denied) {
//       permission = await Geolocator.requestPermission();
//       if (permission == LocationPermission.denied) {
//         throw Exception('Разрешения на геолокацию отклонены.');
//       }
//     }

//     if (permission == LocationPermission.deniedForever) {
//       throw Exception(
//         'Разрешения на геолокацию отклонены навсегда. Измените это в настройках.',
//       );
//     }

//     return await Geolocator.getCurrentPosition();
//   }

//   /// Возвращает поток с обновлениями геопозиции.
//   /// Можно подписаться и получать координаты в реальном времени.
//   Stream<Position> getPositionStream() {
//     const locationSettings = LocationSettings(
//       accuracy: LocationAccuracy.high, // Можно medium/low для экономии батареи
//       distanceFilter: 10, // Обновлять при изменении на 5+ метров
//     );

//     return Geolocator.getPositionStream(locationSettings: locationSettings);
//   }
// }
