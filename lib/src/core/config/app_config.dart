class AppConfig {
  static const String backendHost = 'https://start.eom.kz';

  static const String apiBasePath = '/api';

  static String get apiBaseUrl => '$backendHost$apiBasePath';
  static String get mediaBaseUrl => backendHost;

  static String get websocketUrl =>
      '${backendHost.replaceFirst('http', 'ws')}/ws';

  static String get loginUrl => '$apiBaseUrl/auth/login';
  static String get refreshTokenUrl => '$apiBaseUrl/auth/refresh';
  static String get logoutUrl => '$apiBaseUrl/logout';
  static String get telegramAuthUrl => '$apiBaseUrl/auth/telegram';
  static String get telegramLoginUrl => '$backendHost/telegram-login.html';

  static const String botUsername = 'eom_auth_bot';

  static String get profileUrl => '$apiBaseUrl/profile';
  static String get shiftsUrl => '$apiBaseUrl/shifts';
  static String get activeShiftUrl => '$apiBaseUrl/shifts/active';
  static String get timeSlotsAvailableForStartUrl =>
      '$apiBaseUrl/time-slots/available-for-start';

  static String get startSlotUrl => '$apiBaseUrl/slot/start';
  static String get endSlotUrl => '$apiBaseUrl/slot/end';

  static String get positionsUrl => '$apiBaseUrl/slots/positions';
  static String get timeSlotsUrl => '$apiBaseUrl/slots/times';
  static String get zonesUrl => '$apiBaseUrl/slots/zones';

  static String get scooterStatsUrl => '$apiBaseUrl/scooter-stats/shift';

  /// URL отправки фото-отчёта
  static String get reportUploadUrl => '$apiBaseUrl/report';

  static String userTelegramIdUrl(int userId) =>
      '$apiBaseUrl/users/$userId/telegram-id';

  static String get adminUsersUrl => '$apiBaseUrl/admin/users';
  static String updateUserRoleUrl(int userId) => '$adminUsersUrl/$userId/role';
  static String updateUserStatusUrl(int userId) =>
      '$adminUsersUrl/$userId/status';
  static String deleteUserUrl(int userId) => '$adminUsersUrl/$userId';
  static String forceEndShiftUrl(int userId) =>
      '$adminUsersUrl/$userId/end-shift';

  static String get adminZonesUrl => '$apiBaseUrl/admin/zones';
  static String updateZoneUrl(int id) => '$adminZonesUrl/$id';

  static String get adminMapsUrl => '$apiBaseUrl/admin/maps';
  static String get uploadMapUrl => '$adminMapsUrl/upload';
  static String getMapByIdUrl(int mapId) => '$adminMapsUrl/$mapId';
  static String getMapFileUrl(String fileName) =>
      '$adminMapsUrl/files/$fileName';
  static String deleteMapUrl(int mapId) => '$adminMapsUrl/$mapId';

  static String get generateShiftsUrl => '$apiBaseUrl/admin/generate-shifts';

  static String get apkDownloadUrl =>
      '$backendHost/uploads/app/app-release.apk';

  static String get promoApplyUrl => '$apiBaseUrl/promo/apply';
  static String get iosAppUrl => '$backendHost/app/your-app';

  static final String geoTrackUrl = '$apiBaseUrl/geo';
  static final String lastLocationsUrl = '$apiBaseUrl/last';
  static final String locationHistoryUrl = '$apiBaseUrl/history';

  static String get environmentInfo {
    final env = backendHost.contains('duckdns') ? 'DEV' : 'PROD';
    return 'Environment: $env | API: $apiBaseUrl | WS: $websocketUrl';
  }

  /// Токен для отправки отчётов
  static const String reportApiToken =
      'sUsPIAllrVoG0yI3Wc08rtMv8XwSBdwUAfJtFVrOFTgjAt7qKWJ7yvAZ5aqh9j7vS1';
}
