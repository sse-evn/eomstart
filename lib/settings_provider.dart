import 'package:flutter/material.dart';

class SettingsProvider extends ChangeNotifier {
  // Состояние для темы
  Brightness _currentBrightness = Brightness.light;
  Brightness get currentBrightness => _currentBrightness;

  // Новое состояние для уведомлений
  bool _notificationsEnabled = true;
  bool get notificationsEnabled => _notificationsEnabled;

  // Метод для переключения темы
  void toggleTheme() {
    _currentBrightness = _currentBrightness == Brightness.light
        ? Brightness.dark
        : Brightness.light;
    notifyListeners();
  }

  // Новый метод для переключения уведомлений
  void toggleNotifications(bool value) {
    _notificationsEnabled = value;
    notifyListeners();
  }
}
