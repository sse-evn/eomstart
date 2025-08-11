import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AppConfig {
  static const String backendUrl = 'https://eom-sharing.duckdns.org';
  static const String botUsername = 'eom_auth_bot';
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
  late final WebViewController _tgController;
  final _storage = const FlutterSecureStorage();

  @override
  void initState() {
    super.initState();
    _checkTokenAndNavigate();
    _initTelegramWebView();
  }

  Future<void> _checkTokenAndNavigate() async {
    final String? token = await _storage.read(key: 'jwt_token');
    if (mounted && token != null && token.isNotEmpty) {
      Navigator.pushReplacementNamed(context, '/dashboard');
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
          onNavigationRequest: (request) {
            if (request.url.contains('${AppConfig.backendUrl}/auth_callback')) {
              _handleTelegramAuth(request.url);
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
        throw Exception('Недостаточно данных для авторизации');
      }

      final response = await http.post(
        Uri.parse('${AppConfig.backendUrl}/api/auth/telegram'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(authData),
      );

      final responseData = jsonDecode(response.body);
      if (response.statusCode == 200) {
        final String token = responseData['token'];
        _navigateToDashboard(token);
      } else {
        _showSnackBar(
            responseData['error'] ?? 'Ошибка авторизации', Colors.red);
      }
    } catch (e) {
      _showSnackBar('Ошибка: ${e.toString()}', Colors.red);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        Navigator.pop(context);
      }
    }
  }

  Future<void> _handleRegularLogin() async {
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
        _navigateToDashboard(token);
      } else {
        _showSnackBar(
          responseData['error'] ?? 'Ошибка авторизации',
          Colors.red,
        );
      }
    } catch (e) {
      _showSnackBar('Ошибка: ${e.toString()}', Colors.red);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _navigateToDashboard(String token) async {
    await _storage.write(key: 'jwt_token', value: token);
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(
          context, '/dashboard', (route) => false);
    }
  }

  void _showSnackBar(String message, Color color) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: color),
      );
    }
  }

  void _showTelegramAuthDialog() {
    showDialog(
      context: context,
      barrierDismissible: !_isLoading,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Column(
          // mainAxisSize is now important to allow the Expanded widget to work
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Вход через Telegram',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.green[700]),
              ),
            ),
            // The fix: wrap the WebViewWidget in Expanded to prevent overflow
            Expanded(
              child: SizedBox(
                // Use a constrained height/width on the Expanded child as needed
                height: 400,
                width: MediaQuery.of(context).size.width * 0.8,
                child: WebViewWidget(controller: _tgController),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextButton(
                onPressed: _isLoading ? null : () => Navigator.pop(context),
                child: const Text('ЗАКРЫТЬ'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SvgPicture.asset('assets/eom.svg', height: 140),
                const SizedBox(height: 32),
                Card(
                  elevation: 8,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          Text(
                            'Вход в систему',
                            style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.green[800]),
                          ),
                          const SizedBox(height: 32),
                          _buildTextField(
                            controller: _usernameController,
                            label: 'Имя пользователя',
                            icon: Icons.person_outline,
                            enabled: !_isLoading,
                          ),
                          const SizedBox(height: 20),
                          _buildTextField(
                            controller: _passwordController,
                            label: 'Пароль',
                            icon: Icons.lock_outline,
                            obscureText: true,
                            enabled: !_isLoading,
                          ),
                          const SizedBox(height: 32),
                          SizedBox(
                            width: double.infinity,
                            height: 55,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green[700],
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16)),
                                elevation: 4,
                              ),
                              onPressed:
                                  _isLoading ? null : _handleRegularLogin,
                              child: _isLoading
                                  ? const CircularProgressIndicator(
                                      color: Colors.white)
                                  : const Text(
                                      'ВОЙТИ',
                                      style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          Row(
                            children: [
                              const Expanded(
                                  child: Divider(
                                      color: Colors.grey, thickness: 1)),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                                child: Text('или',
                                    style: TextStyle(color: Colors.grey[700])),
                              ),
                              const Expanded(
                                  child: Divider(
                                      color: Colors.grey, thickness: 1)),
                            ],
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            height: 55,
                            child: OutlinedButton.icon(
                              icon: SvgPicture.asset('assets/telegram.svg',
                                  height: 26, color: Colors.blue[400]),
                              label: Text(
                                'Войти через Telegram',
                                style: TextStyle(
                                    color: Colors.blue[400],
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: Colors.blue[400]!),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16)),
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
    bool obscureText = false,
    bool enabled = true,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      enabled: enabled,
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Поле не может быть пустым';
        }
        return null;
      },
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: Colors.green[700]),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Colors.grey[400]!)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Colors.green[700]!, width: 2)),
        errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Colors.red, width: 2)),
        focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Colors.red, width: 2)),
        contentPadding:
            const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
      ),
    );
  }
}
