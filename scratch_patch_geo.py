import os

file_path = "lib/src/core/services/geo_tracking_service.dart"

with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# 1. Замена периодического таймера с 5 на 15 секунд
target_1 = """  // Запускаем таймер сбора данных
  _backgroundTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {"""

replacement_1 = """  // Запускаем таймер сбора данных
  _backgroundTimer = Timer.periodic(const Duration(seconds: 15), (timer) async {"""

# 2. Оптимизация LocationSettings и graceful fallback в сборе геоданных
target_2 = """    try {
      final LocationSettings locationSettings;
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        locationSettings = AppleSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 0,
          allowBackgroundLocationUpdates: true,
          showBackgroundLocationIndicator: true,
          pauseLocationUpdatesAutomatically: false,
          activityType: ActivityType.otherNavigation,
          timeLimit: const Duration(seconds: 4),
        );
      } else {
        locationSettings = const LocationSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 0,
          timeLimit: Duration(seconds: 6),
        );
      }

      position = await Geolocator.getCurrentPosition(
        locationSettings: locationSettings,
      );
    } catch (e) {
      _log("Ошибка получения позиции: $e. Пробуем последнюю известную...");
      final lastPos = await Geolocator.getLastKnownPosition();
      if (lastPos != null) {
        position = lastPos;
      } else {
        return;
      }
    }"""

replacement_2 = """    try {
      final LocationSettings locationSettings;
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        locationSettings = AppleSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 0,
          allowBackgroundLocationUpdates: true,
          showBackgroundLocationIndicator: true,
          pauseLocationUpdatesAutomatically: false,
          activityType: ActivityType.otherNavigation,
          timeLimit: const Duration(seconds: 8),
        );
      } else {
        locationSettings = const LocationSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 0,
          timeLimit: Duration(seconds: 10),
        );
      }

      position = await Geolocator.getCurrentPosition(
        locationSettings: locationSettings,
      );
    } catch (e) {
      _log("Ошибка получения лучшей позиции: $e. Пробуем получить сбалансированную точность...");
      try {
        final fallbackSettings = LocationSettings(
          accuracy: LocationAccuracy.medium,
          distanceFilter: 0,
          timeLimit: const Duration(seconds: 5),
        );
        position = await Geolocator.getCurrentPosition(
          locationSettings: fallbackSettings,
        );
      } catch (fallbackError) {
        _log("Ошибка fallback-позиции: $fallbackError. Пробуем последнюю известную...");
        final lastPos = await Geolocator.getLastKnownPosition();
        if (lastPos != null) {
          position = lastPos;
        } else {
          return;
        }
      }
    }"""

# Применяем автозамены
content = content.replace(target_1.replace("\r\n", "\n"), replacement_1)
content = content.replace(target_1.replace("\n", "\r\n"), replacement_1.replace("\n", "\r\n"))

content = content.replace(target_2.replace("\r\n", "\n"), replacement_2)
content = content.replace(target_2.replace("\n", "\r\n"), replacement_2.replace("\n", "\r\n"))

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)

print("Successfully patched geo_tracking_service.dart!")
