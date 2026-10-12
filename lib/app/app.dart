import 'package:flutter/material.dart';

import '../features/groceries/presentation/pages/grocery_page.dart';

class HeladeraApp extends StatelessWidget {
  const HeladeraApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seedColor = Color(0xFF477A5B);
    return MaterialApp(
      title: 'La heladera',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: seedColor),
        scaffoldBackgroundColor: const Color(0xFFF7F8F4),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      home: const GroceryPage(),
    );
  }
}
