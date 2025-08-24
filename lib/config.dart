// lib/config/app_config.dart

class AppConfig {
  /// Основной хост бэкенда (убраны лишние пробелы!)
  static const String backendHost = 'https://eom-sharing.duckdns.org';

  /// Базовый путь API
  static const String apiBasePath = '/api';

  /// Полный базовый URL для API
  static String get apiBaseUrl => '$backendHost$apiBasePath';

  /// Базовый URL для медиа (изображений)
  static String get mediaBaseUrl => backendHost;

  /// URL для входа
  static String get loginUrl => '$apiBaseUrl/auth/login';

  /// URL для обновления токена
  static String get refreshTokenUrl => '$apiBaseUrl/auth/refresh';

  /// URL для выхода
  static String get logoutUrl => '$apiBaseUrl/logout';

  /// URL для Telegram-аутентификации
  static String get telegramAuthUrl => '$apiBaseUrl/auth/telegram';

  /// URL для Telegram-логина (HTML страница)
  static String get telegramLoginUrl => '$backendHost/telegram-login.html';

  /// Имя Telegram-бота
  static const String botUsername = 'eom_auth_bot';

  /// URL профиля пользователя
  static String get profileUrl => '$apiBaseUrl/profile';

  /// URL истории смен
  static String get shiftsUrl => '$apiBaseUrl/shifts';

  /// URL активной смены
  static String get activeShiftUrl => '$apiBaseUrl/shifts/active';

  /// URL старта смены
  static String get startSlotUrl => '$apiBaseUrl/slot/start';

  /// URL завершения смены
  static String get endSlotUrl => '$apiBaseUrl/slot/end';

  /// URL доступных позиций
  static String get positionsUrl => '$apiBaseUrl/slots/positions';

  /// URL доступных временных слотов
  static String get timeSlotsUrl => '$apiBaseUrl/slots/times';

  /// URL доступных зон
  static String get zonesUrl => '$apiBaseUrl/slots/zones';

  /// URL статистики самокатов
  static String get scooterStatsUrl => '$apiBaseUrl/scooter-stats/shift';

  /// URL получения Telegram ID пользователя
  static String userTelegramIdUrl(int userId) =>
      '$apiBaseUrl/users/$userId/telegram-id';

  /// URL управления пользователями (админ)
  static String get adminUsersUrl => '$apiBaseUrl/admin/users';

  /// URL изменения роли пользователя
  static String updateUserRoleUrl(int userId) => '$adminUsersUrl/$userId/role';

  /// URL изменения статуса пользователя
  static String updateUserStatusUrl(int userId) =>
      '$adminUsersUrl/$userId/status';

  /// URL удаления пользователя
  static String deleteUserUrl(int userId) => '$adminUsersUrl/$userId';

  /// URL принудительного завершения смены
  static String forceEndShiftUrl(int userId) =>
      '$adminUsersUrl/$userId/end-shift';

  /// URL управления зонами (админ)
  static String get adminZonesUrl => '$apiBaseUrl/admin/zones';

  /// URL изменения зоны
  static String updateZoneUrl(int id) => '$adminZonesUrl/$id';

  /// URL управления картами (админ)
  static String get adminMapsUrl => '$apiBaseUrl/admin/maps';

  /// URL загрузки карты
  static String get uploadMapUrl => '$adminMapsUrl/upload';

  /// URL получения карты по ID
  static String getMapByIdUrl(int mapId) => '$adminMapsUrl/$mapId';

  /// URL получения файла карты
  static String getMapFileUrl(String fileName) =>
      '$adminMapsUrl/files/$fileName';

  /// URL удаления карты
  static String deleteMapUrl(int mapId) => '$adminMapsUrl/$mapId';

  /// URL генерации смен
  static String get generateShiftsUrl => '$apiBaseUrl/admin/generate-shifts';

  /// Информация о текущем окружении (для отладки)
  static String get environmentInfo {
    final env = backendHost.contains('duckdns') ? 'DEV' : 'PROD';
    return 'Environment: $env | API: $apiBaseUrl';
  }
}
