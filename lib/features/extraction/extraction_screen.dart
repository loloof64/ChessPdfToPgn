import 'dart:io';
import 'package:chess_pdf_to_pgn/core/models/chess_move.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:dartcv4/dartcv.dart' as cv;

import '../../core/models/chess_game.dart';
import '../../core/models/game_extraction_config.dart';
import '../../core/models/page_layout.dart';
import '../../core/services/diagram_classifier.dart';
import '../../core/services/opencv_service.dart';
import '../../core/services/page_analyzer.dart';
import '../../core/services/tesseract_service.dart';
import '../../features/config/config_screen.dart';
import '../../features/export/pgn_serializer.dart';
import '../../features/processing/move_validator.dart';
import '../../features/processing/pgn_parser.dart';
import '../../core/models/ocr_line.dart';
import '../../features/processing/smart_pgn_parser.dart';

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
  final MoveValidator _validator = MoveValidator();
  final SmartPGNParser _smartParser = SmartPGNParser();

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

  void _rebuildServices() {
    _tesseract = TesseractService(
      // Always use standard 'eng' — eng_chess model not available
      tessLang: 'eng',
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

    // Ask user for extraction options before processing
    if (!mounted) return;
    final config = await showDialog<GameExtractionConfig>(
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

    // User dismissed the dialog — cancel extraction
    if (config == null) return;

    // Update config and rebuild services with new settings
    setState(() {
      _config = config;
      _rebuildServices();
    });

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
      final fullWidth = (page.width * scale).round();
      final fullHeight = (page.height * scale).round();

      final image = await page.render(
        fullWidth: fullWidth.toDouble(),
        fullHeight: fullHeight.toDouble(),
        backgroundColor: 0xFFFFFFFF,
      );
      if (image == null) continue;

      final outPath = p.join(
        outDir.path,
        'page_${(i + 1).toString().padLeft(4, '0')}.png',
      );

      // pdfrx returns raw RGBA pixels — encode to proper PNG so OpenCV can read it
      final imgLib = img.Image.fromBytes(
        width: fullWidth,
        height: fullHeight,
        bytes: image.pixels.buffer,
        format: img.Format.uint8,
        numChannels: 4,
      );
      final pngBytes = img.encodePng(imgLib);
      await File(outPath).writeAsBytes(pngBytes);
      image.dispose();

      // DEBUG — save first page for visual inspection
      if (i == 0) {
        final debugPath =
            '/home/${Platform.environment['USER']}/Documents/temp/chess_debug_page1.png';
        await File(debugPath).writeAsBytes(pngBytes);
        debugPrint('DEBUG: page 1 saved to $debugPath');
      }

      imagePaths.add(outPath);
      debugPrint(
        'Rasterized page ${i + 1}: $outPath (${pngBytes.length} bytes)',
      );
    }

    await doc.dispose();
    return imagePaths;
  }

  // ---------------------------------------------------------------------------
  // Page processing pipeline
  // ---------------------------------------------------------------------------

  /// Corrects Tesseract misreadings of FAN chess glyphs (♘♗♖♕♔).
  /// Only called when usesFigurine is true in the extraction config.
  String _fixFanGlyphs(String text) {
    // Remove narrative lines starting with move number + ellipsis + move
    // e.g. "4,...exd5 leads to..." → these are commentary, not game moves
    text = text.replaceAll(
      RegExp(r'^\d+[,.]\.{2,3}[A-Za-z]\S+.*$', multiLine: true),
      '',
    );

    return text
        // Remove page header artifacts like "2/7"
        .replaceAll(RegExp(r'^\d+/\d+\s+', multiLine: true), '')
        // Knight with missing file letter: £6→Nf6, M3→Nf3
        .replaceAllMapped(RegExp(r'£(\d)'), (m) => 'Nf${m.group(1)}')
        .replaceAllMapped(RegExp(r'\bM(\d)\b'), (m) => 'Nf${m.group(1)}')
        // Knight with file letter: OM6, A\e3, Ae3, Mf3, 4\xd5, @xc3, 2xf5
        .replaceAllMapped(
          RegExp(r'(?:OM|A\\?|Mf?|4\\?|@|£f?|2)([a-h]?[1-8]|x[a-h][1-8])'),
          (m) {
            final square = m.group(1)!;
            if (RegExp(r'^\d').hasMatch(square)) return m.group(0)!;
            return 'N$square';
          },
        )
        // Bishop: &b4
        .replaceAllMapped(
          RegExp(r'&([a-h][1-8]|x[a-h][1-8])'),
          (m) => 'B${m.group(1)}',
        )
        // Rook: Za1
        .replaceAllMapped(
          RegExp(r'Z([a-h][1-8]|x[a-h][1-8])'),
          (m) => 'R${m.group(1)}',
        )
        // Queen: Wd3, Wwd3
        .replaceAllMapped(
          RegExp(r'Ww?([a-h][1-8]|x[a-h][1-8])'),
          (m) => 'Q${m.group(1)}',
        )
        // Black move indicators
        .replaceAll('wes', '...')
        .replaceAll(RegExp(r'\bsa\b'), '...')
        .replaceAll('ees', '...');
  }

  /// Reconstructs move pairs from Fischer-style tabular format.
  /// Example: "1    d4    Nf6" → "1. d4 Nf6"
  String _reconstructMoveTable(String text) {
    final lines = text.split('\n');
    final result = <String>[];

    // SAN pattern covering both pawn moves (e4) and piece moves (Nf3, Bxe4)
    const sanPat =
        r'(?:[KQRBN][a-h]?[1-8]?x?)?[a-h]x?[a-h]?[1-8](?:=[QRBN])?[+#]?'
        r'|O-O(?:-O)?[+#]?';

    for (final line in lines) {
      final trimmed = line.trim();

      // Match: number + spaces + white_move + spaces + black_move
      final tableMatch = RegExp(
        '^(\\d+)\\s+($sanPat)\\s+($sanPat)\$',
      ).firstMatch(trimmed);

      if (tableMatch != null) {
        final num = tableMatch.group(1);
        final white = tableMatch.group(2);
        final black = tableMatch.group(3);
        result.add('$num. $white $black');
        continue;
      }

      // Match: number + spaces + dots + spaces + black_move
      final blackMatch = RegExp(
        '^(\\d+)\\s+\\.{1,3}\\s+($sanPat)\$',
      ).firstMatch(trimmed);

      if (blackMatch != null) {
        final num = blackMatch.group(1);
        final black = blackMatch.group(2);
        result.add('$num... $black');
        continue;
      }

      // Match: number + spaces + single white move only
      final whiteMatch = RegExp('^(\\d+)\\s+($sanPat)\$').firstMatch(trimmed);

      if (whiteMatch != null) {
        final num = whiteMatch.group(1);
        final white = whiteMatch.group(2);
        result.add('$num. $white');
        continue;
      }

      result.add(line);
    }

    return result.join('\n');
  }

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
            // Diagram — only the first one per game is kept (start position)
            case DiagramBlock():
              if (!gameStarted) {
                try {
                  final boardImg = await cv.imreadAsync(
                    path,
                    flags: cv.IMREAD_COLOR,
                  );
                  final board800 = await cv.resizeAsync(boardImg, (800, 800));
                  final classifier = DiagramClassifier();
                  await classifier.init();
                  final fen = await classifier.boardToFen(board800);
                  const standardFen =
                      'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR';
                  if (fen != standardFen) {
                    pendingTexts.add('[FEN "$fen w KQkq - 0 1"]');
                  }
                  board800.dispose();
                  boardImg.dispose();
                  classifier.dispose();
                  gameStarted = true;
                } catch (e) {
                  debugPrint('DiagramClassifier error: $e');
                }
              }

            // Header block — signals a new game
            case HeaderBlock() when block.isGameHeader:
              if (pendingTexts.isNotEmpty) {
                _flushGame(pendingTexts);
                pendingTexts.clear();
              }
              if (block.text != null) pendingTexts.add(block.text!);
              gameStarted = false;

            // Text block — preprocess + OCR with spatial awareness
            case TextBlock():
              setState(() => _statusMsg = 'OCR — page ${i + 1} / $total…');

              // Step 1: Extract words WITH spatial coordinates
              final words = await _tesseract.extractWords(path);

              if (words.isEmpty) {
                continue;
              }

              // Step 2: Convert TesseractWord to OCRLine (spatial wrapper)
              final ocrLines = words
                  .map(
                    (w) => OCRLine(
                      text: w.text,
                      x: w.left,
                      y: w.top,
                      width: w.width,
                      height: w.height,
                      confidence: w.confidence,
                    ),
                  )
                  .toList();

              // Step 3: Use SmartPGNParser to extract moves and comments
              // respecting spatial layout (columns, rows, etc.)
              final extraction = _smartParser.extractMovesAndComments(ocrLines);

              // Step 4: Reconstruct text from smart extraction
              // Moves are already coherent (proper white/black pairing)
              var text = extraction.moves.join(' ');

              // Step 5: Apply post-processing (FAN glyphs, table reconstruction)
              if (_config.usesFigurine) {
                text = _fixFanGlyphs(text);
                text = _reconstructMoveTable(text);
              }

              // Step 6: Log extraction (for debugging)
              if (i == 0) {
                debugPrint('=== EXTRACTED MOVES (PAGE 1) ===');
                debugPrint('Moves: ${extraction.moves.length}');
                debugPrint(extraction.moves.join(" "));
                debugPrint('=== EXTRACTED COMMENTS ===');
                for (final comment in extraction.comments) {
                  debugPrint('  {$comment}');
                }
                debugPrint('=== FIXED OCR PAGE 1 ===\n$text\n=== END ===');
              }

              // Step 7: Add to pending texts
              if (text.isNotEmpty) {
                pendingTexts.add(text);
                gameStarted = true;
              }

              // Step 8: Add extracted comments to pending texts
              // They will be merged with moves during pgn_parser phase
              for (final comment in extraction.comments) {
                if (comment.isNotEmpty) {
                  pendingTexts.add('{ $comment }');
                }
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

    // DEBUG — show parsed moves
    debugPrint('=== PARSED MOVES ===');
    for (final m in game.moves) {
      debugPrint(
        '  ${m.moveNumber}. ${m.color == PieceColor.white ? "W" : "B"} ${m.san}',
      );
    }
    debugPrint('=== END PARSED ===');

    if (game.moves.isEmpty) return;

    // Validate moves through chess engine
    final result = _validator.validate(game);
    final validatedGame = ChessGame(
      headers: game.headers,
      moves: result.validMoves,
      result: game.result,
    );
    if (validatedGame.moves.isEmpty) return;

    // Log invalid moves for debugging
    if (result.invalidMoves.isNotEmpty) {
      debugPrint(
        'Game "${game.headers['Event']}": '
        '${result.invalidMoves.length} invalid move(s) — '
        'accuracy: ${(result.accuracy * 100).toStringAsFixed(1)}%',
      );
      for (final inv in result.invalidMoves) {
        debugPrint(
          '  Move ${inv.move.moveNumber}. ${inv.move.san} '
          '(raw: ${inv.move.rawOcr}) — ${inv.reason}'
          '${inv.suggestion != null ? " → ${inv.suggestion}" : ""}',
        );
      }
    }

    setState(() => _games.add(validatedGame));
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
