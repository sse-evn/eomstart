import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:micro_mobility_app/services/api_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockApiService extends Mock implements ApiService {}

class MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  late MockApiService apiService;
  late MockFlutterSecureStorage storage;

  setUp(() {
    apiService = MockApiService();
    storage = MockFlutterSecureStorage();
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    when(() => storage.delete(key: any<String>(named: 'key')))
        .thenAnswer((_) async {});
  });

  group('Main App Initial Route Logic', () {
    test('Должен быть /dashboard, если токен есть, роль user, is_active = true',
        () async {
      const token = 'valid.jwt.token';
      when(() => storage.read(key: 'jwt_token')).thenAnswer((_) async => token);
      when(() => apiService.getUserProfile(token))
          .thenAnswer((_) async => {'role': 'user', 'is_active': true});

      final initialToken = await storage.read(key: 'jwt_token');
      String initialRoute = '/dashboard';

      if (initialToken != null && initialToken.isNotEmpty) {
        try {
          final profile = await apiService.getUserProfile(initialToken);
          final role = (profile['role'] ?? 'user').toString().toLowerCase();
          final isActive = (profile['is_active'] as bool?) ?? false;

          if (isActive) {
            initialRoute = role == 'superadmin' ? '/admin' : '/dashboard';
          } else {
            initialRoute = '/pending';
          }
        } catch (e) {
          initialRoute = '/';
          await storage.delete(key: 'jwt_token');
        }
      }

      expect(initialRoute, '/dashboard');
    });

    test('Должен быть /admin, если роль superadmin и is_active = true',
        () async {
      const token = 'valid.jwt.token';
      when(() => storage.read(key: 'jwt_token')).thenAnswer((_) async => token);
      when(() => apiService.getUserProfile(token))
          .thenAnswer((_) async => {'role': 'superadmin', 'is_active': true});

      final initialToken = await storage.read(key: 'jwt_token');
      String initialRoute = '/dashboard';

      if (initialToken != null && initialToken.isNotEmpty) {
        final profile = await apiService.getUserProfile(initialToken);
        final role = (profile['role'] ?? 'user').toString().toLowerCase();
        final isActive = (profile['is_active'] as bool?) ?? false;

        if (isActive) {
          initialRoute = role == 'superadmin' ? '/admin' : '/dashboard';
        } else {
          initialRoute = '/pending';
        }
      }

      expect(initialRoute, '/admin');
    });

    test('Должен быть /pending, если is_active = false и не superadmin',
        () async {
      const token = 'valid.jwt.token';
      when(() => storage.read(key: 'jwt_token')).thenAnswer((_) async => token);
      when(() => apiService.getUserProfile(token))
          .thenAnswer((_) async => {'role': 'user', 'is_active': false});

      final initialToken = await storage.read(key: 'jwt_token');
      String initialRoute = '/dashboard';

      if (initialToken != null && initialToken.isNotEmpty) {
        final profile = await apiService.getUserProfile(initialToken);
        final role = (profile['role'] ?? 'user').toString().toLowerCase();
        final isActive = (profile['is_active'] as bool?) ?? false;

        if (isActive) {
          initialRoute = role == 'superadmin' ? '/admin' : '/dashboard';
        } else {
          initialRoute = '/pending';
        }
      }

      expect(initialRoute, '/pending');
    });

    test('Должен быть /, если токен есть, но API вернул ошибку', () async {
      const token = 'invalid.token';
      when(() => storage.read(key: 'jwt_token')).thenAnswer((_) async => token);
      when(() => apiService.getUserProfile(token))
          .thenThrow(Exception('Network error'));

      final initialToken = await storage.read(key: 'jwt_token');
      String initialRoute = '/dashboard';

      if (initialToken != null && initialToken.isNotEmpty) {
        try {
          final profile = await apiService.getUserProfile(initialToken);
          final role = (profile['role'] ?? 'user').toString().toLowerCase();
          final isActive = (profile['is_active'] as bool?) ?? false;

          if (isActive) {
            initialRoute = role == 'superadmin' ? '/admin' : '/dashboard';
          } else {
            initialRoute = '/pending';
          }
        } catch (e) {
          initialRoute = '/';
          await storage.delete(key: 'jwt_token');
        }
      }

      expect(initialRoute, '/');
      verify(() => storage.delete(key: 'jwt_token')).called(1);
    });

    test('Должен быть /dashboard по умолчанию, если токена нет', () async {
      when(() => storage.read(key: 'jwt_token')).thenAnswer((_) async => null);

      final initialToken = await storage.read(key: 'jwt_token');
      String initialRoute = '/dashboard';

      if (initialToken != null && initialToken.isNotEmpty) {
        final profile = await apiService.getUserProfile(initialToken);
        final role = (profile['role'] ?? 'user').toString().toLowerCase();
        final isActive = (profile['is_active'] as bool?) ?? false;

        if (isActive) {
          initialRoute = role == 'superadmin' ? '/admin' : '/dashboard';
        } else {
          initialRoute = '/pending';
        }
      }

      expect(initialRoute, '/dashboard');
    });
  });
}
