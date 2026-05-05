import 'package:flutter/material.dart';
import 'chess_pgn_export_screen.dart';

void main() {
  runApp(const ChessPgnApp());
}

class ChessPgnApp extends StatelessWidget {
  const ChessPgnApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chess PGN Converter',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.grey.shade900,
          brightness: Brightness.light,
        ),
        typography: Typography.material2021(),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.grey.shade900,
          brightness: Brightness.dark,
        ),
      ),
      themeMode: ThemeMode.system,
      home: ChessPgnExportScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
