// lib/config.dart

class AppConfig {
  /// Основной хост бэкенда (без слеша на конце!)
  static const String backendHost = 'https://eom-sharing.duckdns.org';

  /// Базовый путь к API
  static const String apiBasePath = '/api';

  /// Полный базовый URL API
  static String get apiBaseUrl => '$backendHost$apiBasePath';

  /// Базовый URL для медиа (фото, аватарки и т.п.)
  static String get mediaBaseUrl => backendHost;

  // === AUTH ===
  static String get loginUrl => '$apiBaseUrl/auth/login';
  static String get refreshTokenUrl => '$apiBaseUrl/auth/refresh';
  static String get logoutUrl => '$apiBaseUrl/logout';
  static String get telegramAuthUrl => '$apiBaseUrl/auth/telegram';

  /// Страница входа через Telegram
  static String get telegramLoginUrl => '$backendHost/telegram-login.html';

  /// Имя Telegram-бота
  static const String botUsername = 'eom_auth_bot';

  // === PROFILE ===
  static String get profileUrl => '$apiBaseUrl/profile';

  // === SHIFTS & SLOTS ===
  static String get shiftsUrl => '$apiBaseUrl/shifts';
  static String get activeShiftUrl => '$apiBaseUrl/shifts/active';
  static String get startSlotUrl => '$apiBaseUrl/slot/start';
  static String get endSlotUrl => '$apiBaseUrl/slot/end';
  static String get positionsUrl => '$apiBaseUrl/slots/positions';
  static String get timeSlotsUrl => '$apiBaseUrl/slots/times';
  static String get zonesUrl => '$apiBaseUrl/slots/zones';

  // === TELEGRAM & STATS ===
  static String get scooterStatsUrl => '$apiBaseUrl/scooter-stats/shift';
  static String userTelegramIdUrl(int userId) =>
      '$apiBaseUrl/users/$userId/telegram-id';

  // === ADMIN USERS ===
  static String get adminUsersUrl => '$apiBaseUrl/admin/users';
  static String updateUserRoleUrl(int userId) => '$adminUsersUrl/$userId/role';
  static String updateUserStatusUrl(int userId) =>
      '$adminUsersUrl/$userId/status';
  static String deleteUserUrl(int userId) => '$adminUsersUrl/$userId';
  static String forceEndShiftUrl(int userId) =>
      '$adminUsersUrl/$userId/end-shift';

  // === MAPS ===
  static String get adminMapsUrl => '$apiBaseUrl/admin/maps';
  static String get uploadMapUrl => '$adminMapsUrl/upload';
  static String getMapByIdUrl(int mapId) => '$adminMapsUrl/$mapId';
  static String deleteMapUrl(int mapId) => '$adminMapsUrl/$mapId';

  // === DEBUG / ENV INFO ===
  static String get environmentInfo {
    final env = backendHost.contains('duckdns') ? 'DEV' : 'PROD';
    return 'Environment: $env | API: $apiBaseUrl';
  }
}
