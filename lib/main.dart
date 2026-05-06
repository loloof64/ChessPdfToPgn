import 'package:flutter/material.dart';
import 'chess_pgn_export_screen.dart';

void main() {
  runApp(const OcrToPgnApp());
}

class OcrToPgnApp extends StatelessWidget {
  const OcrToPgnApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chess OCR to PGN',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.grey.shade900,
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.grey.shade900,
          brightness: Brightness.dark,
        ),
      ),
      themeMode: ThemeMode.system,
      home: OcrToPgnScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
