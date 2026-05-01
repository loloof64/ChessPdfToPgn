import 'dart:io';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../core/models/chess_game.dart';
import '../../core/models/game_extraction_config.dart';
import '../../core/models/page_layout.dart';
import '../../core/services/opencv_service.dart';
import '../../core/services/page_analyzer.dart';
import '../../core/services/tesseract_service.dart';
import '../../features/config/config_screen.dart';
import '../../features/export/pgn_serializer.dart';
import '../../features/processing/pgn_parser.dart';

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class ExtractionScreen extends StatefulWidget {
  final GameExtractionConfig config;

  const ExtractionScreen({required this.config, super.key});

  @override
  State<ExtractionScreen> createState() => _ExtractionScreenState();
}

class _ExtractionScreenState extends State<ExtractionScreen> {
  // Services — rebuilt on config change
  late TesseractService _tesseract;
  late OpenCvService _opencv;
  late PageAnalyzer _analyzer;
  late PgnParser _parser;
  final PgnSerializer _serializer = PgnSerializer();

  // Config — mutable, updated via Settings
  late GameExtractionConfig _config;

  // State
  _ExtractionStatus _status = _ExtractionStatus.idle;
  String _statusMsg = '';
  double? _progress;
  final List<ChessGame> _games = [];
  String? _errorMsg;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _config = widget.config;
    _rebuildServices();
  }

  /// Rebuilds all config-dependent services.
  /// Called on init and whenever settings are updated.
  void _rebuildServices() {
    _tesseract = TesseractService(
      tessLang: _config.locale.tessLang,
      psm: PageSegMode.singleBlock,
    );
    _opencv = OpenCvService();
    _analyzer = PageAnalyzer(_opencv);
    _parser = PgnParser(_config);
  }

  // ---------------------------------------------------------------------------
  // Settings
  // ---------------------------------------------------------------------------

  Future<void> _openSettings() async {
    final updated = await showDialog<GameExtractionConfig>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 600),
          child: ConfigScreen(
            initialConfig: _config,
            onConfirmed: (config) => Navigator.of(context).pop(config),
          ),
        ),
      ),
    );

    if (updated == null) return;

    setState(() {
      _config = updated;
      _rebuildServices();
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Settings updated — applies to next extraction'),
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // File picking
  // ---------------------------------------------------------------------------

  Future<void> _pickAndProcess() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg', 'tiff', 'bmp'],
      dialogTitle: 'Select a chess book or image',
    );
    if (result == null || result.files.isEmpty) return;

    final path = result.files.single.path!;
    final ext = p.extension(path).toLowerCase();

    setState(() {
      _status = _ExtractionStatus.running;
      _statusMsg = 'Preparing…';
      _progress = null;
      _games.clear();
      _errorMsg = null;
    });

    try {
      final imagePaths = ext == '.pdf' ? await _rasterizePdf(path) : [path];

      await _processPages(imagePaths);

      setState(() => _status = _ExtractionStatus.done);
    } catch (e) {
      setState(() {
        _status = _ExtractionStatus.error;
        _errorMsg = e.toString();
      });
    }
  }

  // ---------------------------------------------------------------------------
  // PDF rasterization
  // ---------------------------------------------------------------------------

  Future<List<String>> _rasterizePdf(String pdfPath) async {
    setState(() => _statusMsg = 'Rasterizing PDF…');

    final tmpDir = await getTemporaryDirectory();
    final outDir = Directory(p.join(tmpDir.path, 'chess_extractor_pages'));
    await outDir.create(recursive: true);

    final doc = await PdfDocument.openFile(pdfPath);
    final pageCount = doc.pages.length;
    final imagePaths = <String>[];

    for (var i = 0; i < pageCount; i++) {
      setState(() {
        _statusMsg = 'Rasterizing page ${i + 1} / $pageCount…';
        _progress = (i + 1) / pageCount;
      });

      final page = doc.pages[i];
      const scale = 300 / 72.0;
      final fullWidth = (page.width * scale).round().toDouble();
      final fullHeight = (page.height * scale).round().toDouble();

      final image = await page.render(
        fullWidth: fullWidth,
        fullHeight: fullHeight,
        backgroundColor: 0xFFFFFFFF,
      );
      if (image == null) continue;

      final outPath = p.join(
        outDir.path,
        'page_${(i + 1).toString().padLeft(4, '0')}.png',
      );
      await File(outPath).writeAsBytes(image.pixels);
      image.dispose();
      imagePaths.add(outPath);
    }

    await doc.dispose();
    return imagePaths;
  }

  // ---------------------------------------------------------------------------
  // Page processing pipeline
  // ---------------------------------------------------------------------------

  Future<void> _processPages(List<String> imagePaths) async {
    final total = imagePaths.length;
    final pendingTexts = <String>[];
    bool gameStarted = false;

    for (var i = 0; i < total; i++) {
      final path = imagePaths[i];

      setState(() {
        _statusMsg = 'Analyzing page ${i + 1} / $total…';
        _progress = (i + 1) / total;
      });

      // Step 1 — Layout analysis
      final analyzedPage = await _analyzer.analyze(path);

      // Step 2 — Intro/appendix pages → skip
      if (analyzedPage.isIntroPage) continue;

      // Step 3 — Process each column independently
      for (final column in analyzedPage.columns) {
        final boundaries = _analyzer.detectGameBoundaries(analyzedPage);

        for (final block in column.blocks) {
          // Check if this block starts a new game boundary
          final boundary = boundaries.firstWhereOrNull(
            (b) => b.header.bounds == block.bounds,
          );

          if (boundary != null) {
            if (pendingTexts.isNotEmpty) {
              _flushGame(pendingTexts);
              pendingTexts.clear();
            }
            if (boundary.header.text != null) {
              pendingTexts.add(boundary.header.text!);
            }
            if (boundary.subtitle?.text != null) {
              pendingTexts.add(boundary.subtitle!.text!);
            }
            if (boundary.hasCustomStartPosition) {
              pendingTexts.add('[FEN "${boundary.startDiagram!.fen}"]');
            }
            gameStarted = false;
            continue;
          }

          // Normal block processing
          switch (block) {
            case DiagramBlock():
              if (!gameStarted && block.fen != null) {
                pendingTexts.add('[FEN "${block.fen}"]');
                gameStarted = true;
              }

            case HeaderBlock() when block.isGameHeader:
              if (pendingTexts.isNotEmpty) {
                _flushGame(pendingTexts);
                pendingTexts.clear();
              }
              if (block.text != null) pendingTexts.add(block.text!);
              gameStarted = false;

            case TextBlock():
              setState(() => _statusMsg = 'OCR — page ${i + 1} / $total…');
              final preprocessed = await _opencv.preprocessBookPage(path);
              final text = await _tesseract.extractText(preprocessed);
              if (text.isNotEmpty) {
                pendingTexts.add(text);
                gameStarted = true;
              }

            default:
              break;
          }
        }
      }
    }

    // Flush the last pending game
    if (pendingTexts.isNotEmpty) _flushGame(pendingTexts);
  }

  // ---------------------------------------------------------------------------
  // Game flushing
  // ---------------------------------------------------------------------------

  void _flushGame(List<String> textBlocks) {
    final rawText = textBlocks.join('\n');
    final game = _parser.parse(rawText);
    if (game.moves.isEmpty) return;
    setState(() => _games.add(game));
  }

  // ---------------------------------------------------------------------------
  // PGN export
  // ---------------------------------------------------------------------------

  Future<void> _exportPgn() async {
    final savePath = await FilePicker.saveFile(
      dialogTitle: 'Export PGN',
      fileName: 'chess_extraction.pgn',
      type: FileType.custom,
      allowedExtensions: ['pgn'],
    );
    if (savePath == null) return;

    final buffer = StringBuffer();
    for (final game in _games) {
      buffer.writeln(_serializer.serialize(game));
      buffer.writeln();
    }

    await File(savePath).writeAsString(buffer.toString());

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Exported ${_games.length} game(s) to $savePath'),
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chess Extractor'),
        actions: [
          IconButton(
            onPressed: _openSettings,
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
          ),
          if (_games.isNotEmpty)
            TextButton.icon(
              onPressed: _exportPgn,
              icon: const Icon(Icons.download),
              label: const Text('Export PGN'),
            ),
        ],
      ),
      body: Column(
        children: [
          if (_status == _ExtractionStatus.running)
            _ProgressBanner(message: _statusMsg, progress: _progress),

          if (_status == _ExtractionStatus.error && _errorMsg != null)
            _ErrorBanner(message: _errorMsg!),

          Expanded(
            child: _games.isEmpty
                ? _EmptyState(status: _status, onPickFile: _pickAndProcess)
                : _GameList(games: _games),
          ),
        ],
      ),
      floatingActionButton: _status != _ExtractionStatus.running
          ? FloatingActionButton.extended(
              onPressed: _pickAndProcess,
              icon: const Icon(Icons.file_open),
              label: const Text('Open file'),
            )
          : null,
    );
  }
}

// ---------------------------------------------------------------------------
// Status enum
// ---------------------------------------------------------------------------

enum _ExtractionStatus { idle, running, done, error }

// ---------------------------------------------------------------------------
// Sub-widgets
// ---------------------------------------------------------------------------

class _ProgressBanner extends StatelessWidget {
  final String message;
  final double? progress;

  const _ProgressBanner({required this.message, this.progress});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 6),
          LinearProgressIndicator(value: progress),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: Theme.of(context).colorScheme.errorContainer,
      child: Text(
        message,
        style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final _ExtractionStatus status;
  final VoidCallback onPickFile;

  const _EmptyState({required this.status, required this.onPickFile});

  @override
  Widget build(BuildContext context) {
    final isIdle = status == _ExtractionStatus.idle;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isIdle ? Icons.grid_on : Icons.search_off,
            size: 64,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          const SizedBox(height: 16),
          Text(
            isIdle
                ? 'Open a chess book or image to begin'
                : 'No games found in this document',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          if (isIdle) ...[
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onPickFile,
              icon: const Icon(Icons.file_open),
              label: const Text('Open file'),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Game list
// ---------------------------------------------------------------------------

class _GameList extends StatelessWidget {
  final List<ChessGame> games;
  const _GameList({required this.games});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: games.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) => _GameTile(game: games[i], index: i),
    );
  }
}

class _GameTile extends StatelessWidget {
  final ChessGame game;
  final int index;

  const _GameTile({required this.game, required this.index});

  @override
  Widget build(BuildContext context) {
    final event = game.headers['Event'] ?? '?';
    final result = game.result ?? '*';
    final moves = game.moves.length;
    final fen = game.headers['FEN'];

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
        child: Text(
          '${index + 1}',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSecondaryContainer,
          ),
        ),
      ),
      title: Text(
        event,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        '$moves moves  ·  $result'
        '${fen != null ? '  ·  custom start' : ''}',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      trailing: _ResultBadge(result: result),
    );
  }
}

class _ResultBadge extends StatelessWidget {
  final String result;
  const _ResultBadge({required this.result});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (result) {
      '1-0' => ('1-0', Colors.blue.shade100),
      '0-1' => ('0-1', Colors.red.shade100),
      '1/2-1/2' => ('½-½', Colors.green.shade100),
      _ => ('*', Colors.grey.shade200),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}
