// // widgets/app_bottom_navigation_bar.dart
// import 'package:flutter/material.dart';

// class AppBottomNavigationBar extends StatelessWidget {
//   final int currentIndex;
//   final Function(int) onTap;

//   const AppBottomNavigationBar({
//     super.key,
//     required this.currentIndex,
//     required this.onTap,
//   });

//   @override
//   Widget build(BuildContext context) {
//     return BottomNavigationBar(
//       type: BottomNavigationBarType.fixed, // Чтобы все элементы были видны
//       selectedItemColor:
//           Color.fromARGB(255, 221, 17, 17), // Активный зеленый цвет
//       unselectedItemColor: Colors.grey, // Серый для неактивных
//       currentIndex: currentIndex,
//       onTap: onTap,
//       items: const [
//         BottomNavigationBarItem(
//           icon: Icon(Icons.home),
//           label: 'Главная',
//         ),
//         BottomNavigationBarItem(
//           icon: Icon(Icons.qr_code),
//           label: 'QR',
//         ),
//         BottomNavigationBarItem(
//           icon: Icon(Icons.map),
//           label: 'Карта',
//         ),
//         BottomNavigationBarItem(
//           icon: Icon(Icons.person),
//           label: 'Профиль',
//         ),
//       ],
//     );
//   }
// }
