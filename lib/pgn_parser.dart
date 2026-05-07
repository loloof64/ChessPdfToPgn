import 'dart:async';
import 'chess_models.dart';
import 'move_validator.dart';

/// Advanced PGN parser for v2.0 (TextLine based)
class AdvancedPgnParser {
  
  /// Group lines into logical sections based on Y position
  static Future<List<String>> groupLinesAsync(List<TextLine> lines) async {
    return Future(() {
      if (lines.isEmpty) return [];
      
      final sorted = List<TextLine>.from(lines);
      sorted.sort((a, b) {
        if ((a.y - b.y).abs() > 15) {
          return a.y.compareTo(b.y);
        }
        return a.x.compareTo(b.x);
      });

      final result = <String>[];
      var currentGroup = <String>[];
      int lastY = -1;

      for (final line in sorted) {
        if (lastY >= 0 && (line.y - lastY).abs() > 15) {
          if (currentGroup.isNotEmpty) {
            result.add(currentGroup.join(' '));
          }
          currentGroup = [];
        }
        currentGroup.add(line.text);
        lastY = line.y;
      }

      if (currentGroup.isNotEmpty) {
        result.add(currentGroup.join(' '));
      }

      return result;
    });
  }

  /// Extract metadata from lines
  static Map<String, String> extractMetadata(List<String> lines) {
    final metadata = <String, String>{};
    
    for (final line in lines.take(20)) {
      if (line.contains(RegExp(r'(?:White|Blanc)\s*[:=]', caseSensitive: false))) {
        final match = RegExp(r'(?:White|Blanc)\s*[:=]\s*([A-Za-z\s\-]+)', caseSensitive: false).firstMatch(line);
        if (match != null) {
          metadata['white'] = match.group(1)?.trim() ?? '';
        }
      }
      
      if (line.contains(RegExp(r'(?:Black|Noir)\s*[:=]', caseSensitive: false))) {
        final match = RegExp(r'(?:Black|Noir)\s*[:=]\s*([A-Za-z\s\-]+)', caseSensitive: false).firstMatch(line);
        if (match != null) {
          metadata['black'] = match.group(1)?.trim() ?? '';
        }
      }
      
      if (line.contains(RegExp(r'Date|Année', caseSensitive: false))) {
        final match = RegExp(r'(\d{4}[.\-/]?\d{0,2}[.\-/]?\d{0,2})').firstMatch(line);
        if (match != null) {
          metadata['date'] = match.group(1) ?? '';
        }
      }
      
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
  static List<String> extractAllMoves(List<String> lines) {
    final moves = <String>[];
    final text = lines.join(' ');
    
    // Find move numbers (1., 2., etc.) as anchors
    final moveNumberPattern = RegExp(r'\b(\d+)\.\s+');
    
    final matches = moveNumberPattern.allMatches(text);
    
    for (final match in matches) {
      final moveNum = int.parse(match.group(1)!);
      final startPos = match.end;
      
      // Find next move number
      final nextMatch = matches.firstWhere(
        (m) => int.parse(m.group(1)!) == moveNum + 1,
        orElse: () => match,
      );
      
      final moveText = nextMatch != match 
          ? text.substring(startPos, nextMatch.start)
          : text.substring(startPos);
      
      // Extract moves from this chunk
      final moveMatches = RegExp(
        r'([a-hKQRBN]?[a-h][1-8](?:=[QRBN])?[+#!?]*)',
      ).allMatches(moveText);
      
      final movesInChunk = moveMatches
          .map((m) => m.group(1)!)
          .where((m) => _looksLikeMove(m))
          .take(2)
          .toList();
      
      moves.addAll(movesInChunk);
    }

    return moves;
  }

  /// Check if text looks like a valid chess move
  static bool _looksLikeMove(String text) {
    if (text.length < 2 || text.length > 8) return false;
    if (RegExp(r'^\d+$').hasMatch(text)) return false;
    if (!text.contains(RegExp(r'[a-hO]', caseSensitive: false))) return false;
    if (!text.contains(RegExp(r'[1-8]'))) return false;
    return true;
  }

  /// Extract comments
  static List<String> extractComments(List<String> lines) {
    final comments = <String>[];
    final text = lines.join(' ');
    
    final bracePattern = RegExp(r'\{([^}]+)\}');
    for (final match in bracePattern.allMatches(text)) {
      final comment = match.group(1)?.trim();
      if (comment != null && comment.isNotEmpty) {
        comments.add(comment);
      }
    }
    
    return comments;
  }

  /// Generate PGN with move validation (async)
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
      // Get all lines from all pages
      final allLines = <TextLine>[];
      for (final page in extraction.pages) {
        allLines.addAll(page.lines);
      }

      // Group into text sections
      final textSections = _groupLinesSync(allLines);

      // Extract metadata
      final foundMetadata = extractMetadata(textSections);
      white ??= foundMetadata['white'] ?? '?';
      black ??= foundMetadata['black'] ?? '?';
      date ??= foundMetadata['date'] ?? '????.??.??';
      event ??= foundMetadata['event'] ?? 'Chess Game';
      site ??= '?';

      // Extract and validate moves
      final rawMoves = extractAllMoves(textSections);
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

  /// Group lines (sync version)
  static List<String> _groupLinesSync(List<TextLine> lines) {
    if (lines.isEmpty) return [];
    
    final sorted = List<TextLine>.from(lines);
    sorted.sort((a, b) {
      if ((a.y - b.y).abs() > 15) {
        return a.y.compareTo(b.y);
      }
      return a.x.compareTo(b.x);
    });

    final result = <String>[];
    var currentGroup = <String>[];
    int lastY = -1;

    for (final line in sorted) {
      if (lastY >= 0 && (line.y - lastY).abs() > 15) {
        if (currentGroup.isNotEmpty) {
          result.add(currentGroup.join(' '));
        }
        currentGroup = [];
      }
      currentGroup.add(line.text);
      lastY = line.y;
    }

    if (currentGroup.isNotEmpty) {
      result.add(currentGroup.join(' '));
    }

    return result;
  }

  /// Generate detailed analysis report
  static String generateAnalysisReport(OcrExtraction extraction) {
    final allLines = <TextLine>[];
    for (final page in extraction.pages) {
      allLines.addAll(page.lines);
    }

    final textSections = _groupLinesSync(allLines);
    final moves = extractAllMoves(textSections);
    final metadata = extractMetadata(textSections);

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

    buffer.writeln('Text Sections (${textSections.length} total):');
    for (int i = 0; i < textSections.length; i++) {
      final section = textSections[i];
      final displaySection = section.length > 80 
          ? '${section.substring(0, 80)}...'
          : section;
      buffer.writeln('  Section $i: "$displaySection"');
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
      buffer.writeln('  No moves found');
    }

    return buffer.toString();
  }
}
