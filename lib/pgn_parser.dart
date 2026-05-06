import 'dart:async';
import 'chess_models.dart';
import 'move_validator.dart';

/// Advanced PGN parser that reconstructs games from raw OCR fragments
/// Uses async/await to avoid blocking UI
class AdvancedPgnParser {
  /// Group fragments into logical lines based on Y position (async version)
  static Future<List<String>> groupFragmentsIntoLinesAsync(
    List<TextFragment> fragments,
  ) async {
    return Future(() {
      if (fragments.isEmpty) return [];

      // Sort by Y, then X
      final sorted = List<TextFragment>.from(fragments);
      sorted.sort((a, b) {
        if ((a.y - b.y).abs() > 15) {
          return a.y.compareTo(b.y);
        }
        return a.x.compareTo(b.x);
      });

      final lines = <String>[];
      var currentLine = <String>[];
      int lastY = -1;

      for (final frag in sorted) {
        // New line if Y differs significantly
        if (lastY >= 0 && (frag.y - lastY).abs() > 15) {
          if (currentLine.isNotEmpty) {
            lines.add(currentLine.join(' '));
          }
          currentLine = [];
        }
        currentLine.add(frag.text);
        lastY = frag.y;
      }

      if (currentLine.isNotEmpty) {
        lines.add(currentLine.join(' '));
      }

      return lines;
    });
  }

  /// Extract metadata (white, black, date, event) from lines
  static Map<String, String> extractMetadata(List<String> lines) {
    final metadata = <String, String>{};

    for (final line in lines.take(20)) {
      // White player
      if (line.contains(
        RegExp(r'(?:White|Blanc)\s*[:=]', caseSensitive: false),
      )) {
        final match = RegExp(
          r'(?:White|Blanc)\s*[:=]\s*([A-Za-z\s\-]+)',
          caseSensitive: false,
        ).firstMatch(line);
        if (match != null) {
          metadata['white'] = match.group(1)?.trim() ?? '';
        }
      }

      // Black player
      if (line.contains(
        RegExp(r'(?:Black|Noir)\s*[:=]', caseSensitive: false),
      )) {
        final match = RegExp(
          r'(?:Black|Noir)\s*[:=]\s*([A-Za-z\s\-]+)',
          caseSensitive: false,
        ).firstMatch(line);
        if (match != null) {
          metadata['black'] = match.group(1)?.trim() ?? '';
        }
      }

      // Date
      if (line.contains(RegExp(r'Date|Année', caseSensitive: false))) {
        final match = RegExp(
          r'(\d{4}[.\-/]?\d{0,2}[.\-/]?\d{0,2})',
        ).firstMatch(line);
        if (match != null) {
          metadata['date'] = match.group(1) ?? '';
        }
      }

      // Event
      if (line.contains(RegExp(r'Event|Événement', caseSensitive: false))) {
        final match = RegExp(
          r'(?:Event|Événement)\s*[:=]\s*([^\n,]+)',
          caseSensitive: false,
        ).firstMatch(line);
        if (match != null) {
          metadata['event'] = match.group(1)?.trim() ?? '';
        }
      }
    }

    return metadata;
  }

  /// Extract all moves from lines (improved: use move numbers as anchors)
  static List<String> extractAllMoves(List<String> lines) {
    final moves = <String>[];
    final text = lines.join(' ');

    // First, find all move numbers (1., 2., 3., etc.)
    // These are reliable anchors
    final moveNumberPattern = RegExp(r'\b(\d+)\.\s+');

    final matches = moveNumberPattern.allMatches(text);

    for (final match in matches) {
      final moveNum = int.parse(match.group(1)!);
      final startPos = match.end;

      // Find the next move number (or end of text)
      final nextMatchPos = matches
          .firstWhere(
            (m) => int.parse(m.group(1)!) == moveNum + 1,
            orElse: () => match,
          )
          .start;

      // Extract text between this move number and next
      final moveText = nextMatchPos > startPos
          ? text.substring(startPos, nextMatchPos)
          : text.substring(startPos);

      // Extract white and black moves from this chunk
      // Look for chess moves (pieces + squares)
      final moveMatches = RegExp(
        r'([a-hKQRBN]?[a-h][1-8](?:=[QRBN])?[+#!?]*)',
      ).allMatches(moveText);

      final movesInChunk = moveMatches
          .map((m) => m.group(1)!)
          .where((m) => _looksLikeMove(m))
          .take(2) // Max 2 moves per turn (white + black)
          .toList();

      moves.addAll(movesInChunk);
    }

    return moves;
  }

  /// Check if text looks like a valid chess move
  static bool _looksLikeMove(String text) {
    // Must be 2-8 chars
    if (text.length < 2 || text.length > 8) return false;

    // Reject pure numbers
    if (RegExp(r'^\d+$').hasMatch(text)) return false;

    // Must have at least one file (a-h) or O (castling)
    if (!text.contains(RegExp(r'[a-hO]', caseSensitive: false))) return false;

    // Must have at least one rank (1-8)
    if (!text.contains(RegExp(r'[1-8]'))) return false;

    return true;
  }

  /// Extract comments from text
  static List<String> extractComments(List<String> lines) {
    final comments = <String>[];
    final text = lines.join(' ');

    // Extract text in braces {comment}
    final bracePattern = RegExp(r'\{([^}]+)\}');
    for (final match in bracePattern.allMatches(text)) {
      final comment = match.group(1)?.trim();
      if (comment != null && comment.isNotEmpty) {
        comments.add(comment);
      }
    }

    // Extract text in parentheses (comment)
    final parenPattern = RegExp(r'\(([^)]+)\)');
    for (final match in parenPattern.allMatches(text)) {
      final comment = match.group(1)?.trim();
      if (comment != null && comment.isNotEmpty) {
        comments.add(comment);
      }
    }

    return comments;
  }

  /// Generate PGN from extraction with move validation
  static Future<String> generatePgnAsync(
    OcrExtraction extraction, {
    String? white,
    String? black,
    String? date,
    String? event,
    String? site,
    String result = '*',
  }) async {
    return Future(() {
      // Get all fragments from all pages
      final allFragments = <TextFragment>[];
      for (final page in extraction.pages) {
        allFragments.addAll(page.fragments);
      }

      // Group into lines
      final lines = groupFragmentsIntoLinesSync(allFragments);

      // Extract metadata
      final foundMetadata = extractMetadata(lines);
      white ??= foundMetadata['white'] ?? '?';
      black ??= foundMetadata['black'] ?? '?';
      date ??= foundMetadata['date'] ?? '????.??.??';
      event ??= foundMetadata['event'] ?? 'Chess Game';
      site ??= '?';

      // Extract and validate moves using chess rules
      final rawMoves = extractAllMoves(lines);
      final validator = MoveValidator();
      final validMoves = <String>[];

      for (final move in rawMoves) {
        if (validator.tryMove(move)) {
          validMoves.add(move);
        }
      }

      // Build PGN
      final buffer = StringBuffer();
      buffer.writeln('[Event "$event"]');
      buffer.writeln('[Site "$site"]');
      buffer.writeln('[Date "$date"]');
      buffer.writeln('[White "$white"]');
      buffer.writeln('[Black "$black"]');
      buffer.writeln('[Result "$result"]');
      buffer.writeln();

      // Write moves
      for (int i = 0; i < validMoves.length; i += 2) {
        final moveNum = (i ~/ 2) + 1;
        buffer.write('$moveNum. ${validMoves[i]} ');

        if (i + 1 < validMoves.length) {
          buffer.write('${validMoves[i + 1]} ');
        }
      }

      buffer.write(result);

      return buffer.toString();
    });
  }

  /// Synchronous version of grouping (for internal use)
  static List<String> groupFragmentsIntoLinesSync(
    List<TextFragment> fragments,
  ) {
    if (fragments.isEmpty) return [];

    final sorted = List<TextFragment>.from(fragments);
    sorted.sort((a, b) {
      if ((a.y - b.y).abs() > 15) {
        return a.y.compareTo(b.y);
      }
      return a.x.compareTo(b.x);
    });

    final lines = <String>[];
    var currentLine = <String>[];
    int lastY = -1;
    int lastX = -1;

    for (final frag in sorted) {
      // New line if Y differs significantly
      if (lastY >= 0 && (frag.y - lastY).abs() > 15) {
        if (currentLine.isNotEmpty) {
          lines.add(currentLine.join(' '));
        }
        currentLine = [];
        lastX = -1;
      }

      // Also break line if X gap is too large (new column)
      if (lastX >= 0 && (frag.x - lastX) > 200) {
        if (currentLine.isNotEmpty) {
          lines.add(currentLine.join(' '));
        }
        currentLine = [];
      }

      currentLine.add(frag.text);
      lastY = frag.y;
      lastX = frag.x + frag.width;
    }

    if (currentLine.isNotEmpty) {
      lines.add(currentLine.join(' '));
    }

    return lines;
  }

  /// Generate detailed report
  static String generateAnalysisReport(OcrExtraction extraction) {
    final allFragments = <TextFragment>[];
    for (final page in extraction.pages) {
      allFragments.addAll(page.fragments);
    }

    final lines = groupFragmentsIntoLinesSync(allFragments);
    final moves = extractAllMoves(lines);
    final metadata = extractMetadata(lines);

    final buffer = StringBuffer();
    buffer.writeln('╔════════════════════════════════════════╗');
    buffer.writeln('║     PGN EXTRACTION ANALYSIS            ║');
    buffer.writeln('╚════════════════════════════════════════╝\n');

    buffer.writeln('Metadata Found:');
    buffer.writeln('  • White: ${metadata['white'] ?? '(not found)'}');
    buffer.writeln('  • Black: ${metadata['black'] ?? '(not found)'}');
    buffer.writeln('  • Date: ${metadata['date'] ?? '(not found)'}');
    buffer.writeln('  • Event: ${metadata['event'] ?? '(not found)'}');
    buffer.writeln();

    buffer.writeln('Lines Grouped (${lines.length} total):');
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final displayLine = line.length > 80
          ? '${line.substring(0, 80)}...'
          : line;
      buffer.writeln('  Line $i: "$displayLine"');
    }
    buffer.writeln();

    buffer.writeln('Moves Extracted:');
    buffer.writeln('  • Total moves: ${moves.length}');
    buffer.writeln('  • Move pairs: ${(moves.length / 2).ceil()}');
    buffer.writeln();

    if (moves.isNotEmpty) {
      buffer.writeln('All Moves:');
      for (int i = 0; i < moves.length; i += 2) {
        final moveNum = (i ~/ 2) + 1;
        buffer.write('  $moveNum. ${moves[i]}');
        if (i + 1 < moves.length) {
          buffer.write(' ${moves[i + 1]}');
        }
        buffer.writeln();
      }
    } else {
      buffer.writeln('  No moves found!');
      buffer.writeln('\nDEBUG: Checking raw text for patterns:');
      final text = lines.take(30).join(' ');
      buffer.writeln('  Text: "$text"');
    }

    return buffer.toString();
  }
}
