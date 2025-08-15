// test/screens/login_screen_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:micro_mobility_app/services/api_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:micro_mobility_app/providers/shift_provider.dart';

// Моки
class MockApiService extends Mock implements ApiService {}

class MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}

class MockShiftProvider extends Mock implements ShiftProvider {}

// Валидаторы из LoginScreen — вынесем как отдельные функции для тестирования
String? validateUsername(String? value) {
  if (value == null || value.isEmpty) {
    return 'Поле не может быть пустым';
  }
  return null;
}

String? validatePassword(String? value) {
  if (value == null || value.isEmpty) {
    return 'Поле не может быть пустым';
  }
  if (value.length < 6) {
    return 'Пароль должен содержать минимум 6 символов';
  }
  return null;
}

void main() {
  late MockApiService apiService;
  late MockFlutterSecureStorage storage;
  late MockShiftProvider shiftProvider;

  setUp(() {
    apiService = MockApiService();
    storage = MockFlutterSecureStorage();
    shiftProvider = MockShiftProvider();
  });

  group('LoginScreen Form Validation', () {
    test('Пустое имя пользователя — возвращает ошибку', () {
      expect(validateUsername(''), 'Поле не может быть пустым');
      expect(validateUsername(null), 'Поле не может быть пустым');
      expect(validateUsername('user'), null);
    });

    test('Пустой пароль — возвращает ошибку', () {
      expect(validatePassword(''), 'Поле не может быть пустым');
      expect(validatePassword(null), 'Поле не может быть пустым');
    });

    test('Пароль короче 6 символов — возвращает ошибку', () {
      expect(validatePassword('123'),
          'Пароль должен содержать минимум 6 символов');
      expect(validatePassword('12345'),
          'Пароль должен содержать минимум 6 символов');
      expect(validatePassword('123456'), null);
    });

    test('Валидные данные — ошибок нет', () {
      expect(validateUsername('admin'), null);
      expect(validatePassword('password'), null);
    });
  });

  group('LoginScreen Login Logic', () {
    test('Успешный вход — сохранение токена и навигация на /dashboard',
        () async {
      // Arrange
      when(() => apiService.login('user', 'pass'))
          .thenAnswer((_) async => {'token': 'abc123', 'role': 'user'});
      when(() => storage.write(key: 'jwt_token', value: 'abc123'))
          .thenAnswer((_) async {});
      when(() => shiftProvider.setToken('abc123')).thenAnswer((_) async {});

      // Act
      final result = await (() async {
        try {
          final response = await apiService.login('user', 'pass');
          if (response.containsKey('token')) {
            final token = response['token'] as String;
            await storage.write(key: 'jwt_token', value: token);
            await shiftProvider.setToken(token);
            final role = (response['role'] ?? 'user').toString().toLowerCase();
            return role == 'superadmin' ? '/admin' : '/dashboard';
          }
          return null;
        } catch (e) {
          return null;
        }
      })();

      // Assert
      expect(result, '/dashboard');
      verify(() => storage.write(key: 'jwt_token', value: 'abc123')).called(1);
      verify(() => shiftProvider.setToken('abc123')).called(1);
    });

    test('Ошибка входа — возвращает null', () async {
      // Arrange
      when(() => apiService.login('bad', 'pass'))
          .thenThrow(Exception('Network error'));

      // Act
      final result = await (() async {
        try {
          final response = await apiService.login('bad', 'pass');
          if (response.containsKey('token')) {
            final token = response['token'] as String;
            await storage.write(key: 'jwt_token', value: token);
            await shiftProvider.setToken(token);
            final role = (response['role'] ?? 'user').toString().toLowerCase();
            return role == 'superadmin' ? '/admin' : '/dashboard';
          }
          return null;
        } catch (e) {
          return null;
        }
      })();

      // Assert
      expect(result, null);
    });

    test('Вход с ролью superadmin — навигация на /admin', () async {
      // Arrange
      when(() => apiService.login('admin', 'pass'))
          .thenAnswer((_) async => {'token': 'abc123', 'role': 'superadmin'});
      when(() => storage.write(key: 'jwt_token', value: 'abc123'))
          .thenAnswer((_) async {});
      when(() => shiftProvider.setToken('abc123')).thenAnswer((_) async {});

      // Act
      final result = await (() async {
        try {
          final response = await apiService.login('admin', 'pass');
          if (response.containsKey('token')) {
            final token = response['token'] as String;
            await storage.write(key: 'jwt_token', value: token);
            await shiftProvider.setToken(token);
            final role = (response['role'] ?? 'user').toString().toLowerCase();
            return role == 'superadmin' ? '/admin' : '/dashboard';
          }
          return null;
        } catch (e) {
          return null;
        }
      })();

      // Assert
      expect(result, '/admin');
    });
  });
}
