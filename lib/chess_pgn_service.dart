import 'dart:io';
import 'dart:convert';
import 'chess_models.dart';

/// Service to parse raw OCR data and generate PGN
class OcrToPgnService {
  /// Load OCR extraction from JSON file
  static Future<OcrExtraction> loadFromFile(String filePath) async {
    try {
      final file = File(filePath);
      final jsonString = await file.readAsString();
      return loadFromJson(jsonString);
    } catch (e) {
      throw Exception('File read error: $e');
    }
  }

  /// Load OCR extraction from JSON string
  static Future<OcrExtraction> loadFromJson(String jsonString) async {
    try {
      final json = jsonDecode(jsonString);
      return OcrExtraction.fromJson(json);
    } catch (e) {
      throw Exception('JSON parsing error: $e');
    }
  }

  /// Convert figurine notation to algebraic
  /// Example: ♘f3 → Nf3
  static String convertFigurineToAlgebraic(String notation) {
    const figurineMap = {
      '♔': 'K',
      '♕': 'Q',
      '♖': 'R',
      '♗': 'B',
      '♘': 'N',
      '♙': '',
      '♚': 'k',
      '♛': 'q',
      '♜': 'r',
      '♝': 'b',
      '♞': 'n',
      '♟': '',
    };

    String result = notation;
    figurineMap.forEach((figurine, letter) {
      result = result.replaceAll(figurine, letter);
    });

    return result.trim();
  }

  /// Validate a move in PGN format
  static bool isValidMove(String move) {
    final pattern = RegExp(
      r'^[KQRBN]?[a-h]?[1-8]?[x@]?[a-h][1-8](?:=[QRBN])?[+#!?]*$|^O-O(?:-O)?[+#!?]*$',
    );
    return pattern.hasMatch(move);
  }

  /// Fix invalid moves with heuristics
  static String fixMove(String move) {
    String fixed = move.trim();

    // Remove spaces
    fixed = fixed.replaceAll(' ', '');

    // Convert figurine to algebraic
    fixed = convertFigurineToAlgebraic(fixed);

    // Normalize castling
    if (fixed.contains('O-O-O') || fixed.contains('0-0-0')) {
      final annotation = RegExp(r'[+#!?]*').firstMatch(fixed)?.group(0) ?? '';
      fixed = 'O-O-O$annotation';
    }
    if (fixed.contains('O-O') || fixed.contains('0-0')) {
      final annotation = RegExp(r'[+#!?]*').firstMatch(fixed)?.group(0) ?? '';
      fixed = 'O-O$annotation';
    }

    // Remove invalid characters
    fixed = fixed.replaceAll(RegExp(r'[^a-hKQRBN0-9x=+#!?\-O]'), '');

    return fixed;
  }

  /// Extract game sections from all pages
  /// Returns list of game texts (grouped by move number patterns)
  static List<String> extractGameSections(OcrExtraction extraction) {
    final allText = extraction.getAllText();
    
    // Split by common game separators
    final gameSections = allText.split(RegExp(r'\n\s*\n'));
    
    return gameSections
        .where((section) => section.trim().isNotEmpty)
        .toList();
  }

  /// Extract moves from a game section (text with "1. e4 c5" format)
  static List<String> extractMovesFromText(String gameText) {
    final moves = <String>[];
    
    // Pattern: number. white_move [black_move]
    final movePattern = RegExp(
      r'(\d+)(?:\.\s*|\.\.\.\s+)'
      r'([A-Za-z0-9\-@x=]+)'
      r'(?:\s+([A-Za-z0-9\-@x=]+))?',
    );

    for (final match in movePattern.allMatches(gameText)) {
      final whiteMove = match.group(2)?.trim() ?? '';
      final blackMove = match.group(3)?.trim();

      if (whiteMove.isNotEmpty) {
        moves.add(whiteMove);
        if (blackMove != null && blackMove.isNotEmpty) {
          moves.add(blackMove);
        }
      }
    }

    return moves;
  }

  /// Build PGN from extraction using advanced parsing
  static String buildPgnFromExtraction(
    OcrExtraction extraction, {
    String? white,
    String? black,
    String? date,
    String? event,
    String? site,
    String result = '*',
  }) {
    // Import AdvancedPgnParser
    // This requires adding: import 'pgn_parser.dart';
    // For now, use the simple version
    
    final buffer = StringBuffer();
    buffer.writeln('[Event "${ event ?? 'Chess Game'}"]');
    buffer.writeln('[Site "${ site ?? '?'}"]');
    buffer.writeln('[Date "${ date ?? '????.??.??'}"]');
    buffer.writeln('[White "${ white ?? '?'}"]');
    buffer.writeln('[Black "${ black ?? '?'}"]');
    buffer.writeln('[Result "$result"]');
    buffer.writeln();
    buffer.write('*');

    return buffer.toString();
  }

  /// Parse a game text to extract moves
  /// Returns list of moves in order
  static List<String> extractMoves(String gameText) {
    final moves = <String>[];
    
    // Pattern: number. white_move black_move
    final movePattern = RegExp(
      r'(\d+)(?:\.\s*|\.\.\.\s+)'
      r'([KQRBN]?[a-h]?[1-8]?[x@]?[a-h][1-8](?:=[QRBN])?[+#!?]*|O-O(?:-O)?[+#!?]*)'
      r'(?:\s+([KQRBN]?[a-h]?[1-8]?[x@]?[a-h][1-8](?:=[QRBN])?[+#!?]*|O-O(?:-O)?[+#!?]*)?)?',
    );

    for (final match in movePattern.allMatches(gameText)) {
      final whiteMove = match.group(2)?.trim() ?? '';
      final blackMove = match.group(3)?.trim();

      if (whiteMove.isNotEmpty) {
        moves.add(whiteMove);
        if (blackMove != null && blackMove.isNotEmpty) {
          moves.add(blackMove);
        }
      }
    }

    return moves;
  }

  /// Extract player names from game text
  static Map<String, String> extractPlayers(String gameText) {
    final players = <String, String>{};

    // Look for patterns: White: ..., Black: ..., etc.
    final whitePattern = RegExp(r'(?:White|Blanc)\s*[:=]\s*([A-Za-zàâäæéèêëïîôöœúùûü\s\-]+?)(?:[,\n]|Black|Noir)', multiLine: true);
    final blackPattern = RegExp(r'(?:Black|Noir)\s*[:=]\s*([A-Za-zàâäæéèêëïîôöœúùûü\s\-]+?)(?:[,\n]|$)', multiLine: true);

    final whiteMatch = whitePattern.firstMatch(gameText);
    if (whiteMatch != null) {
      players['white'] = whiteMatch.group(1)?.trim() ?? '';
    }

    final blackMatch = blackPattern.firstMatch(gameText);
    if (blackMatch != null) {
      players['black'] = blackMatch.group(1)?.trim() ?? '';
    }

    return players;
  }

  /// Extract metadata (date, event, etc.)
  static Map<String, String> extractMetadata(String gameText) {
    final metadata = <String, String>{};

    // Date pattern
    final datePattern = RegExp(r'(?:Date|Année)\s*[:=]\s*(\d{4}[.\-/]?\d{0,2}[.\-/]?\d{0,2})', multiLine: true);
    final dateMatch = datePattern.firstMatch(gameText);
    if (dateMatch != null) {
      metadata['date'] = dateMatch.group(1) ?? '';
    }

    // Event pattern
    final eventPattern = RegExp(r'(?:Event|Événement)\s*[:=]\s*([^\n,]+)', multiLine: true);
    final eventMatch = eventPattern.firstMatch(gameText);
    if (eventMatch != null) {
      metadata['event'] = eventMatch.group(1)?.trim() ?? '';
    }

    // Site pattern
    final sitePattern = RegExp(r'(?:Site|Lieu)\s*[:=]\s*([^\n,]+)', multiLine: true);
    final siteMatch = sitePattern.firstMatch(gameText);
    if (siteMatch != null) {
      metadata['site'] = siteMatch.group(1)?.trim() ?? '';
    }

    return metadata;
  }

  /// Generate a PGN from extracted data
  static String generatePgn({
    required String white,
    required String black,
    String? date,
    String? event,
    String? site,
    required List<String> moves,
    String result = '*',
  }) {
    final buffer = StringBuffer();

    // Headers
    buffer.writeln('[Event "${event ?? 'Chess Game'}"]');
    buffer.writeln('[Site "${site ?? '?'}"]');
    buffer.writeln('[Date "${date ?? '????.??.??'}"]');
    buffer.writeln('[White "$white"]');
    buffer.writeln('[Black "$black"]');
    buffer.writeln('[Result "$result"]');
    buffer.writeln();

    // Moves
    for (int i = 0; i < moves.length; i += 2) {
      final moveNum = (i ~/ 2) + 1;
      final whiteMove = moves[i];

      buffer.write('$moveNum. $whiteMove ');

      if (i + 1 < moves.length) {
        final blackMove = moves[i + 1];
        buffer.write('$blackMove ');
      }
    }

    buffer.write(result);

    return buffer.toString();
  }

  /// Generate a report of the extraction
  static String generateReport(OcrExtraction extraction) {
    final buffer = StringBuffer();
    buffer.writeln('╔════════════════════════════════════════╗');
    buffer.writeln('║     OCR EXTRACTION REPORT              ║');
    buffer.writeln('╚════════════════════════════════════════╝\n');

    buffer.writeln('Statistics:');
    buffer.writeln('  • Total pages: ${extraction.totalPages}');
    buffer.writeln('  • Total fragments: ${extraction.totalFragments}');
    buffer.writeln('  • Valid: ${extraction.isValid() ? '✓' : '✗'}');
    buffer.writeln();

    for (int i = 0; i < extraction.pages.length; i++) {
      final page = extraction.pages[i];
      buffer.writeln('Page ${page.pageNumber}:');
      buffer.writeln('  • Dimensions: ${page.width} x ${page.height}');
      buffer.writeln('  • Fragments: ${page.fragments.length}');
      
      // Show sample fragments
      final sampleSize = 3;
      final samples = page.fragments.take(sampleSize).toList();
      for (final frag in samples) {
        buffer.writeln('    - "${frag.text}" (confidence: ${frag.confidence}%)');
      }
      
      if (page.fragments.length > sampleSize) {
        buffer.writeln('    ... and ${page.fragments.length - sampleSize} more');
      }
      buffer.writeln();
    }

    return buffer.toString();
  }
}
