import 'dart:io';

import 'package:flutter/material.dart';
import 'core/models/game_extraction_config.dart';
import 'core/services/tesseract_service.dart';
import 'features/config/config_screen.dart';

void main() {
  runApp(const ChessExtractorApp());
}

class ChessExtractorApp extends StatelessWidget {
  const ChessExtractorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chess Extractor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.blueGrey, useMaterial3: true),
      home: const _TesseractGate(),
    );
  }
}

// ---------------------------------------------------------------------------
// Gate — checks Tesseract availability before entering the app
// ---------------------------------------------------------------------------

class _TesseractGate extends StatefulWidget {
  const _TesseractGate();

  @override
  State<_TesseractGate> createState() => _TesseractGateState();
}

class _TesseractGateState extends State<_TesseractGate> {
  late final Future<String?> _versionFuture;

  @override
  void initState() {
    super.initState();
    _versionFuture = TesseractService.detectVersion();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _versionFuture,
      builder: (context, snapshot) {
        // Still checking
        if (snapshot.connectionState != ConnectionState.done) {
          return const _SplashScreen();
        }

        // Tesseract not found
        if (snapshot.data == null) {
          return const _TesseractMissingScreen();
        }

        // Tesseract found — proceed to config
        return _AppRoot(tesseractVersion: snapshot.data!);
      },
    );
  }
}

// ---------------------------------------------------------------------------
// App root — holds the extraction config in state
// ---------------------------------------------------------------------------

class _AppRoot extends StatefulWidget {
  final String tesseractVersion;

  const _AppRoot({required this.tesseractVersion});

  @override
  State<_AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<_AppRoot> {
  GameExtractionConfig? _config;

  @override
  Widget build(BuildContext context) {
    // No config yet — show the configuration screen
    if (_config == null) {
      return ConfigScreen(
        onConfirmed: (config) => setState(() => _config = config),
      );
    }

    // Config set — placeholder for the main extraction screen
    // TODO: replace with the actual extraction screen
    return Scaffold(
      appBar: AppBar(title: const Text('Chess Extractor')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.check_circle_outline,
              size: 64,
              color: Colors.green,
            ),
            const SizedBox(height: 16),
            Text(
              'Ready — ${widget.tesseractVersion}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Locale: ${_config!.locale.name}  |  '
              'Figurines: ${_config!.usesFigurine}  |  '
              'Comments: ${_config!.commentStyle.name}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 32),
            OutlinedButton(
              onPressed: () => setState(() => _config = null),
              child: const Text('Change settings'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Splash screen — shown while detecting Tesseract
// ---------------------------------------------------------------------------

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Checking Tesseract…'),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tesseract missing screen — shown if Tesseract is not in PATH
// ---------------------------------------------------------------------------

class _TesseractMissingScreen extends StatelessWidget {
  const _TesseractMissingScreen();

  String get _installCommand => Platform.isWindows
      ? 'winget install UB-Mannheim.TesseractOCR'
      : 'sudo apt install tesseract-ocr tesseract-ocr-fra';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 16),
                Text(
                  'Tesseract not found',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Tesseract OCR must be installed and available in your PATH.',
                ),
                const SizedBox(height: 24),
                Text(
                  'Install command:',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    _installCommand,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'After installation, restart the application.',
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
