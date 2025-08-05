import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import 'package:http/http.dart' as http;

class TelegramAuthScreen extends StatefulWidget {
  final Function(String)? onAuthSuccess;
  final Function(String)? onError;

  const TelegramAuthScreen({
    super.key,
    this.onAuthSuccess,
    this.onError,
  });

  @override
  State<TelegramAuthScreen> createState() => _TelegramAuthScreenState();
}

class _TelegramAuthScreenState extends State<TelegramAuthScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _hasError = false;

  // Конфигурация
  static const String _botUsername = "eom_auth_bot";
  static const String _backendUrl = "https://eom-sharing.duckdns.org";
  static const String _callbackPath = "/auth/telegram/callback";
  static const String _authEndpoint = "/auth/telegram";

  @override
  void initState() {
    super.initState();
    _initWebViewController();
  }

  void _initWebViewController() {
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
          onProgress: (int progress) => _handleLoadingProgress(progress),
          onPageStarted: (_) => _handlePageStart(),
          onPageFinished: (_) => _handlePageFinish(),
          onWebResourceError: (error) => _handleWebError(error),
          onNavigationRequest: (request) => _handleNavigation(request),
        ),
      )
      ..loadRequest(Uri.parse(_authUrl));

    if (controller.platform is AndroidWebViewController) {
      (controller.platform as AndroidWebViewController)
          .setMediaPlaybackRequiresUserGesture(false);
    }

    _controller = controller;
  }

  // URL helpers
  String get _authUrl => "https://oauth.telegram.org/auth?"
      "bot_id=$_botUsername&"
      "origin=${Uri.encodeComponent(_backendUrl)}&"
      "embed=1&"
      "request_access=write&"
      "return_to=${Uri.encodeComponent(_callbackUrl)}";

  String get _callbackUrl => "$_backendUrl$_callbackPath";
  String get _apiUrl => "$_backendUrl$_authEndpoint";

  // WebView handlers
  void _handleLoadingProgress(int progress) {
    if (progress == 100) {
      setState(() => _isLoading = false);
    }
  }

  void _handlePageStart() {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });
  }

  void _handlePageFinish() {
    setState(() => _isLoading = false);
  }

  void _handleWebError(WebResourceError error) {
    setState(() => _hasError = true);
    _reportError('Ошибка загрузки: ${error.description}');
  }

  NavigationDecision _handleNavigation(NavigationRequest request) {
    if (request.url.startsWith(_callbackUrl)) {
      _handleAuthCallback(request.url);
      return NavigationDecision.prevent;
    }
    return NavigationDecision.navigate;
  }

  // Auth callback processing
  Future<void> _handleAuthCallback(String url) async {
    try {
      final uri = Uri.parse(url);
      final params = uri.queryParameters;

      if (!_validateAuthParams(params)) {
        throw Exception('Недостаточно данных для авторизации');
      }

      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'id': params['id'],
          'first_name': params['first_name'],
          'username': params['username'],
          'auth_date': params['auth_date'],
          'hash': params['hash'],
          'bot_username': _botUsername,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _handleSuccess(data['token']);
      } else {
        throw Exception('Ошибка сервера: ${response.statusCode}');
      }
    } catch (e) {
      _reportError(e.toString());
    }
  }

  bool _validateAuthParams(Map<String, String?> params) {
    const requiredParams = ['id', 'first_name', 'auth_date', 'hash'];
    return requiredParams.every((param) => params[param]?.isNotEmpty ?? false);
  }

  // Result handlers
  void _handleSuccess(String token) {
    if (widget.onAuthSuccess != null) {
      widget.onAuthSuccess!(token);
    } else {
      Navigator.pop(context, token);
    }
  }

  void _reportError(String message) {
    debugPrint('TelegramAuth Error: $message');
    if (widget.onError != null) {
      widget.onError!(message);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
      if (mounted) Navigator.pop(context);
    }
  }

  // UI
  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_isLoading) {
          _reportError('Авторизация отменена');
          return true;
        }
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Вход через Telegram'),
          actions: [
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_hasError) {
      return _buildErrorView();
    }

    return Stack(
      children: [
        WebViewWidget(controller: _controller),
        if (_isLoading) const Center(child: CircularProgressIndicator()),
      ],
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 16),
          const Text('Ошибка загрузки', style: TextStyle(fontSize: 18)),
          const SizedBox(height: 8),
          const Text('Проверьте подключение к интернету'),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _retryLoading,
            child: const Text('Повторить попытку'),
          ),
        ],
      ),
    );
  }

  void _retryLoading() {
    setState(() {
      _hasError = false;
      _isLoading = true;
    });
    _controller.reload();
  }
}
