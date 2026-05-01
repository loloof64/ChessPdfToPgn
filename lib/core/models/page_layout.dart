import 'package:dartcv4/dartcv.dart' as cv;

// ---------------------------------------------------------------------------
// Block types
// ---------------------------------------------------------------------------

/// Base class for all detected blocks on a page.
sealed class PageBlock {
  /// Bounding box in the original (pre-split) page coordinate space.
  final cv.Rect bounds;

  const PageBlock({required this.bounds});
}

/// A block of regular body text — passed to Tesseract for OCR.
final class TextBlock extends PageBlock {
  const TextBlock({required super.bounds});
}

/// A bold and/or centered block — candidate for game header (title + subtitle).
final class HeaderBlock extends PageBlock {
  /// True if the block is visually centered within its column.
  final bool isCentered;

  /// True if the average stroke width suggests bold text.
  final bool isBold;

  /// Raw OCR text of the header, filled after OCR pass.
  final String? text;

  const HeaderBlock({
    required super.bounds,
    required this.isCentered,
    required this.isBold,
    this.text,
  });

  /// A block qualifies as a game header if it is centered AND bold.
  bool get isGameHeader => isCentered && isBold;
}

/// A chess diagram block.
final class DiagramBlock extends PageBlock {
  /// Path to the extracted and warped square images, filled after OpenCV pass.
  /// Null until [OpenCvService.extractBoardSquares] has been called.
  final String? preprocessedPath;

  /// FEN string reconstructed from the diagram, filled after classification.
  /// Null until the board classifier has run.
  final String? fen;

  const DiagramBlock({required super.bounds, this.preprocessedPath, this.fen});
}

// ---------------------------------------------------------------------------
// Column
// ---------------------------------------------------------------------------

/// A single column of content within a page.
/// Contains an ordered list of blocks from top to bottom.
class PageColumn {
  /// Bounding box of the column within the page.
  final cv.Rect bounds;

  /// Ordered blocks within the column (top → bottom).
  final List<PageBlock> blocks;

  const PageColumn({required this.bounds, required this.blocks});

  /// Returns only text blocks.
  List<TextBlock> get textBlocks => blocks.whereType<TextBlock>().toList();

  /// Returns only diagram blocks.
  List<DiagramBlock> get diagramBlocks =>
      blocks.whereType<DiagramBlock>().toList();

  /// Returns only header blocks.
  List<HeaderBlock> get headerBlocks =>
      blocks.whereType<HeaderBlock>().toList();

  /// Returns the first diagram block, if any.
  DiagramBlock? get firstDiagram =>
      blocks.whereType<DiagramBlock>().firstOrNull;
}

// ---------------------------------------------------------------------------
// Page layout
// ---------------------------------------------------------------------------

enum ColumnLayout { single, double }

/// Fully analyzed page, ready for OCR and game extraction.
class AnalyzedPage {
  /// Original image path (before any preprocessing).
  final String imagePath;

  /// Detected column layout.
  final ColumnLayout layout;

  /// Columns, ordered left to right.
  /// Always contains exactly 1 entry for [ColumnLayout.single],
  /// exactly 2 entries for [ColumnLayout.double].
  final List<PageColumn> columns;

  /// True if the page looks like an intro, foreword, or appendix —
  /// i.e. contains little or no chess notation patterns.
  /// These pages are exported as plain text, not parsed as PGN.
  final bool isIntroPage;

  const AnalyzedPage({
    required this.imagePath,
    required this.layout,
    required this.columns,
    required this.isIntroPage,
  });

  /// Convenience: all blocks across all columns, left-to-right, top-to-bottom.
  List<PageBlock> get allBlocks => columns.expand((col) => col.blocks).toList();

  /// Convenience: all text blocks across all columns.
  List<TextBlock> get allTextBlocks =>
      allBlocks.whereType<TextBlock>().toList();

  /// Convenience: first diagram found across all columns.
  DiagramBlock? get firstDiagram =>
      allBlocks.whereType<DiagramBlock>().firstOrNull;
}

// ---------------------------------------------------------------------------
// Game boundary
// ---------------------------------------------------------------------------

/// Marks the start of a new chess game within a page analysis result.
/// Produced by [PageAnalyzer] when a game header + first move or diagram
/// is detected.
class GameBoundary {
  /// The header block that triggered the boundary detection.
  final HeaderBlock header;

  /// Optional subtitle block immediately following the header.
  final HeaderBlock? subtitle;

  /// The first diagram of this game, if present (defines starting FEN).
  /// Null if the game starts from the standard position.
  final DiagramBlock? startDiagram;

  /// Index of the column where this game starts.
  final int columnIndex;

  const GameBoundary({
    required this.header,
    this.subtitle,
    this.startDiagram,
    required this.columnIndex,
  });

  bool get hasCustomStartPosition => startDiagram?.fen != null;
}
