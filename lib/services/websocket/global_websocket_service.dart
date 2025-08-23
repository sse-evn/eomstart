// lib/services/global_websocket_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:micro_mobility_app/models/location.dart';
import 'package:micro_mobility_app/models/user_shift_location.dart';

class GlobalWebSocketService {
  static final GlobalWebSocketService _instance =
      GlobalWebSocketService._internal();
  static final _storage = FlutterSecureStorage();

  factory GlobalWebSocketService() {
    return _instance;
  }

  GlobalWebSocketService._internal();

  WebSocketChannel? _channel;
  bool _isConnected = false;
  bool _isConnecting = false;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  Timer? _locationUpdateTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  static const Duration _initialReconnectDelay = Duration(seconds: 3);
  bool _isExplicitDisconnect = false;

  // Коллбэки для обновления данных
  final List<void Function(List<Location>)> _locationsCallbacks = [];
  final List<void Function(List<UserShiftLocation>)> _shiftsCallbacks = [];
  final List<void Function(bool)> _connectionCallbacks = [];

  // Данные
  List<Location> _users = [];
  List<UserShiftLocation> _activeShifts = [];
  Location? _currentLocation;

  // Добавить коллбэк для обновления местоположений
  void addLocationsCallback(void Function(List<Location>) callback) {
    _locationsCallbacks.add(callback);
    // Сразу отправляем текущие данные
    if (_users.isNotEmpty) {
      callback(_users);
    }
  }

  // Удалить коллбэк для обновления местоположений
  void removeLocationsCallback(void Function(List<Location>) callback) {
    _locationsCallbacks.remove(callback);
  }

  // Добавить коллбэк для обновления смен
  void addShiftsCallback(void Function(List<UserShiftLocation>) callback) {
    _shiftsCallbacks.add(callback);
    // Сразу отправляем текущие данные
    if (_activeShifts.isNotEmpty) {
      callback(_activeShifts);
    }
  }

  // Удалить коллбэк для обновления смен
  void removeShiftsCallback(void Function(List<UserShiftLocation>) callback) {
    _shiftsCallbacks.remove(callback);
  }

  // Добавить коллбэк для обновления состояния соединения
  void addConnectionCallback(void Function(bool) callback) {
    _connectionCallbacks.add(callback);
    // Сразу отправляем текущее состояние
    callback(_isConnected);
  }

  // Удалить коллбэк для обновления состояния соединения
  void removeConnectionCallback(void Function(bool) callback) {
    _connectionCallbacks.remove(callback);
  }

  // Инициализация сервиса
  Future<void> init() async {
    print('🔧 GlobalWebSocketService: Initializing');
    await connect();
  }

  // Подключение к WebSocket
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
      final url = 'wss://eom-sharing.duckdns.org/ws?token=$cleanToken';
      print('🌐 Connecting to: $url');

      // Закрываем существующее соединение, если есть
      if (_channel != null) {
        try {
          await _channel!.sink.close();
          _channel = null;
        } catch (e) {
          print('❌ Error closing existing connection: $e');
        }
      }

      _isConnected = false;

      // Создаем соединение с таймаутом
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

      // Запускаем таймер пингов
      _startPingTimer();

      // Запускаем таймер обновления местоположения
      _startLocationUpdateTimer();

      // Запрашиваем данные с сервера с небольшой задержкой
      Future.delayed(const Duration(milliseconds: 500), () {
        if (_isConnected) {
          _requestActiveShifts();
          _requestOnlineUsers();
        }
      });

      // Уведомляем подписчиков об изменении состояния соединения
      _notifyConnectionCallbacks();
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

  // Обновление текущего местоположения
  void updateCurrentLocation(Location location) {
    _currentLocation = location;
    if (_isConnected && _channel != null) {
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
  }

  // Запрос активных смен
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

  // Запрос онлайн пользователей
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

  // Обработка полученных сообщений
  void _processMessage(String message) {
    try {
      final data = jsonDecode(message);
      print('📨 Processing message type: ${data['type']}');

      if (data is Map<String, dynamic>) {
        if (data['type'] == 'online_users') {
          print('👥 Processing online users');
          final users = _parseOnlineUsers(data['users']);
          print('👥 Found ${users.length} online users');
          _users = users;
          _notifyLocationsCallbacks();
        } else if (data['type'] == 'active_shifts') {
          print('⏱️ Processing active shifts');
          final shifts = _parseActiveShifts(data['shifts']);
          print('⏱️ Found ${shifts.length} active shifts');
          _activeShifts = shifts;
          _notifyShiftsCallbacks();
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

  // Запуск таймера пингов
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

  // Запуск таймера обновления местоположения
  void _startLocationUpdateTimer() {
    _locationUpdateTimer?.cancel();
    _locationUpdateTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      if (_isConnected && _currentLocation != null) {
        try {
          final message = jsonEncode({
            'type': 'location',
            'data': _currentLocation!.toJson(),
          });
          print('📤 Sending location update: $message');
          _channel!.sink.add(message);
        } catch (e) {
          print('❌ Error sending location update: $e');
          if (!_isExplicitDisconnect) {
            _handleDisconnect(error: e);
          }
        }
      }
    });
  }

  // Парсинг пользователей
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

  // Парсинг смен
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

  // Уведомление подписчиков об изменении местоположений
  void _notifyLocationsCallbacks() {
    for (final callback in _locationsCallbacks) {
      try {
        callback(_users);
      } catch (e) {
        print('❌ Error in locations callback: $e');
      }
    }
  }

  // Уведомление подписчиков об изменении смен
  void _notifyShiftsCallbacks() {
    for (final callback in _shiftsCallbacks) {
      try {
        callback(_activeShifts);
      } catch (e) {
        print('❌ Error in shifts callback: $e');
      }
    }
  }

  // Уведомление подписчиков об изменении состояния соединения
  void _notifyConnectionCallbacks() {
    for (final callback in _connectionCallbacks) {
      try {
        callback(_isConnected);
      } catch (e) {
        print('❌ Error in connection callback: $e');
      }
    }
  }

  // Обработка отключения
  void _handleDisconnect({Object? error}) {
    if (!_isConnected && !_isConnecting) return;

    print('🔌 Handling WebSocket disconnect');
    if (error != null) {
      print('❌ Disconnect reason: $error');
    }

    _isConnected = false;
    _isConnecting = false;
    _pingTimer?.cancel();
    _locationUpdateTimer?.cancel();

    // Уведомляем подписчиков об изменении состояния соединения
    _notifyConnectionCallbacks();

    // Отменяем существующий таймер переподключения
    _reconnectTimer?.cancel();

    // Если это явное отключение, не пытаемся переподключиться
    if (_isExplicitDisconnect) {
      print('🔌 Explicit disconnect, not attempting to reconnect');
      return;
    }

    // Пытаемся переподключиться с экспоненциальной задержкой
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

  // Сброс счетчика попыток переподключения
  void _resetReconnectAttempts() {
    _reconnectAttempts = 0;
  }

  // Отключение от WebSocket
  Future<void> disconnect() async {
    print('🔌 Disconnecting WebSocket');
    _isExplicitDisconnect = true;
    _pingTimer?.cancel();
    _locationUpdateTimer?.cancel();
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

    // Уведомляем подписчиков об изменении состояния соединения
    _notifyConnectionCallbacks();
  }

  // Очистка токена
  String _cleanToken(String token) {
    return token.trim().replaceAll(RegExp(r'\s+'), '');
  }

  // Получение состояния соединения
  bool get isConnected => _isConnected;

  // Получение текущих пользователей
  List<Location> get users => List.unmodifiable(_users);

  // Получение текущих смен
  List<UserShiftLocation> get activeShifts => List.unmodifiable(_activeShifts);
}
