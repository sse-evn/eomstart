import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LanguageProvider extends ChangeNotifier {
  String _locale = 'ru'; // 'ru' or 'kk'
  String get locale => _locale;

  LanguageProvider() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _locale = prefs.getString('app_language') ?? 'ru';
    notifyListeners();
  }

  Future<void> setLocale(String languageCode) async {
    _locale = languageCode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_language', languageCode);
    notifyListeners();
  }
}

String tr(BuildContext context, String ru, String kk) {
  try {
    final provider = context.watch<LanguageProvider>();
    return provider.locale == 'ru' ? ru : kk;
  } catch (_) {
    return ru; // fallback
  }
}
