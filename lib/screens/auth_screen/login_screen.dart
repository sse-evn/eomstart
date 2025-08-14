import 'package:flutter/material.dart';
import 'package:micro_mobility_app/providers/shift_provider.dart'
    show ShiftProvider;
import 'package:micro_mobility_app/services/api_service.dart' show ApiService;
import 'package:provider/provider.dart' show Provider;
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AppConfig {
  static const String backendUrl = 'https://eom-sharing.duckdns.org';
  static const String telegramLoginUrl = '$backendUrl/telegram-login.html';
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _obscurePassword = true;
  late final WebViewController _tgController;
  final _storage = const FlutterSecureStorage();
  final ApiService _apiService = ApiService();

  @override
  void initState() {
    super.initState();
    _checkTokenAndNavigate();
    _initTelegramWebView();
  }

  Future<void> _checkTokenAndNavigate() async {
    final String? token = await _storage.read(key: 'jwt_token');
    if (mounted && token != null && token.isNotEmpty) {
      try {
        final profile = await _apiService.getUserProfile(token);
        final status =
            (profile['status'] ?? 'inactive').toString().toLowerCase();
        final role = profile['role']?.toString().toLowerCase();
        final isActive = (profile['is_active'] as bool?) ?? false;

        if (mounted) {
          // Логика перехода внутри экрана логина
          if (isActive && status != 'pending') {
            final nextRoute = role == 'superadmin' ? '/admin' : '/dashboard';
            Navigator.pushNamedAndRemoveUntil(
                context, nextRoute, (route) => false);
          } else if (status == 'pending') {
            Navigator.pushNamedAndRemoveUntil(
                context, '/pending', (route) => false);
          } else if (status == 'new' || status == 'null') {
            // Если новый пользователь - направляем на регистрацию
            Navigator.pushNamedAndRemoveUntil(
                context, '/registration', (route) => false);
          } else {
            // Если пользователь не активен, остаемся на экране логина
            // и не показываем ошибку, просто позволяем пользователю войти
            // или зарегистрироваться снова.
            // Токен уже недействителен, поэтому удаляем его.
            await _storage.delete(key: 'jwt_token');
          }
        }
      } catch (e) {
        // Токен недействителен, удаляем его и остаемся на экране логина
        debugPrint('Недействительный токен: $e');
        await _storage.delete(key: 'jwt_token');
        // Не показываем ошибку пользователю, просто позволяем войти заново.
      }
    }
    // Если токена нет или он недействителен, остаемся на экране логина
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showSuccess(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _performLogin(String username, String password) async {
    setState(() => _isLoading = true);

    try {
      final response = await _apiService.login(username, password);

      if (response.containsKey('token')) {
        final token = response['token'] as String;

        // Сохраняем токен в SecureStorage
        await _storage.write(key: 'jwt_token', value: token);

        // Обновляем провайдер
        final shiftProvider =
            Provider.of<ShiftProvider>(context, listen: false);
        await shiftProvider.setToken(token);

        // Переходим к нужному экрану
        final profile = await _apiService.getUserProfile(token);
        final status =
            (profile['status'] ?? 'inactive').toString().toLowerCase();
        final role = (profile['role'] ?? 'user').toString().toLowerCase();

        if (mounted) {
          if (status == 'pending' && role != 'superadmin') {
            Navigator.pushNamedAndRemoveUntil(
                context, '/pending', (route) => false);
          } else if (status == 'new' || status == 'null') {
            Navigator.pushNamedAndRemoveUntil(
                context, '/registration', (route) => false);
          } else {
            final nextRoute = role == 'superadmin' ? '/admin' : '/dashboard';
            Navigator.pushReplacementNamed(context, nextRoute);
          }
        }
      } else {
        _showError('Неверный логин или пароль');
      }
    } catch (e) {
      _showError('Ошибка авторизации: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _initTelegramWebView() {
    late final PlatformWebViewControllerCreationParams params;
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    final controller = WebViewController.fromPlatformCreationParams(params);

    controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) async {
            if (request.url.contains('${AppConfig.backendUrl}/auth_callback')) {
              await _handleTelegramAuth(request.url);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(AppConfig.telegramLoginUrl));

    if (controller.platform is AndroidWebViewController) {
      (controller.platform as AndroidWebViewController)
          .setMediaPlaybackRequiresUserGesture(false);
    }

    _tgController = controller;
  }

  Future<void> _handleTelegramAuth(String url) async {
    setState(() => _isLoading = true);
    try {
      final uri = Uri.parse(url);
      Map<String, String> authData = {};
      uri.queryParameters.forEach((key, value) {
        if (value.isNotEmpty) {
          authData[key] = value;
        }
      });

      if (!authData.containsKey('id') || !authData.containsKey('hash')) {
        throw Exception('Недостаточно данных');
      }

      final response = await http.post(
        Uri.parse('${AppConfig.backendUrl}/api/auth/telegram'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(authData),
      );

      final responseData = jsonDecode(response.body);
      if (response.statusCode == 200) {
        final String token = responseData['token'];
        await _storage.write(key: 'jwt_token', value: token);

        final profile = await _apiService.getUserProfile(token);
        final status = profile['status']?.toString();
        final role = profile['role']?.toString().toLowerCase();

        if (mounted) {
          // Проверяем статус пользователя
          if (status == 'pending' && role != 'superadmin') {
            Navigator.pushNamedAndRemoveUntil(
                context, '/pending', (route) => false);
          } else if (status == 'new' || status == null) {
            // Если новый пользователь - направляем на регистрацию
            Navigator.pushNamedAndRemoveUntil(
                context, '/registration', (route) => false);
          } else {
            // Для активных пользователей - в основное приложение
            final nextRoute = role == 'superadmin' ? '/admin' : '/dashboard';
            Navigator.pushNamedAndRemoveUntil(
                context, nextRoute, (route) => false);
          }
        }
      } else {
        _showError(
            responseData['error'] ?? 'Ошибка авторизации через Telegram');
      }
    } catch (e) {
      _showError('Ошибка авторизации через Telegram: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _handleRegularLogin() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final response = await http.post(
        Uri.parse('${AppConfig.backendUrl}/api/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': _usernameController.text,
          'password': _passwordController.text,
        }),
      );
      final responseData = jsonDecode(response.body);
      if (response.statusCode == 200) {
        final String token = responseData['token'];
        await _storage.write(key: 'jwt_token', value: token);

        final profile = await _apiService.getUserProfile(token);
        final status = profile['status']?.toString();
        final role = profile['role']?.toString().toLowerCase();

        if (mounted) {
          if (status == 'pending' && role != 'superadmin') {
            Navigator.pushNamedAndRemoveUntil(
                context, '/pending', (route) => false);
          } else if (status == 'new' || status == null) {
            Navigator.pushNamedAndRemoveUntil(
                context, '/registration', (route) => false);
          } else {
            final nextRoute = role == 'superadmin' ? '/admin' : '/dashboard';
            Navigator.pushNamedAndRemoveUntil(
                context, nextRoute, (route) => false);
          }
        }
      } else {
        _showError(responseData['error'] ?? 'Ошибка авторизации');
      }
    } catch (e) {
      _showError('Ошибка подключения: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showTelegramAuthDialog() {
    showDialog(
      context: context,
      barrierDismissible: !_isLoading,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: SizedBox(
          height: 500,
          width: MediaQuery.of(context).size.width * 0.9,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Вход через Telegram',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.green[800]),
                    ),
                    IconButton(
                      onPressed:
                          _isLoading ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: WebViewWidget(controller: _tgController),
              ),
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDarkMode ? Colors.grey[900] : Colors.grey[50],
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Логотип
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: isDarkMode ? Colors.grey[800] : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: isDarkMode
                            ? Colors.black26
                            : Colors.grey.withOpacity(0.3),
                        blurRadius: 15,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: SvgPicture.asset(
                    'assets/eom.svg',
                    height: 120,
                    // color: isDarkMode ? Colors.white : Colors.green[800],
                  ),
                ),

                const SizedBox(height: 32),

                // Карточка входа
                Card(
                  elevation: 8,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  color: isDarkMode ? Colors.grey[800] : Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Вход в систему',
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                              color:
                                  isDarkMode ? Colors.white : Colors.green[800],
                            ),
                          ),
                          const SizedBox(height: 32),

                          // Поле имени пользователя
                          _buildTextField(
                            controller: _usernameController,
                            label: 'Имя пользователя',
                            icon: Icons.person_outline,
                            enabled: !_isLoading,
                          ),
                          const SizedBox(height: 20),

                          // Поле пароля
                          _buildPasswordField(),
                          const SizedBox(height: 32),

                          // Кнопка входа
                          SizedBox(
                            width: double.infinity,
                            height: 55,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green[700],
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                elevation: 4,
                              ),
                              onPressed:
                                  _isLoading ? null : _handleRegularLogin,
                              child: _isLoading
                                  ? const CircularProgressIndicator(
                                      color: Colors.white,
                                    )
                                  : const Text(
                                      'ВОЙТИ',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Разделитель
                          Row(
                            children: [
                              const Expanded(
                                child: Divider(
                                  color: Colors.grey,
                                  thickness: 1,
                                ),
                              ),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                                child: Text(
                                  'или',
                                  style: TextStyle(
                                    color: isDarkMode
                                        ? Colors.grey[400]
                                        : Colors.grey[700],
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              const Expanded(
                                child: Divider(
                                  color: Colors.grey,
                                  thickness: 1,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),

                          // Кнопка Telegram
                          SizedBox(
                            width: double.infinity,
                            height: 55,
                            child: OutlinedButton.icon(
                              icon: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.blue[400],
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: SvgPicture.asset(
                                  'assets/telegram.svg',
                                  height: 22,
                                  color: Colors.white,
                                ),
                              ),
                              label: const Text(
                                'Войти через Telegram',
                                style: TextStyle(
                                  color: Colors.blue,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: Colors.blue[400]!),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              onPressed:
                                  _isLoading ? null : _showTelegramAuthDialog,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Информация
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDarkMode ? Colors.grey[800] : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDarkMode ? Colors.grey[700]! : Colors.grey[300]!,
                    ),
                  ),
                  child: const Text(
                    'Введите свои учетные данные для доступа к системе',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool enabled = true,
  }) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    return TextFormField(
      controller: controller,
      enabled: enabled,
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Поле не может быть пустым';
        }
        return null;
      },
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
          color: isDarkMode ? Colors.grey[400] : Colors.grey[700],
        ),
        prefixIcon: Icon(
          icon,
          color: Colors.green[700],
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: isDarkMode ? Colors.grey[700]! : Colors.grey[400]!,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: Colors.green[700]!,
            width: 2,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(
            color: Colors.red,
            width: 2,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(
            color: Colors.red,
            width: 2,
          ),
        ),
        filled: true,
        fillColor: isDarkMode ? Colors.grey[900] : Colors.grey[50],
        contentPadding: const EdgeInsets.symmetric(
          vertical: 20,
          horizontal: 20,
        ),
      ),
    );
  }

  Widget _buildPasswordField() {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    return TextFormField(
      controller: _passwordController,
      obscureText: _obscurePassword,
      enabled: !_isLoading,
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Поле не может быть пустым';
        }
        if (value.length < 6) {
          return 'Пароль должен содержать минимум 6 символов';
        }
        return null;
      },
      decoration: InputDecoration(
        labelText: 'Пароль',
        labelStyle: TextStyle(
          color: isDarkMode ? Colors.grey[400] : Colors.grey[700],
        ),
        prefixIcon: Icon(
          Icons.lock_outline,
          color: Colors.green[700],
        ),
        suffixIcon: IconButton(
          icon: Icon(
            _obscurePassword
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            color: Colors.grey[600],
          ),
          onPressed: () {
            setState(() {
              _obscurePassword = !_obscurePassword;
            });
          },
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: isDarkMode ? Colors.grey[700]! : Colors.grey[400]!,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: Colors.green[700]!,
            width: 2,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(
            color: Colors.red,
            width: 2,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(
            color: Colors.red,
            width: 2,
          ),
        ),
        filled: true,
        fillColor: isDarkMode ? Colors.grey[900] : Colors.grey[50],
        contentPadding: const EdgeInsets.symmetric(
          vertical: 20,
          horizontal: 20,
        ),
      ),
    );
  }
}
