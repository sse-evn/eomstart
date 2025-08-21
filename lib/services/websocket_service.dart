import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/location.dart';
import 'package:flutter/foundation.dart';

class WebSocketService {
  static final _storage = const FlutterSecureStorage();
  WebSocketChannel? _channel;
  final void Function(List<Location>) onLocationsUpdated;
  bool _isConnected = false;
  bool _isConnecting = false;

  WebSocketService({required this.onLocationsUpdated});

  Future<void> connect() async {
    if (_isConnecting || _isConnected) {
      print('WebSocket: уже подключен или подключается...');
      return;
    }

    _isConnecting = true;
    _isConnected = false;

    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token == null) {
        throw Exception('Токен не найден');
      }

      // ✅ ИСПРАВЛЕНО: Тщательная очистка токена
      final cleanToken = _cleanToken(token);
      print('Оригинальный токен: "$token"');
      print('Очищенный токен: "$cleanToken"');

      // ✅ ИСПРАВЛЕНО: Правильный URL без лишних символов
      final baseUrl = 'wss://eom-sharing.duckdns.org/ws';
      final encodedToken = Uri.encodeQueryComponent(cleanToken);
      final url = '$baseUrl?token=$encodedToken';

      print('WebSocket URL: $url');

      // Создаем канал
      final uri = Uri.parse(url);
      print('Parsed URI: $uri');
      _channel = WebSocketChannel.connect(uri);

      _isConnected = true;
      _isConnecting = false;

      _channel!.stream.listen(
        (message) {
          try {
            final data = jsonDecode(message);
            print('Получено сообщение WebSocket: $data');
            if (data['type'] == 'online_users') {
              final users = (data['users'] as List)
                  .map((u) => Location.fromJson(u))
                  .toList();
              _safeCallCallback(() => onLocationsUpdated(users));
            }
          } catch (e) {
            print('Ошибка обработки сообщения WebSocket: $e');
          }
        },
        onError: (err) {
          print('WS Error: $err');
          _handleConnectionError();
        },
        onDone: () {
          print('WS Disconnected');
          _handleConnectionError();
        },
      );
    } catch (e) {
      print('Ошибка подключения к WebSocket: $e');
      _handleConnectionError();
    }
  }

  // Метод для очистки токена от лишних символов
  String _cleanToken(String token) {
    // Убираем все пробельные символы и лишние данные
    String clean = token.trim();

    // Если токен содержит "HTTP/1.1", убираем всё после него
    if (clean.contains('HTTP/1.1')) {
      clean = clean.split('HTTP/1.1').first.trim();
    }

    // Убираем лишние пробелы и специальные символы
    clean = clean.replaceAll(RegExp(r'\s+'), '');
    clean = clean.replaceAll('"', '');
    clean = clean.replaceAll("'", '');

    return clean;
  }

  void _handleConnectionError() {
    _isConnected = false;
    _isConnecting = false;
    _safeCallCallback(() => onLocationsUpdated([]));
  }

  Future<void> sendLocation(Location location) async {
    if (_channel == null || !_isConnected) {
      print('WebSocket канал не подключен');
      return;
    }

    try {
      _channel!.sink.add(jsonEncode(location.toJson()));
    } catch (e) {
      print('Ошибка отправки локации: $e');
      _isConnected = false;
    }
  }

  void disconnect() {
    _isConnected = false;
    _isConnecting = false;
    _channel?.sink.close();
    _channel = null;
  }

  bool get isConnected => _isConnected;
  bool get isConnecting => _isConnecting;

  void _safeCallCallback(Function callback) {
    try {
      if (WidgetsBinding.instance?.lifecycleState ==
          AppLifecycleState.resumed) {
        callback();
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          callback();
        });
      }
    } catch (e) {
      print('Ошибка при безопасном вызове callback: $e');
    }
  }
}
