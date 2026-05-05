import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chess PDF to PGN - Cloud OCR',
      home: Scaffold(
        appBar: AppBar(title: const Text('Chess PDF to PGN')),
        body: const Center(child: Text('Ready for OCR')),
      ),
    );
  }
}
