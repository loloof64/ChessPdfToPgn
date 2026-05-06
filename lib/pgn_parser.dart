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

  /// Extract all moves from lines
  /// Returns alternating white/black moves
  static List<String> extractAllMoves(List<String> lines) {
    final moves = <String>[];
    final text = lines.join(' ');
    
    // Match: number. move [comment] number. move [comment]
    // Be very permissive to catch chess notation
    final movePattern = RegExp(
      r'(\d+)\s*\.\s*'  // move number
      r'([a-hKQRBN0-9x@\-=+#!?]{2,10}?)'  // white move (permissive)
      r'(?:\s+\{[^}]*\})?'  // optional comment in braces
      r'(?:\s+([a-hKQRBN0-9x@\-=+#!?]{2,10}?))?'  // optional black move
      r'(?:\s+\{[^}]*\})?',  // optional comment
      multiLine: false,
    );

    for (final match in movePattern.allMatches(text)) {
      final whiteMove = match.group(2)?.trim() ?? '';
      final blackMove = match.group(3)?.trim();

      // Filter out garbage (like "20", "26" which are page numbers)
      if (whiteMove.isNotEmpty && _looksLikeMove(whiteMove)) {
        moves.add(whiteMove);
        
        if (blackMove != null && blackMove.isNotEmpty && _looksLikeMove(blackMove)) {
          moves.add(blackMove);
        }
      }
    }

    return moves;
  }

  /// Check if text looks like a valid chess move
  static bool _looksLikeMove(String text) {
    // Must have: piece letter (optional) + destination square + optional capture/promotion
    // Examples: e4, Nf3, exd5, f8=Q, O-O, O-O-O
    
    // Reject pure numbers (page numbers, ratings)
    if (RegExp(r'^\d+$').hasMatch(text)) return false;
    
    // Must contain at least one file letter (a-h) or O (castling)
    if (!text.contains(RegExp(r'[a-hO]', caseSensitive: false))) return false;
    
    // Must be reasonably short (max 10 chars)
    if (text.length > 10) return false;
    
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

    for (final frag in sorted) {
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
    for (int i = 0; i < lines.take(10).length; i++) {
      buffer.writeln('  Line $i: "${lines[i].substring(0, lines[i].length > 50 ? 50 : lines[i].length)}"${lines[i].length > 50 ? '...' : ''}');
    }
    if (lines.length > 10) {
      buffer.writeln('  ... and ${lines.length - 10} more lines');
    }
    buffer.writeln();

    buffer.writeln('Moves Extracted:');
    buffer.writeln('  • Total moves: ${moves.length}');
    buffer.writeln('  • Move pairs: ${(moves.length / 2).ceil()}');
    buffer.writeln();

    if (moves.isNotEmpty) {
      buffer.writeln('Sample Moves:');
      for (int i = 0; i < moves.take(10).length; i += 2) {
        final moveNum = (i ~/ 2) + 1;
        buffer.write('  $moveNum. ${moves[i]}');
        if (i + 1 < moves.length) {
          buffer.write(' ${moves[i + 1]}');
        }
        buffer.writeln();
      }

      if (moves.length > 10) {
        buffer.writeln('  ... and ${moves.length - 10} more moves');
      }
    } else {
      buffer.writeln('  No moves found!');
      buffer.writeln('\nDEBUG: Checking first few lines for move patterns:');
      final text = lines.take(20).join(' ');
      buffer.writeln('  Text: "${text.substring(0, text.length > 200 ? 200 : text.length)}"...');
    }

    return buffer.toString();
  }
}
