import 'package:flutter/foundation.dart';
import '../../core/models/ocr_line.dart';

/// Intelligent PGN parser that analyzes spatial layout and extracts chess moves
/// while preserving book comments and ignoring position diagrams
///
/// CRITICAL FIX: Groups individual OCR words into coherent TEXT LINES first,
/// because extractWords() returns individual words, not pre-grouped lines.
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

  /// Pattern to identify position diagram indicators
  static final RegExp _diagramPattern = RegExp(
    r'\b(?:diagram|position|fig\.?|figure|[♔♕♖♗♘♙♚♛♜♝♞♟]|[KQRBNkqrbn]\d{1,2})\b',
    caseSensitive: false,
  );

  /// PUBLIC ENTRY POINT: Extract chess moves and comments from OCR words
  ///
  /// INPUT: List of individual OCR words with coordinates
  /// OUTPUT: PGNExtraction with properly paired moves and separated comments
  PGNExtraction extractMovesAndComments(List<OCRLine> ocrWords) {
    // STEP 1: Group individual words into coherent text lines
    final textLines = _groupWordsIntoLines(ocrWords);

    debugPrint(
      '[SmartPGN] Grouped ${ocrWords.length} words into ${textLines.length} lines',
    );

    // STEP 2: Analyze spatial layout of text lines
    final groups = _analyzeLayout(textLines);

    // STEP 3: Extract moves and comments from groups
    final moves = <String>[];
    final comments = <String>[];

    for (final group in groups) {
      // Check if this is a diagram line (ignore it)
      if (_isLikelyDiagram(group)) {
        debugPrint(
          '[SmartPGN] Skipped diagram line: "${group.leftLines.map((l) => l.text).join(" ")}"',
        );
        continue;
      }

      // Extract chess notation from left side (white moves)
      final leftText = group.leftLines.map((l) => l.text).join(' ');
      if (leftText.isNotEmpty) {
        _extractMovesFromText(leftText, moves, comments);
      }

      // Extract chess notation from right side (black moves)
      final rightText = group.rightLines.map((l) => l.text).join(' ');
      if (rightText.isNotEmpty) {
        _extractMovesFromText(rightText, moves, comments);
      }

      // If only one column (likely a comment or narration), check for comments
      if (group.leftLines.isEmpty || group.rightLines.isEmpty) {
        final fullText = group.allLines.map((l) => l.text).join(' ');
        if (!_looksLikeMoves(fullText) && fullText.isNotEmpty) {
          // This is likely a comment
          comments.add(fullText);
          debugPrint('[SmartPGN] Added comment: "$fullText"');
        }
      }
    }

    debugPrint(
      '[SmartPGN] Extracted ${moves.length} moves and ${comments.length} comments',
    );

    return PGNExtraction(moves: moves, comments: comments);
  }

  // =========================================================================
  // STEP 1: GROUP WORDS INTO LINES
  // =========================================================================

  /// Group individual OCR words into coherent lines based on spatial proximity
  /// This is CRITICAL because extractWords() returns individual words, not lines
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
    // Words are already sorted left-to-right
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
  // STEP 2: ANALYZE LAYOUT
  // =========================================================================

  /// Analyze spatial layout of text lines and group into semantic units
  List<LineGroup> _analyzeLayout(List<TextLine> textLines) {
    if (textLines.isEmpty) return [];

    final groups = <LineGroup>[];
    final currentGroup = <TextLine>[];
    int? currentRowY;

    for (final line in textLines) {
      // Group lines that are on the same horizontal level
      if (currentRowY != null &&
          (line.y - currentRowY).abs() > _lineHeightTolerance) {
        // New row detected
        if (currentGroup.isNotEmpty) {
          groups.add(_createLineGroup(currentGroup));
          currentGroup.clear();
        }
        currentRowY = line.y;
      } else {
        currentRowY ??= line.y;
      }

      currentGroup.add(line);
    }

    // Add the last group
    if (currentGroup.isNotEmpty) {
      groups.add(_createLineGroup(currentGroup));
    }

    return groups;
  }

  /// Create a line group from a set of lines on the same horizontal level
  LineGroup _createLineGroup(List<TextLine> lines) {
    // Calculate center X
    final centerX =
        lines.fold<int>(0, (sum, l) => sum + l.centerX) ~/ lines.length;

    final leftLines = <TextLine>[];
    final rightLines = <TextLine>[];

    for (final line in lines) {
      if (line.centerX < centerX) {
        leftLines.add(line);
      } else {
        rightLines.add(line);
      }
    }

    return LineGroup(
      allLines: lines,
      leftLines: leftLines,
      rightLines: rightLines,
    );
  }

  // =========================================================================
  // STEP 3: EXTRACT MOVES AND COMMENTS
  // =========================================================================

  /// Extract individual moves from text
  void _extractMovesFromText(
    String text,
    List<String> moves,
    List<String> comments,
  ) {
    // Find all chess notation patterns
    final matches = _chessNotationPattern.allMatches(text);

    if (matches.isEmpty) {
      // No moves found, might be a comment
      if (text.isNotEmpty && !_looksLikePageNumber(text)) {
        comments.add(text);
      }
      return;
    }

    int lastEnd = 0;
    for (final match in matches) {
      // Extract any comment text between the last move and this move
      final textBefore = text.substring(lastEnd, match.start).trim();
      if (textBefore.isNotEmpty && !_looksLikePageNumber(textBefore)) {
        comments.add(textBefore);
      }

      moves.add(match.group(0)!);
      lastEnd = match.end;
    }

    // Extract any trailing comment
    if (lastEnd < text.length) {
      final trailing = text.substring(lastEnd).trim();
      if (trailing.isNotEmpty && !_looksLikePageNumber(trailing)) {
        comments.add(trailing);
      }
    }
  }

  /// Check if a line is likely a position diagram
  bool _isLikelyDiagram(LineGroup group) {
    final fullText = group.allLines.map((l) => l.text).join(' ');

    // Check for diagram indicators
    if (_diagramPattern.hasMatch(fullText)) {
      return true;
    }

    // Check for coordinate-like patterns (a1, b2, etc.)
    if (RegExp(r'\b[a-h][1-8]\b').hasMatch(fullText)) {
      return true;
    }

    return false;
  }

  /// Check if text looks like it contains chess moves
  bool _looksLikeMoves(String text) {
    return _chessNotationPattern.hasMatch(text);
  }

  /// Check if text is likely a page number or header/footer
  bool _looksLikePageNumber(String text) {
    final trimmed = text.trim();
    if (trimmed.length > 20) return false; // Too long to be a page number

    // Check for common page indicators
    return RegExp(
      r'^\d+$|^page\s+\d+|^\d+\s*\-\s*\d+$',
      caseSensitive: false,
    ).hasMatch(trimmed);
  }
}

// ============================================================================
// DATA MODELS
// ============================================================================

/// Represents a single line of text (grouped from multiple OCR words)
class TextLine {
  final String text;
  final int x; // Left position in pixels
  final int y; // Top position in pixels
  final int width;
  final int height;
  final double confidence;
  final List<OCRLine> words; // Original OCR words that compose this line

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
  String toString() =>
      'TextLine(text: "$text", x: $x, y: $y, conf: $confidence)';
}

/// Represents a horizontal line group (moves on the same row)
class LineGroup {
  final List<TextLine> allLines;
  final List<TextLine> leftLines; // Usually white moves
  final List<TextLine> rightLines; // Usually black moves

  LineGroup({
    required this.allLines,
    required this.leftLines,
    required this.rightLines,
  });

  @override
  String toString() =>
      'LineGroup(left: ${leftLines.length}, right: ${rightLines.length})';
}

/// Result of PGN extraction
class PGNExtraction {
  final List<String> moves; // Raw move strings (e.g., "1. d4", "Nf3")
  final List<String> comments; // Book comments to include

  PGNExtraction({required this.moves, required this.comments});

  @override
  String toString() =>
      'PGNExtraction(moves: ${moves.length}, comments: ${comments.length})';
}
