import 'dart:async';
import 'chess_models.dart';

/// Advanced PGN parser that reconstructs games from raw OCR fragments
/// Uses async/await to avoid blocking UI
class AdvancedPgnParser {
  
  /// Group fragments into logical lines based on Y position (async version)
  static Future<List<String>> groupFragmentsIntoLinesAsync(List<TextFragment> fragments) async {
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
      if (line.contains(RegExp(r'(?:White|Blanc)\s*[:=]', caseSensitive: false))) {
        final match = RegExp(r'(?:White|Blanc)\s*[:=]\s*([A-Za-z\s\-]+)', caseSensitive: false).firstMatch(line);
        if (match != null) {
          metadata['white'] = match.group(1)?.trim() ?? '';
        }
      }
      
      // Black player
      if (line.contains(RegExp(r'(?:Black|Noir)\s*[:=]', caseSensitive: false))) {
        final match = RegExp(r'(?:Black|Noir)\s*[:=]\s*([A-Za-z\s\-]+)', caseSensitive: false).firstMatch(line);
        if (match != null) {
          metadata['black'] = match.group(1)?.trim() ?? '';
        }
      }
      
      // Date
      if (line.contains(RegExp(r'Date|Année', caseSensitive: false))) {
        final match = RegExp(r'(\d{4}[.\-/]?\d{0,2}[.\-/]?\d{0,2})').firstMatch(line);
        if (match != null) {
          metadata['date'] = match.group(1) ?? '';
        }
      }
      
      // Event
      if (line.contains(RegExp(r'Event|Événement', caseSensitive: false))) {
        final match = RegExp(r'(?:Event|Événement)\s*[:=]\s*([^\n,]+)', caseSensitive: false).firstMatch(line);
        if (match != null) {
          metadata['event'] = match.group(1)?.trim() ?? '';
        }
      }
    }
    
    return metadata;
  }

  /// Extract all moves from lines (improved version)
  static List<String> extractAllMoves(List<String> lines) {
    final moves = <String>[];
    final text = lines.join(' ');
    
    // More aggressive move pattern that catches variations
    // Pattern: optional number + optional dots + move notation
    // Move notation: can be quite flexible
    final movePattern = RegExp(
      r'(?:^|\s)'  // Start or whitespace
      r'(?:\d+\.+)?'  // Optional move number (1., 2., etc)
      r'\s*'
      r'([a-hKQRBN]?[a-h]?[1-8]?[x@]?[a-h][1-8](?:=[QRBN])?[+#!?]*)'  // White move
      r'(?:\s+([a-hKQRBN]?[a-h]?[1-8]?[x@]?[a-h][1-8](?:=[QRBN])?[+#!?]*))?'  // Black move
      ,
      multiLine: false,
    );

    for (final match in movePattern.allMatches(text)) {
      final whiteMove = match.group(1)?.trim() ?? '';
      final blackMove = match.group(2)?.trim();

      // Validate moves more carefully
      if (whiteMove.isNotEmpty && _looksLikeMove(whiteMove)) {
        moves.add(whiteMove);
        
        if (blackMove != null && blackMove.isNotEmpty && _looksLikeMove(blackMove)) {
          moves.add(blackMove);
        }
      }
    }

    // If we found very few moves, try even more permissive pattern
    if (moves.length < 10) {
      moves.addAll(_extractMovesAggressive(text));
    }

    return moves;
  }

  /// Ultra-permissive move extraction as fallback
  static List<String> _extractMovesAggressive(String text) {
    final moves = <String>[];
    
    // Look for patterns like: e4, Nf3, O-O, exd5, f8=Q, etc.
    // Much simpler pattern
    final simplePattern = RegExp(
      r'[a-hKQRBN][a-h]?[1-8]?[x@]?[a-h][1-8](?:=[QRBN])?[+#!?]*',
    );

    for (final match in simplePattern.allMatches(text)) {
      final move = match.group(0)!;
      
      // Filter out junk
      if (move.length >= 2 && move.length <= 8 && _looksLikeMove(move)) {
        moves.add(move);
      }
    }

    return moves;
  }

  /// Check if text looks like a valid chess move
  static bool _looksLikeMove(String text) {
    // Reject pure numbers (page numbers, ratings)
    if (RegExp(r'^\d+$').hasMatch(text)) return false;
    
    // Reject very short or very long
    if (text.length < 2 || text.length > 8) return false;
    
    // Must have at least one valid file letter (a-h) or O (castling)
    if (!text.contains(RegExp(r'[a-hO]', caseSensitive: false))) return false;
    
    // Reject pure text (no numbers)
    if (!text.contains(RegExp(r'[0-9]'))) return false;
    
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

  /// Generate PGN from extraction (async version)
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

      // Group into lines (sync, but fast enough)
      final lines = groupFragmentsIntoLinesSync(allFragments);

      // Extract metadata (if not provided)
      final foundMetadata = extractMetadata(lines);
      white ??= foundMetadata['white'] ?? '?';
      black ??= foundMetadata['black'] ?? '?';
      date ??= foundMetadata['date'] ?? '????.??.??';
      event ??= foundMetadata['event'] ?? 'Chess Game';
      site ??= '?';

      // Extract moves and comments
      final moves = extractAllMoves(lines);
      final comments = extractComments(lines);

      // Build PGN
      final buffer = StringBuffer();
      buffer.writeln('[Event "$event"]');
      buffer.writeln('[Site "$site"]');
      buffer.writeln('[Date "$date"]');
      buffer.writeln('[White "$white"]');
      buffer.writeln('[Black "$black"]');
      buffer.writeln('[Result "$result"]');
      
      if (comments.isNotEmpty) {
        buffer.writeln('[Comment "${comments.join('; ')}"]');
      }
      
      buffer.writeln();

      // Write moves
      for (int i = 0; i < moves.length; i += 2) {
        final moveNum = (i ~/ 2) + 1;
        buffer.write('$moveNum. ${moves[i]} ');

        if (i + 1 < moves.length) {
          buffer.write('${moves[i + 1]} ');
        }
      }

      buffer.write(result);

      return buffer.toString();
    });
  }

  /// Synchronous version of grouping (for internal use)
  static List<String> groupFragmentsIntoLinesSync(List<TextFragment> fragments) {
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
