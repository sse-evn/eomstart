import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/location.dart';

class WebSocketService {
  static final _storage = FlutterSecureStorage();
  WebSocketChannel? _channel;
  final void Function(List<Location>) onLocationsUpdated;
  bool _isConnected = false;
  bool _isConnecting = false;

  WebSocketService({required this.onLocationsUpdated});

  Future<void> connect() async {
    if (_isConnecting || _isConnected) {
      print('WebSocket: уже подключён или подключается...');
      return;
    }

    _isConnecting = true;
    _isConnected = false;

    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token == null) {
        throw Exception('Токен не найден в хранилище');
      }

      final cleanToken = _cleanToken(token);
      final baseUrl = 'wss://eom-sharing.duckdns.org/ws';
      final encodedToken = Uri.encodeQueryComponent(cleanToken);
      final url = '$baseUrl?token=$encodedToken';

      print('Подключение к WebSocket: $url');
      _channel = WebSocketChannel.connect(Uri.parse(url));

      _isConnected = true;
      _isConnecting = false;

      _channel!.stream.listen(
        (message) {
          try {
            final dynamic data = jsonDecode(message);
            print('WebSocket получено: $data');

            if (data is Map<String, dynamic> &&
                data['type'] == 'online_users') {
              final users = _parseOnlineUsers(data['users']);
              _safeCall(() => onLocationsUpdated(users));
            }
          } catch (e, stack) {
            print('Ошибка обработки сообщения WebSocket: $e\n$stack');
          }
        },
        onError: (error) {
          print('WebSocket ошибка: $error');
          _handleDisconnect();
        },
        onDone: () {
          print('WebSocket соединение закрыто');
          _handleDisconnect();
        },
      );
    } catch (e, stack) {
      print('Ошибка инициализации WebSocket: $e\n$stack');
      _handleDisconnect();
    }
  }

  List<Location> _parseOnlineUsers(dynamic usersData) {
    if (usersData == null) return [];
    if (usersData is! List) return [];

    try {
      return usersData
          .map((item) {
            if (item is! Map<String, dynamic>) {
              print('Пропущен некорректный элемент: $item');
              return null;
            }
            return Location.fromJson(item);
          })
          .where((u) => u != null)
          .cast<Location>()
          .toList();
    } catch (e) {
      print('Ошибка парсинга списка пользователей: $e');
      return [];
    }
  }

  // ✅ ИСПРАВЛЕНО: Убран `mounted`, используется только WidgetsBinding
  void _safeCall(Function() callback) {
    try {
      final binding = WidgetsBinding.instance;
      if (binding != null &&
          binding.lifecycleState == AppLifecycleState.resumed) {
        callback();
      } else {
        // Откладываем до следующего кадра, если приложение не в активном состоянии
        binding?.addPostFrameCallback((_) {
          callback();
        });
      }
    } catch (e) {
      print('Ошибка при вызове callback: $e');
    }
  }

  void sendLocation(Location location) {
    if (_channel == null || !_isConnected) {
      print('WebSocket не подключён. Пропущена отправка локации.');
      return;
    }

    try {
      final message = jsonEncode(location.toJson());
      _channel!.sink.add(message);
      print('Локация отправлена: $message');
    } catch (e) {
      print('Ошибка отправки локации: $e');
      _isConnected = false;
    }
  }

  void _handleDisconnect() {
    _isConnected = false;
    _isConnecting = false;

    disconnect();

    // Повторное подключение
    Future.delayed(const Duration(seconds: 3), () {
      if (_isConnected || _isConnecting) return;
      connect();
    });
  }

  void disconnect() {
    _channel?.sink.close();
    _channel = null;
  }

  String _cleanToken(String token) {
    return token
        .trim()
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll('"', '')
        .replaceAll("'", '')
        .replaceAll(RegExp(r'[\r\n\t]'), '');
  }

  bool get isConnected => _isConnected;
  bool get isConnecting => _isConnecting;
}
