import 'package:flutter/foundation.dart';
import '../../core/models/ocr_line.dart';

/// Intelligent PGN parser that analyzes spatial layout and extracts chess moves
/// while preserving book comments and ignoring position diagrams
///
/// v3: Balanced approach with column detection but less aggressive filtering
class SmartPGNParser {
  /// Tolerance for grouping words into same line (pixels)
  static const int _lineHeightTolerance = 15;

  /// Regular expression patterns for chess notation recognition
  static final RegExp _chessNotationPattern = RegExp(
    r'\b'
    r'(?:\d+\.{1,3})?' // Move number: 1., 1..., 1...
    r'(?:[KQRBN]?' // Piece type (optional)
    r'[a-h]?' // File (optional, for disambiguation)
    r'[1-8]?' // Rank (optional, for disambiguation)
    r'x?' // Capture (optional)
    r'[a-h][1-8]' // Destination square (required)
    r'(?:=[QRBN])?' // Promotion (optional)
    r'[+#]?' // Check or checkmate (optional)
    r'|O-O(?:-O)?' // Castling (0-0 or 0-0-0)
    r')\b',
    multiLine: true,
  );

  /// PUBLIC ENTRY POINT: Extract chess moves and comments from OCR words
  PGNExtraction extractMovesAndComments(List<OCRLine> ocrWords) {
    // STEP 1: Group individual words into coherent text lines
    final textLines = _groupWordsIntoLines(ocrWords);

    debugPrint(
      '[SmartPGN] Grouped ${ocrWords.length} words into ${textLines.length} lines',
    );

    // STEP 2: Process lines to extract moves and comments
    final moves = <String>[];
    final comments = <String>[];

    _extractFromLines(textLines, moves, comments);

    debugPrint(
      '[SmartPGN] Extracted ${moves.length} moves and ${comments.length} comments',
    );

    return PGNExtraction(moves: moves, comments: comments);
  }

  // =========================================================================
  // STEP 1: GROUP WORDS INTO LINES
  // =========================================================================

  /// Group individual OCR words into coherent lines based on spatial proximity
  List<TextLine> _groupWordsIntoLines(List<OCRLine> ocrWords) {
    if (ocrWords.isEmpty) return [];

    // Sort by Y (top to bottom), then X (left to right)
    final sorted = List<OCRLine>.from(ocrWords)
      ..sort((a, b) {
        final yDiff = a.y.compareTo(b.y);
        if (yDiff != 0) return yDiff;
        return a.x.compareTo(b.x);
      });

    final textLines = <TextLine>[];
    var currentLineWords = <OCRLine>[];
    int? currentLineY;

    for (final word in sorted) {
      // Check if word is on same horizontal line as current line
      if (currentLineY != null &&
          (word.y - currentLineY).abs() > _lineHeightTolerance) {
        // Start a new line
        if (currentLineWords.isNotEmpty) {
          textLines.add(_createTextLine(currentLineWords));
          currentLineWords.clear();
        }
        currentLineY = word.y;
      } else {
        currentLineY ??= word.y;
      }

      currentLineWords.add(word);
    }

    // Add the last line
    if (currentLineWords.isNotEmpty) {
      textLines.add(_createTextLine(currentLineWords));
    }

    return textLines;
  }

  /// Create a TextLine from grouped OCR words
  TextLine _createTextLine(List<OCRLine> words) {
    final text = words.map((w) => w.text).join(' ');
    final minX = words.first.x;
    final maxX = words.last.right;
    final minY = words.first.y;
    final avgConfidence =
        words.fold<double>(0, (sum, w) => sum + w.confidence) / words.length;

    return TextLine(
      text: text,
      x: minX,
      y: minY,
      width: maxX - minX,
      height: words.first.height,
      confidence: avgConfidence,
      words: words,
    );
  }

  // =========================================================================
  // STEP 2: EXTRACT MOVES AND COMMENTS
  // =========================================================================

  /// Extract moves and comments from text lines
  void _extractFromLines(
    List<TextLine> textLines,
    List<String> moves,
    List<String> comments,
  ) {
    // Group lines by approximate row (same Y level)
    final rowGroups = _groupLinesByRow(textLines);

    for (final rowLines in rowGroups) {
      if (rowLines.isEmpty) continue;

      // Try to split into left/right columns
      final (leftLines, rightLines) = _splitIntoColumns(rowLines);

      // Extract moves from left column
      if (leftLines.isNotEmpty) {
        final leftText = leftLines.map((l) => l.text).join(' ');
        _extractMovesFromText(leftText, moves, comments);
      }

      // Extract moves from right column (if exists and different from left)
      if (rightLines.isNotEmpty && rightLines != leftLines) {
        final rightText = rightLines.map((l) => l.text).join(' ');
        _extractMovesFromText(rightText, moves, comments);
      }

      // If only one column and no moves found, might be a comment
      if ((leftLines.isEmpty || rightLines.isEmpty) &&
          leftLines.isNotEmpty &&
          rightLines.isEmpty) {
        final fullText = leftLines.map((l) => l.text).join(' ');
        if (!_looksLikeMoves(fullText) && fullText.isNotEmpty) {
          comments.add(fullText);
        }
      }
    }
  }

  /// Group lines by approximate vertical position
  List<List<TextLine>> _groupLinesByRow(List<TextLine> textLines) {
    if (textLines.isEmpty) return [];

    final rows = <List<TextLine>>[];
    var currentRow = <TextLine>[textLines[0]];
    int currentRowY = textLines[0].y;

    for (int i = 1; i < textLines.length; i++) {
      final line = textLines[i];

      if ((line.y - currentRowY).abs() <= _lineHeightTolerance) {
        currentRow.add(line);
      } else {
        rows.add(currentRow);
        currentRow = [line];
        currentRowY = line.y;
      }
    }

    if (currentRow.isNotEmpty) {
      rows.add(currentRow);
    }

    return rows;
  }

  /// Split a row into left and right columns (or return all as left if single)
  (List<TextLine>, List<TextLine>) _splitIntoColumns(List<TextLine> rowLines) {
    if (rowLines.length == 1) {
      return (rowLines, []);
    }

    // Calculate center X
    final centerX =
        rowLines.fold<int>(0, (sum, l) => sum + l.centerX) ~/ rowLines.length;

    final leftLines = <TextLine>[];
    final rightLines = <TextLine>[];

    for (final line in rowLines) {
      if (line.centerX < centerX) {
        leftLines.add(line);
      } else {
        rightLines.add(line);
      }
    }

    return (leftLines, rightLines);
  }

  /// Extract moves from text, collecting any non-move text as comments
  void _extractMovesFromText(
    String text,
    List<String> moves,
    List<String> comments,
  ) {
    final matches = _chessNotationPattern.allMatches(text);

    if (matches.isEmpty) {
      // No moves found — might be a comment
      if (text.isNotEmpty && !_looksLikePageNumber(text)) {
        comments.add(text);
      }
      return;
    }

    int lastEnd = 0;
    for (final match in matches) {
      // Extract text before move as potential comment
      final textBefore = text.substring(lastEnd, match.start).trim();
      if (textBefore.isNotEmpty && !_looksLikePageNumber(textBefore)) {
        comments.add(textBefore);
      }

      moves.add(match.group(0)!);
      lastEnd = match.end;
    }

    // Extract trailing text
    if (lastEnd < text.length) {
      final trailing = text.substring(lastEnd).trim();
      if (trailing.isNotEmpty && !_looksLikePageNumber(trailing)) {
        comments.add(trailing);
      }
    }
  }

  /// Check if text looks like it contains chess moves
  bool _looksLikeMoves(String text) {
    return _chessNotationPattern.hasMatch(text);
  }

  /// Check if text is likely a page number
  bool _looksLikePageNumber(String text) {
    final trimmed = text.trim();
    if (trimmed.length > 10) return false;

    return RegExp(r'^\d+$|^page\s+\d+', caseSensitive: false).hasMatch(trimmed);
  }
}

// ============================================================================
// DATA MODELS
// ============================================================================

/// Represents a single line of text (grouped from multiple OCR words)
class TextLine {
  final String text;
  final int x;
  final int y;
  final int width;
  final int height;
  final double confidence;
  final List<OCRLine> words;

  const TextLine({
    required this.text,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.confidence,
    required this.words,
  });

  /// Center X coordinate
  int get centerX => x + (width ~/ 2);

  /// Center Y coordinate
  int get centerY => y + (height ~/ 2);

  /// Right X coordinate
  int get right => x + width;

  @override
  String toString() => 'TextLine(text: "$text", x: $x, y: $y)';
}

/// Result of PGN extraction
class PGNExtraction {
  final List<String> moves;
  final List<String> comments;

  PGNExtraction({required this.moves, required this.comments});

  @override
  String toString() =>
      'PGNExtraction(moves: ${moves.length}, comments: ${comments.length})';
}
