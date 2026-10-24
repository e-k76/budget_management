import 'package:flutter/material.dart';

const kPrimary = Color(0xFF3B5BDB);
const kIncome = Color(0xFF2F9E44);
const kExpense = Color(0xFFE8590C);

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: kPrimary, brightness: Brightness.light);
  const border = BorderSide(color: Color(0xFFE3E7EF));
  return ThemeData(
    useMaterial3: true,
    fontFamily: 'Vazirmatn',
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xFFF5F7FB),
    cardTheme: CardThemeData(
      elevation: 1.5,
      shadowColor: Colors.black12,
      color: Colors.white,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: border),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    dataTableTheme: const DataTableThemeData(
      headingRowColor: WidgetStatePropertyAll(Color(0xFFEEF1F8)),
      headingTextStyle: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF343A40)),
    ),
  );
}
