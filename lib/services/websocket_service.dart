// lib/services/websocket_service.dart
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
    if (_isConnecting || _isConnected) return;

    _isConnecting = true;
    _isConnected = false;

    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token == null) throw Exception('Токен не найден');

      final cleanToken = _cleanToken(token);
      final url = 'wss://eom-sharing.duckdns.org/ws?token=$cleanToken';

      _channel = WebSocketChannel.connect(Uri.parse(url));
      _isConnected = true;
      _isConnecting = false;

      _channel!.stream.listen(
        (message) {
          try {
            final data = jsonDecode(message);
            if (data is Map<String, dynamic> &&
                data['type'] == 'online_users') {
              final users = _parseOnlineUsers(data['users']);
              _safeCall(() => onLocationsUpdated(users));
            }
          } catch (e) {
            print('Ошибка обработки сообщения: $e');
          }
        },
        onError: (error) => _handleDisconnect(),
        onDone: () => _handleDisconnect(),
      );
    } catch (e) {
      _handleDisconnect();
    }
  }

  List<Location> _parseOnlineUsers(dynamic usersData) {
    if (usersData == null || usersData is! List) return [];

    return usersData
        .map((item) {
          if (item is! Map<String, dynamic>) return null;
          return Location.fromJson(item);
        })
        .where((u) => u != null)
        .cast<Location>()
        .toList();
  }

  void _safeCall(Function() callback) {
    try {
      final binding = WidgetsBinding.instance;
      if (binding != null &&
          binding.lifecycleState == AppLifecycleState.resumed) {
        callback();
      } else {
        binding?.addPostFrameCallback((_) => callback());
      }
    } catch (e) {
      print('Ошибка вызова callback: $e');
    }
  }

  void sendLocation(Location location) {
    if (_channel == null || !_isConnected) return;

    try {
      final message = jsonEncode(location.toJson());
      _channel!.sink.add(message);
    } catch (e) {
      _isConnected = false;
    }
  }

  void _handleDisconnect() {
    _isConnected = false;
    _isConnecting = false;
    disconnect();

    Future.delayed(const Duration(seconds: 3), () {
      if (!_isConnected && !_isConnecting) connect();
    });
  }

  void disconnect() {
    _channel?.sink.close();
    _channel = null;
  }

  String _cleanToken(String token) {
    return token.trim().replaceAll(RegExp(r'\s+'), '');
  }

  bool get isConnected => _isConnected;
}
