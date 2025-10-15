import 'package:flutter/material.dart';
import 'package:micro_mobility_app/core/themes/theme.dart';

class ThemeProvider extends ChangeNotifier {
  ThemeData _themeData = darkMode;
  ThemeData get themeData => _themeData;


  void setTheme({required ThemeData theme}) {
    _themeData = theme;
    notifyListeners();
  }
}