import 'package:dartcv4/dartcv.dart' as cv;
import '../models/page_layout.dart';
import 'opencv_service.dart';

/// Analyzes a page image and returns a fully segmented [AnalyzedPage].
///
/// Pipeline:
///   1. Detect column layout (single vs double) via vertical projection
///   2. For each column: detect blocks (text / header / diagram)
///   3. Classify each block (centered, bold, chess diagram)
///   4. Detect intro/appendix pages
///   5. Detect game boundaries (header + first move or diagram)
class PageAnalyzer {
  // ignore: unused_field
  final OpenCvService _opencv;

  /// Minimum vertical gap (px) between two blocks in the same column.
  static const int _blockGapThreshold = 12;

  /// Minimum ratio of white pixels in the vertical projection valley
  /// to consider a page as two-column layout.
  static const double _valleyWhiteRatio = 0.85;

  /// Column center tolerance: left_margin ≈ right_margin within this ratio.
  static const double _centerTolerance = 0.10;

  const PageAnalyzer(this._opencv);

  // ---------------------------------------------------------------------------
  // Public entry point
  // ---------------------------------------------------------------------------

  /// Analyzes [imagePath] and returns the segmented [AnalyzedPage].
  Future<AnalyzedPage> analyze(String imagePath) async {
    final src = await cv.imreadAsync(imagePath, flags: cv.IMREAD_COLOR);
    _assertNotEmpty(src, imagePath);

    final gray = await cv.cvtColorAsync(src, cv.COLOR_BGR2GRAY);
    final binary = await _binarize(gray);

    // Step 1 — Detect column layout
    final layout = await _detectColumnLayout(binary);

    // Step 2 — Split into column regions
    final columnRects = await _splitColumnRects(binary, layout);

    // Step 3 — Analyze each column
    final columns = <PageColumn>[];
    for (final rect in columnRects) {
      final colRegion = binary.region(rect);
      final blocks = await _detectBlocks(colRegion, rect, binary.cols);
      columns.add(PageColumn(bounds: rect, blocks: blocks));
      colRegion.dispose();
    }

    // Step 4 — Detect intro/appendix pages
    final isIntro = _isIntroPage(columns);

    src.dispose();
    gray.dispose();
    binary.dispose();

    return AnalyzedPage(
      imagePath: imagePath,
      layout: layout,
      columns: columns,
      isIntroPage: isIntro,
    );
  }

  /// Detects game boundaries within an already-analyzed page.
  /// Call this after OCR has populated [HeaderBlock.text].
  List<GameBoundary> detectGameBoundaries(AnalyzedPage page) {
    final boundaries = <GameBoundary>[];

    for (var colIdx = 0; colIdx < page.columns.length; colIdx++) {
      final column = page.columns[colIdx];
      final blocks = column.blocks;

      for (var i = 0; i < blocks.length; i++) {
        final block = blocks[i];

        // Must be a bold + centered header block
        if (block is! HeaderBlock || !block.isGameHeader) continue;

        // Look ahead for optional subtitle (centered, non-bold)
        HeaderBlock? subtitle;
        var nextIdx = i + 1;
        if (nextIdx < blocks.length &&
            blocks[nextIdx] is HeaderBlock &&
            (blocks[nextIdx] as HeaderBlock).isCentered &&
            !(blocks[nextIdx] as HeaderBlock).isBold) {
          subtitle = blocks[nextIdx] as HeaderBlock;
          nextIdx++;
        }

        // Look ahead for first move "1." or diagram
        DiagramBlock? startDiagram;
        if (nextIdx < blocks.length) {
          final candidate = blocks[nextIdx];
          if (candidate is DiagramBlock) {
            startDiagram = candidate;
          }
          // TextBlock starting with "1." is also valid —
          // detected at PGN parsing stage, no action needed here
        }

        boundaries.add(
          GameBoundary(
            header: block,
            subtitle: subtitle,
            startDiagram: startDiagram,
            columnIndex: colIdx,
          ),
        );
      }
    }

    return boundaries;
  }

  // ---------------------------------------------------------------------------
  // Step 1 — Column layout detection
  // ---------------------------------------------------------------------------

  /// Detects whether the page has a single or double column layout.
  ///
  /// Strategy: compute the vertical projection (sum of black pixels per column)
  /// then look for a sustained valley of white pixels in the horizontal center.
  Future<ColumnLayout> _detectColumnLayout(cv.Mat binary) async {
    // Try Case A first — white space valley
    if (await _detectWhiteValley(binary)) return ColumnLayout.double;

    // Try Case B — vertical line separator
    if (await _detectVerticalLine(binary)) return ColumnLayout.double;

    return ColumnLayout.single;
  }

  /// Detects a double column layout via a white space valley in the center.
  /// Returns true if a sustained valley of white pixels is found.
  Future<bool> _detectWhiteValley(cv.Mat binary) async {
    final width = binary.cols;
    final height = binary.rows;

    final centerStart = width ~/ 3;
    final centerEnd = 2 * width ~/ 3;

    // Compute vertical projection: for each x, count black pixels
    final projection = List<int>.filled(width, 0);
    for (var x = centerStart; x < centerEnd; x++) {
      var blackCount = 0;
      for (var y = 0; y < height; y++) {
        if (binary.at<int>(y, x) == 0) blackCount++;
      }
      projection[x] = blackCount;
    }

    final valleyZone = projection.sublist(centerStart, centerEnd);
    final maxBlack = valleyZone.reduce((a, b) => a > b ? a : b);
    if (maxBlack == 0) return false;

    final centerX = width ~/ 2;
    final valleyHalfWidth = (width * 0.025).round();
    var valleyBlackPixels = 0;
    var valleyTotal = 0;

    for (
      var x = centerX - valleyHalfWidth;
      x <= centerX + valleyHalfWidth;
      x++
    ) {
      if (x < 0 || x >= width) continue;
      valleyBlackPixels += projection[x];
      valleyTotal++;
    }

    if (valleyTotal == 0) return false;

    final avgBlackInValley = valleyBlackPixels / valleyTotal;
    final whiteRatio = 1.0 - (avgBlackInValley / maxBlack);

    return whiteRatio >= _valleyWhiteRatio;
  }

  Future<bool> _detectVerticalLine(cv.Mat binary) async {
    final width = binary.cols;
    final height = binary.rows;

    final edges = await cv.cannyAsync(binary, 50, 150);
    final lines = await cv.HoughLinesAsync(
      edges,
      1.0,
      3.14159 / 180,
      (height * 0.6).round(),
    );
    edges.dispose();

    if (lines.rows == 0) {
      lines.dispose();
      return false;
    }

    final centerStart = width ~/ 3;
    final centerEnd = 2 * width ~/ 3;

    for (var i = 0; i < lines.rows; i++) {
      final rho = lines.at<double>(i, 0, 0);
      final theta = lines.at<double>(i, 0, 1);

      // theta ≈ 0 or π → vertical line
      final isVertical = theta < 0.15 || theta > 2.99;
      if (!isVertical) continue;

      // rho ≈ x position for a vertical line
      final x = rho.abs().round();
      if (x >= centerStart && x <= centerEnd) {
        lines.dispose();
        return true; // vertical separator found in the central zone
      }
    }

    lines.dispose();
    return false;
  }

  // ---------------------------------------------------------------------------
  // Step 2 — Column rect splitting
  // ---------------------------------------------------------------------------

  /// Returns the bounding rectangles for each column.
  Future<List<cv.Rect>> _splitColumnRects(
    cv.Mat binary,
    ColumnLayout layout,
  ) async {
    final width = binary.cols;
    final height = binary.rows;

    if (layout == ColumnLayout.single) {
      return [cv.Rect(0, 0, width, height)];
    }

    final splitX = await _findSplitX(binary);

    return [
      cv.Rect(0, 0, splitX, height),
      cv.Rect(splitX, 0, width - splitX, height),
    ];
  }

  Future<int> _findSplitX(cv.Mat binary) async {
    final width = binary.cols;
    final height = binary.rows;

    // Case A — minimum of vertical projection in center zone
    final centerStart = width ~/ 3;
    final centerEnd = 2 * width ~/ 3;

    var minBlack = double.infinity;
    var splitX = width ~/ 2;

    for (var x = centerStart; x < centerEnd; x++) {
      var blackCount = 0;
      for (var y = 0; y < height; y++) {
        if (binary.at<int>(y, x) == 0) blackCount++;
      }
      // Case B — a vertical line shows as a spike, not a valley.
      // We look for the x with the most vertically-aligned black pixels
      // that form a continuous line (not scattered text).
      if (blackCount.toDouble() < minBlack) {
        minBlack = blackCount.toDouble();
        splitX = x;
      }
    }

    // Case B override — if a Hough vertical line exists, use its x
    final edges = await cv.cannyAsync(binary, 50, 150);
    final lines = await cv.HoughLinesAsync(
      edges,
      1.0,
      3.14159 / 180,
      (height * 0.6).round(),
    );
    edges.dispose();

    for (var i = 0; i < lines.rows; i++) {
      final rho = lines.at<double>(i, 0, 0);
      final theta = lines.at<double>(i, 0, 1);
      final isVertical = theta < 0.15 || theta > 2.99;
      if (!isVertical) continue;
      final x = rho.abs().round();
      if (x >= centerStart && x <= centerEnd) {
        splitX = x;
        break;
      }
    }

    lines.dispose();
    return splitX;
  }

  // ---------------------------------------------------------------------------
  // Step 3 — Block detection within a column
  // ---------------------------------------------------------------------------

  /// Detects blocks within [colRegion] using horizontal projection.
  ///
  /// A gap of [_blockGapThreshold] or more white rows separates two blocks.
  /// Each block is then classified as [TextBlock], [HeaderBlock], or [DiagramBlock].
  Future<List<PageBlock>> _detectBlocks(
    cv.Mat colRegion,
    cv.Rect colRect,
    int pageWidth,
  ) async {
    final height = colRegion.rows;
    final width = colRegion.cols;

    // Horizontal projection: count black pixels per row
    final rowProjection = List<int>.filled(height, 0);
    for (var y = 0; y < height; y++) {
      var blackCount = 0;
      for (var x = 0; x < width; x++) {
        if (colRegion.at<int>(y, x) == 0) blackCount++;
      }
      rowProjection[y] = blackCount;
    }

    // Find block boundaries using gap detection
    final blockRects = <cv.Rect>[];
    var inBlock = false;
    var blockStart = 0;
    var gapCount = 0;

    for (var y = 0; y < height; y++) {
      final isEmpty = rowProjection[y] == 0;

      if (!inBlock && !isEmpty) {
        inBlock = true;
        blockStart = y;
        gapCount = 0;
      } else if (inBlock && isEmpty) {
        gapCount++;
        if (gapCount >= _blockGapThreshold) {
          // End of block
          blockRects.add(
            cv.Rect(
              colRect.x,
              colRect.y + blockStart,
              width,
              y - gapCount - blockStart,
            ),
          );
          inBlock = false;
        }
      } else if (inBlock && !isEmpty) {
        gapCount = 0;
      }
    }

    // Close the last block if page ends without a gap
    if (inBlock) {
      blockRects.add(
        cv.Rect(colRect.x, colRect.y + blockStart, width, height - blockStart),
      );
    }

    // Classify each detected block
    final blocks = <PageBlock>[];
    for (final rect in blockRects) {
      final region = colRegion.region(
        cv.Rect(
          rect.x - colRect.x,
          rect.y - colRect.y,
          rect.width,
          rect.height,
        ),
      );
      final block = await _classifyBlock(region, rect, pageWidth);
      blocks.add(block);
      region.dispose();
    }

    return blocks;
  }

  // ---------------------------------------------------------------------------
  // Step 3b — Block classification
  // ---------------------------------------------------------------------------

  /// Classifies a block region as [TextBlock], [HeaderBlock], or [DiagramBlock].
  Future<PageBlock> _classifyBlock(
    cv.Mat region,
    cv.Rect bounds,
    int pageWidth,
  ) async {
    // --- Diagram detection ---
    // Chess diagrams have a very regular grid structure:
    // strong horizontal and vertical lines at regular intervals.
    if (await _looksLikeDiagram(region)) {
      return DiagramBlock(bounds: bounds);
    }

    // --- Centered detection ---
    // Find leftmost and rightmost black pixels to estimate text margins
    var leftmost = region.cols;
    var rightmost = 0;

    for (var y = 0; y < region.rows; y++) {
      for (var x = 0; x < region.cols; x++) {
        if (region.at<int>(y, x) == 0) {
          if (x < leftmost) leftmost = x;
          if (x > rightmost) rightmost = x;
        }
      }
    }

    final leftMargin = leftmost.toDouble();
    final rightMargin = (region.cols - rightmost).toDouble();
    final marginDiff = (leftMargin - rightMargin).abs();
    final avgMargin = (leftMargin + rightMargin) / 2;
    final isCentered =
        avgMargin > 0 && (marginDiff / avgMargin) <= _centerTolerance;

    // --- Bold detection via average stroke width ---
    // Use connected components: bold text has thicker strokes
    // → larger average component height relative to block height
    final isBold = await _looksLikeBold(region);

    if (isCentered || isBold) {
      return HeaderBlock(
        bounds: bounds,
        isCentered: isCentered,
        isBold: isBold,
      );
    }

    return TextBlock(bounds: bounds);
  }

  // ---------------------------------------------------------------------------
  // Diagram detection heuristic
  // ---------------------------------------------------------------------------

  /// Returns true if [region] looks like a printed chess diagram.
  ///
  /// Heuristic: a diagram has strong, evenly-spaced horizontal and vertical
  /// lines. We detect this via Hough line density and regularity.
  Future<bool> _looksLikeDiagram(cv.Mat region) async {
    // Diagrams are roughly square — quick aspect ratio check
    final aspect = region.cols / region.rows;
    if (aspect < 0.7 || aspect > 1.3) return false;

    // Minimum size: a diagram should be at least 100×100 px
    if (region.cols < 100 || region.rows < 100) return false;

    final edges = await cv.cannyAsync(region, 50, 150);
    final lines = await cv.HoughLinesAsync(
      edges,
      1.0,
      3.14159 / 180,
      60,
    );
    edges.dispose();

    if (lines.rows < 16) {
      // A chess diagram has at least 9+9 = 18 grid lines
      lines.dispose();
      return false;
    }

    // Check for regularity: horizontal and vertical lines should be
    // evenly spaced (grid pattern)
    final horizontalYs = <double>[];
    final verticalXs = <double>[];

    for (var i = 0; i < lines.rows; i++) {
      final rho = lines.at<double>(i, 0, 0);
      final theta = lines.at<double>(i, 0, 1);

      // theta ≈ 0 or π → vertical line
      // theta ≈ π/2    → horizontal line
      if (theta < 0.2 || theta > 2.94) {
        verticalXs.add(rho.abs());
      } else if (theta > 1.37 && theta < 1.77) {
        horizontalYs.add(rho.abs());
      }
    }

    lines.dispose();

    // Need at least 7 horizontal and 7 vertical lines for an 8×8 grid
    if (horizontalYs.length < 7 || verticalXs.length < 7) return false;

    // Check regularity: spacing between consecutive lines should be uniform
    return _isRegularlySpaced(horizontalYs) && _isRegularlySpaced(verticalXs);
  }

  /// Returns true if [values] are approximately evenly spaced.
  /// Coefficient of variation of gaps < 25% is considered regular.
  bool _isRegularlySpaced(List<double> values) {
    if (values.length < 2) return false;
    values.sort();

    final gaps = <double>[];
    for (var i = 1; i < values.length; i++) {
      gaps.add(values[i] - values[i - 1]);
    }

    final mean = gaps.reduce((a, b) => a + b) / gaps.length;
    if (mean == 0) return false;

    final variance =
        gaps.map((g) => (g - mean) * (g - mean)).reduce((a, b) => a + b) /
        gaps.length;
    final cv = variance == 0 ? 0.0 : (variance / (mean * mean));

    return cv < 0.25;
  }

  // ---------------------------------------------------------------------------
  // Bold detection heuristic
  // ---------------------------------------------------------------------------

  /// Returns true if [region] contains text with bold-weight strokes.
  ///
  /// Strategy: analyze connected components — bold characters have a higher
  /// filled pixel ratio (solidity) than regular weight characters.
  Future<bool> _looksLikeBold(cv.Mat region) async {
    if (region.rows < 8) return false;

    final labels = cv.Mat.empty();
    final stats = cv.Mat.empty();
    final centroids = cv.Mat.empty();
    final numLabels = await cv.connectedComponentsWithStatsAsync(
      region,
      labels,
      stats,
      centroids,
      8,
      cv.MatType.CV_32SC1.value,
      cv.CCL_DEFAULT,
    );
    labels.dispose();
    centroids.dispose();

    if (numLabels < 3) {
      stats.dispose();
      return false;
    }

    var totalSolidity = 0.0;
    var componentCount = 0;

    for (var i = 1; i < numLabels; i++) {
      // skip label 0 (background)
      final w = stats.at<int>(i, cv.CC_STAT_WIDTH);
      final h = stats.at<int>(i, cv.CC_STAT_HEIGHT);
      final area = stats.at<int>(i, cv.CC_STAT_AREA);

      // Skip components that are too small (noise) or too large (diagram lines)
      if (w < 3 || h < 3 || w > 80 || h > 80) continue;

      final boundingArea = w * h;
      if (boundingArea == 0) continue;

      totalSolidity += area / boundingArea;
      componentCount++;
    }

    stats.dispose();

    if (componentCount == 0) return false;

    final avgSolidity = totalSolidity / componentCount;

    // Bold text typically has avgSolidity > 0.45
    // Regular text typically has avgSolidity < 0.35
    return avgSolidity > 0.45;
  }

  // ---------------------------------------------------------------------------
  // Step 4 — Intro/appendix detection
  // ---------------------------------------------------------------------------

  /// Returns true if the page contains little or no chess notation.
  ///
  /// Heuristic: count blocks that contain chess-like patterns
  /// (move numbers, SAN tokens) vs total text blocks.
  /// Pages below [_chessPatternThreshold] are considered intro/appendix.
  bool _isIntroPage(List<PageColumn> columns) {
    final allBlocks = columns.expand((c) => c.blocks).toList();

    // A page with diagrams is definitely a game page
    if (allBlocks.any((b) => b is DiagramBlock)) return false;

    // A page with header blocks is likely a game page
    if (allBlocks.any((b) => b is HeaderBlock && (b).isGameHeader)) {
      return false;
    }

    // Without OCR text available at this stage, fall back to block count:
    // intro pages tend to have very few or very many text blocks
    // with no headers and no diagrams.
    // A more accurate check happens after OCR in the extraction pipeline.
    final textBlockCount = allBlocks.whereType<TextBlock>().length;
    final headerCount = allBlocks.whereType<HeaderBlock>().length;

    // No headers + only text → likely intro
    return headerCount == 0 && textBlockCount > 0;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Future<cv.Mat> _binarize(cv.Mat gray) async {
    return cv.adaptiveThresholdAsync(
      gray,
      255,
      cv.ADAPTIVE_THRESH_GAUSSIAN_C,
      cv.THRESH_BINARY,
      15,
      8.0,
    );
  }

  void _assertNotEmpty(cv.Mat mat, String path) {
    if (mat.isEmpty) {
      throw OpenCvException('Failed to load image: $path');
    }
  }
}
