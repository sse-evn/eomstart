// lib/services/websocket_service.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:micro_mobility_app/config/config.dart'; // ✅ Импортируем конфиг
import '../models/location.dart';
import '../models/user_shift_location.dart';

class WebSocketService {
  static final _storage = FlutterSecureStorage();
  WebSocketChannel? _channel;
  final void Function(List<Location>) onLocationsUpdated;
  final void Function(List<UserShiftLocation>) onActiveShiftsUpdated;
  bool _isConnected = false;
  bool _isConnecting = false;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  static const Duration _initialReconnectDelay = Duration(seconds: 3);
  bool _isExplicitDisconnect = false;

  WebSocketService({
    required this.onLocationsUpdated,
    required this.onActiveShiftsUpdated,
  });

  Future<void> connect() async {
    if (_isConnecting || _isConnected) {
      print('⚠️ Already connecting or connected');
      return;
    }
    _isConnecting = true;
    _isExplicitDisconnect = false;
    _reconnectAttempts = 0;
    print('🔄 Attempting to connect to WebSocket...');
    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token == null) {
        throw Exception('Token not found');
      }
      print('✅ Token found, connecting...');
      final cleanToken = _cleanToken(token);
      final url =
          '${AppConfig.websocketUrl}?token=$cleanToken'; // ✅ Изменено: используем AppConfig
      print('🌐 Connecting to: $url');

      // Close any existing connection properly
      if (_channel != null) {
        try {
          await _channel!.sink.close();
          _channel = null;
        } catch (e) {
          print('❌ Error closing existing connection: $e');
        }
      }
      _isConnected = false;

      // Create connection with timeout
      _channel = await _connectWithTimeout(url);

      _channel!.stream.listen(
        (message) {
          _resetReconnectAttempts();
          print('📨 Received message: $message');
          _processMessage(message);
        },
        onError: (error) {
          print('❌ WebSocket error: $error');
          if (!_isExplicitDisconnect) {
            _handleDisconnect(error: error);
          }
        },
        onDone: () {
          print('🔚 WebSocket connection closed');
          if (!_isExplicitDisconnect) {
            _handleDisconnect();
          }
        },
      );
      _isConnected = true;
      _isConnecting = false;
      print('✅ WebSocket connected successfully');
      // Start ping timer
      _startPingTimer();

      // Запросить список активных смен и пользователей после подключения
      Future.delayed(const Duration(milliseconds: 500), () {
        if (_isConnected) {
          _requestActiveShifts();
          _requestOnlineUsers();
        }
      });
    } catch (e) {
      print('❌ WebSocket connection error: $e');
      _isConnecting = false;
      if (!_isExplicitDisconnect) {
        _handleDisconnect(error: e);
      }
    }
  }

  Future<WebSocketChannel> _connectWithTimeout(String url) async {
    try {
      final connectionFuture = Future<WebSocketChannel>(() {
        return WebSocketChannel.connect(Uri.parse(url));
      });

      final timeoutFuture = Future<WebSocketChannel>.delayed(
        const Duration(seconds: 10),
        () => throw TimeoutException('Connection timeout'),
      );

      return await Future.any([connectionFuture, timeoutFuture]);
    } on TimeoutException catch (_) {
      throw TimeoutException('Connection timeout');
    }
  }

  void _requestActiveShifts() {
    if (_isConnected && _channel != null) {
      try {
        final message = jsonEncode({'type': 'get_active_shifts'});
        _channel!.sink.add(message);
        print('📤 Requested active shifts: $message');
      } catch (e) {
        print('❌ Error requesting active shifts: $e');
      }
    }
  }

  void _requestOnlineUsers() {
    if (_isConnected && _channel != null) {
      try {
        final message = jsonEncode({'type': 'get_online_users'});
        _channel!.sink.add(message);
        print('📤 Requested online users: $message');
      } catch (e) {
        print('❌ Error requesting online users: $e');
      }
    }
  }

  void _processMessage(String message) {
    try {
      final data = jsonDecode(message);
      print('📨 Processing message type: ${data['type']}');

      if (data is Map<String, dynamic>) {
        if (data['type'] == 'online_users') {
          print('👥 Processing online users');
          final users = _parseOnlineUsers(data['users']);
          print('👥 Found ${users.length} online users');
          _safeCall(() => onLocationsUpdated(users));
        } else if (data['type'] == 'active_shifts') {
          print('⏱️ Processing active shifts');
          final shifts = _parseActiveShifts(data['shifts']);
          print('⏱️ Found ${shifts.length} active shifts');
          _safeCall(() => onActiveShiftsUpdated(shifts));
        } else if (data['type'] == 'pong') {
          print('📨 Received pong from server');
        } else if (data['type'] == 'error') {
          print('❌ Server error: ${data['message']}');
        } else {
          print('❓ Unknown message type: ${data['type']}');
        }
      }
    } catch (e) {
      print('❌ Error processing message: $e');
      print('❌ Raw message: $message');
    }
  }

  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_isConnected && _channel != null) {
        print('📤 Sending ping');
        try {
          final message = jsonEncode({'type': 'ping'});
          _channel!.sink.add(message);
        } catch (e) {
          print('❌ Error sending ping: $e');
          if (!_isExplicitDisconnect) {
            _handleDisconnect(error: e);
          }
        }
      }
    });
  }

  List<Location> _parseOnlineUsers(dynamic usersData) {
    if (usersData == null || usersData is! List) {
      print('❌ Invalid users data format: $usersData');
      return [];
    }
    return usersData
        .map((item) {
          if (item is! Map<String, dynamic>) {
            print('❌ Invalid user item format: $item');
            return null;
          }
          return Location.fromJson(item);
        })
        .where((u) => u != null)
        .cast<Location>()
        .toList();
  }

  List<UserShiftLocation> _parseActiveShifts(dynamic shiftsData) {
    if (shiftsData == null || shiftsData is! List) {
      print('❌ Invalid shifts data format: $shiftsData');
      return [];
    }
    return shiftsData
        .map((item) {
          if (item is! Map<String, dynamic>) {
            print('❌ Invalid shift item format: $item');
            return null;
          }
          return UserShiftLocation.fromJson(item);
        })
        .where((s) => s != null)
        .cast<UserShiftLocation>()
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
      print('❌ Error calling callback: $e');
    }
  }

  void sendLocation(Location location) {
    if (_channel == null || !_isConnected) {
      print('❌ Cannot send location - WebSocket not connected');
      return;
    }
    try {
      final message = jsonEncode({
        'type': 'location',
        'data': location.toJson(),
      });
      print('📤 Sending location: $message');
      _channel!.sink.add(message);
    } catch (e) {
      print('❌ Error sending location: $e');
      if (!_isExplicitDisconnect) {
        _handleDisconnect(error: e);
      }
    }
  }

  void _handleDisconnect({Object? error}) {
    if (!_isConnected && !_isConnecting) return;
    print('🔌 Handling WebSocket disconnect');
    if (error != null) {
      print('❌ Disconnect reason: $error');
    }
    _isConnected = false;
    _isConnecting = false;
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    if (_isExplicitDisconnect) {
      print('🔌 Explicit disconnect, not attempting to reconnect');
      return;
    }
    if (_reconnectAttempts < _maxReconnectAttempts) {
      _reconnectAttempts++;
      final delay = _initialReconnectDelay * (1 << (_reconnectAttempts - 1));
      print(
          '🔄 Attempting to reconnect in ${delay.inSeconds} seconds (attempt $_reconnectAttempts/$_maxReconnectAttempts)');
      _reconnectTimer = Timer(delay, () {
        if (!_isConnected && !_isConnecting) {
          connect().catchError((error) {
            print('❌ Reconnection failed: $error');
            _handleDisconnect(error: error);
          });
        }
      });
    } else {
      print('❌ Max reconnection attempts reached');
    }
  }

  void _resetReconnectAttempts() {
    _reconnectAttempts = 0;
  }

  Future<void> disconnect() async {
    print('🔌 Disconnecting WebSocket');
    _isExplicitDisconnect = true;
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    _isConnected = false;
    _isConnecting = false;
    if (_channel != null) {
      try {
        print('🔌 Closing WebSocket connection');
        await _channel!.sink.close();
        _channel = null;
      } catch (e) {
        print('❌ Error closing WebSocket: $e');
      }
    }
  }

  String _cleanToken(String token) {
    return token.trim().replaceAll(RegExp(r'\s+'), '');
  }

  bool get isConnected => _isConnected;
}
