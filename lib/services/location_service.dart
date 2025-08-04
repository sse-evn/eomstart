// services/location_service.dart
import 'package:geolocator/geolocator.dart'; // Добавлен импорт geolocator

class LocationService {
  /// Определяет текущее местоположение пользователя.
  /// Запрашивает разрешения на геолокацию и получает позицию.
  ///
  /// Выбрасывает исключения, если службы геолокации отключены
  /// или разрешения не предоставлены.
  Future<Position> determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Проверяем, включены ли службы геолокации.
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // Если службы геолокации отключены, выбрасываем исключение.
      throw Exception('Службы геолокации отключены.');
    }

    // Проверяем статус разрешений на геолокацию.
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      // Если разрешения отклонены, запрашиваем их.
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        // Если разрешения все еще отклонены, выбрасываем исключение.
        throw Exception('Разрешения на геолокацию отклонены.');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      // Если разрешения отклонены навсегда, выбрасываем исключение.
      throw Exception(
          'Разрешения на геолокацию отклонены навсегда, мы не можем запросить разрешения.');
    }

    // Если разрешения получены, получаем текущее местоположение.
    return await Geolocator.getCurrentPosition();
  }

  // TODO: Добавить методы для фонового отслеживания местоположения (Stream)
}
