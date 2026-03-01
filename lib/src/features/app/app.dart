
import 'package:flutter/material.dart';
import 'package:micro_mobility_app/src/features/profile/promo_code_screen.dart';
import 'package:micro_mobility_app/src/core/providers/theme_provider.dart';
import 'package:provider/provider.dart';
// Screens
import 'package:micro_mobility_app/src/features/auth_screen/login_screen.dart';
import 'package:micro_mobility_app/src/features/auth_screen/pending_screen.dart';
import 'package:micro_mobility_app/src/features/app/ui/bottom_navigation.dart';
import 'package:micro_mobility_app/src/features/profile/profile_screen.dart';
import 'package:micro_mobility_app/src/features/profile/settings_screen.dart';
import 'package:micro_mobility_app/src/features/profile/about_screen.dart';
import 'package:micro_mobility_app/src/features/map_screen/map_screens.dart';
import 'package:micro_mobility_app/src/features/qr_scanner_screen/qr_scanner_screen.dart';
import 'package:micro_mobility_app/src/features/admin/admin_panel_screen.dart';
import 'package:micro_mobility_app/src/features/app/ui/splash_screen.dart';




class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Оператор микромобильности',
      theme: Provider.of<ThemeProvider>(context).themeData,
      debugShowCheckedModeBanner: false,
      initialRoute: '/splash',
      routes: {
        '/splash': (context) => const SplashScreen(),
        '/login': (context) => const LoginScreen(),
        '/dashboard': (context) => const DashboardScreen(),
        '/profile': (context) => const ProfileScreen(),
        '/settings': (context) => const SettingsScreen(),
        '/about': (context) => const AboutScreen(),
        '/promo': (context) => const PromoCodeScreen(),
        '/map': (context) => const MapScreen(),
        '/qr_scanner': (context) => const QrScannerScreen(),
        '/admin': (context) => const AdminPanelScreen(),
        '/pending': (context) => const PendingApprovalScreen(),
      },
    );
  }
}
