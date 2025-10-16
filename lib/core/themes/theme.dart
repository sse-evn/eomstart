import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:micro_mobility_app/core/themes/colors.dart';

const Color primaryColor = AppColors.primary;


final ThemeData lightMode = ThemeData(
  brightness: Brightness.light,

  primaryColor: primaryColor,
  colorScheme: ColorScheme.light(
    primary: primaryColor,
    secondary: Colors.white,
    shadow: const Color.fromARGB(255, 201, 201, 201),
  ),

  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: primaryColor,
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ),
  ),
  cardTheme: const CardThemeData(
    elevation: 1,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(16)),
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: primaryColor),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: primaryColor),
    ),
  ),
  visualDensity: VisualDensity.adaptivePlatformDensity,
);


final ThemeData darkMode = ThemeData(
  brightness: Brightness.dark,

  primaryColor: primaryColor,
  colorScheme: ColorScheme.dark(
    primary: primaryColor,
    secondary: const Color.fromARGB(255, 59, 59, 59),
    shadow: const Color.fromARGB(255, 32, 32, 32),
  ),

);