import 'dart:io';
import 'package:dartcv4/dartcv.dart' as cv;

/// Handles image preprocessing before passing to Tesseract OCR.
/// Two preprocessing profiles are available:
///   - [preprocessBookPage] for printed book text (Branch A)
///   - [preprocessDiagram]  for printed magazine chess diagrams (Branch B)
class OpenCvService {
  // ---------------------------------------------------------------------------
  // Branch A — Book page (printed text + FAN glyphs)
  // ---------------------------------------------------------------------------

  /// Preprocesses a scanned book page for optimal OCR accuracy.
  ///
  /// Pipeline:
  ///   1. Grayscale conversion
  ///   2. Light denoising (printed text has low noise)
  ///   3. Adaptive thresholding (handles uneven lighting across the page)
  ///   4. Deskew if needed
  ///
  /// Returns the path to the preprocessed image (temp file).
  Future<String> preprocessBookPage(String inputPath) async {
    final src = await cv.imreadAsync(inputPath, flags: cv.IMREAD_COLOR);
    _assertNotEmpty(src, inputPath);

    // Step 1 — Grayscale
    final gray = await cv.cvtColorAsync(src, cv.COLOR_BGR2GRAY);

    // Step 2 — Light denoising (h=10 is sufficient for clean book scans)
    final denoised = await cv.fastNlMeansDenoisingAsync(gray, h: 10);

    // Step 3 — Adaptive threshold
    // blockSize=15 and C=8 work well for standard book fonts
    final binary = await cv.adaptiveThresholdAsync(
      denoised,
      255,
      cv.ADAPTIVE_THRESH_GAUSSIAN_C,
      cv.THRESH_BINARY,
      15,
      8,
    );

    // Step 4 — Deskew (correct slight rotation from scanning)
    final deskewed = await _deskew(binary);

    final outPath = _tempPath(inputPath, suffix: '_book');
    await cv.imwriteAsync(outPath, deskewed);

    src.dispose();
    gray.dispose();
    denoised.dispose();
    binary.dispose();
    deskewed.dispose();

    return outPath;
  }

  // ---------------------------------------------------------------------------
  // Branch B — Chess diagram (printed magazine style)
  // ---------------------------------------------------------------------------

  /// Preprocesses a chess diagram image and extracts the 64 squares.
  ///
  /// Pipeline:
  ///   1. Grayscale + threshold to isolate the board grid
  ///   2. Board contour detection
  ///   3. Perspective correction (warpPerspective to a flat 800×800 grid)
  ///   4. Split into 64 individual square images
  ///
  /// Returns a list of 64 square image paths, ordered a8→h8, a7→h7, ... a1→h1
  /// (i.e. top-left to bottom-right as printed).
  Future<List<String>> extractBoardSquares(String inputPath) async {
    final src = await cv.imreadAsync(inputPath, flags: cv.IMREAD_COLOR);
    _assertNotEmpty(src, inputPath);

    final gray = await cv.cvtColorAsync(src, cv.COLOR_BGR2GRAY);

    // Strong threshold to isolate the black grid lines
    final (_, binary) = await cv.thresholdAsync(gray, 128, 255, cv.THRESH_BINARY_INV);

    // Detect the board outer contour
    final warped = await _warpBoard(src, binary);

    // Split the 800×800 warped board into 64 squares of 100×100 px
    final squarePaths = <String>[];
    const boardSize = 800;
    const squareSize = boardSize ~/ 8;

    for (var row = 0; row < 8; row++) {
      for (var col = 0; col < 8; col++) {
        final roi = cv.Rect(
          col * squareSize,
          row * squareSize,
          squareSize,
          squareSize,
        );
        final square = warped.region(roi);
        final squarePath = _tempPath(inputPath, suffix: '_sq_${row}_$col');
        await cv.imwriteAsync(squarePath, square);
        squarePaths.add(squarePath);
        square.dispose();
      }
    }

    src.dispose();
    gray.dispose();
    binary.dispose();
    warped.dispose();

    return squarePaths;
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Corrects slight rotation (skew) of a scanned page using Hough lines.
  Future<cv.Mat> _deskew(cv.Mat binary) async {
    final edges = await cv.cannyAsync(binary, 50, 150);
    final lines = await cv.HoughLinesAsync(
      edges,
      1,
      3.14159 / 180,
      100,
    );

    if (lines.isEmpty) {
      edges.dispose();
      return binary.clone();
    }

    // Compute the median angle of detected lines
    final angles = <double>[];
    for (var i = 0; i < lines.rows; i++) {
      final theta = lines.at<double>(i, 0, 1);
      final angle = (theta - 3.14159 / 2) * (180 / 3.14159);
      if (angle.abs() < 45) angles.add(angle);
    }

    edges.dispose();
    lines.dispose();

    if (angles.isEmpty) return binary.clone();

    angles.sort();
    final medianAngle = angles[angles.length ~/ 2];

    // Skip rotation if the skew is negligible (< 0.5°)
    if (medianAngle.abs() < 0.5) return binary.clone();

    // Rotate around the image center
    final center = cv.Point2f(binary.cols / 2, binary.rows / 2);
    final rotMatrix = cv.getRotationMatrix2D(center, medianAngle, 1.0);
    final deskewed = await cv.warpAffineAsync(binary, rotMatrix, (
      binary.cols,
      binary.rows,
    ));

    rotMatrix.dispose();
    return deskewed;
  }

  /// Detects the board bounding quadrilateral and applies perspective correction.
  /// Returns an 800×800 warped image of the board.
  Future<cv.Mat> _warpBoard(cv.Mat src, cv.Mat binary) async {
    final contours = await cv.findContoursAsync(
      binary,
      cv.RETR_EXTERNAL,
      cv.CHAIN_APPROX_SIMPLE,
    );

    if (contours.$1.isEmpty) {
      throw OpenCvException('No contours found — board not detected in image.');
    }

    // Pick the largest contour (should be the board border)
    cv.VecPoint? boardContour;
    double maxArea = 0;
    for (final contour in contours.$1) {
      final area = cv.contourArea(contour);
      if (area > maxArea) {
        maxArea = area;
        boardContour = contour;
      }
    }

    // Approximate to a quadrilateral
    final perimeter = cv.arcLength(boardContour!, true);
    final approx = cv.approxPolyDP(boardContour, 0.02 * perimeter, true);

    if (approx.length != 4) {
      throw OpenCvException(
        'Board contour is not a quadrilateral '
        '(${approx.length} vertices found). '
        'Check image quality or crop.',
      );
    }

    // Sort corners: top-left, top-right, bottom-right, bottom-left
    final corners = _sortCorners(approx);

    final dst = cv.VecPoint2f.fromList([
      cv.Point2f(0, 0),
      cv.Point2f(800, 0),
      cv.Point2f(800, 800),
      cv.Point2f(0, 800),
    ]);

    final M = cv.getPerspectiveTransform2f(corners, dst);
    final warped = await cv.warpPerspectiveAsync(src, M, (800, 800));

    M.dispose();
    dst.dispose();
    corners.dispose();

    return warped;
  }

  /// Sorts 4 corner points into [top-left, top-right, bottom-right, bottom-left].
  cv.VecPoint2f _sortCorners(cv.VecPoint approx) {
    final pts = List.generate(approx.length, (i) => approx[i]);

    // Top points have smaller y, bottom points larger y
    pts.sort((a, b) => a.y.compareTo(b.y));
    final top = pts.sublist(0, 2)..sort((a, b) => a.x.compareTo(b.x));
    final bottom = pts.sublist(2, 4)..sort((a, b) => b.x.compareTo(a.x));

    return cv.VecPoint2f.fromList([
      cv.Point2f(top[0].x.toDouble(), top[0].y.toDouble()),
      cv.Point2f(top[1].x.toDouble(), top[1].y.toDouble()),
      cv.Point2f(bottom[0].x.toDouble(), bottom[0].y.toDouble()),
      cv.Point2f(bottom[1].x.toDouble(), bottom[1].y.toDouble()),
    ]);
  }

  /// Asserts that the loaded image is not empty (file not found or unreadable).
  void _assertNotEmpty(cv.Mat mat, String path) {
    if (mat.isEmpty) {
      throw OpenCvException('Failed to load image: $path');
    }
  }

  /// Builds a temp file path alongside the original file.
  String _tempPath(String inputPath, {required String suffix}) {
    final dir = File(inputPath).parent.path;
    final name = File(inputPath).uri.pathSegments.last.split('.').first;
    return '$dir/$name$suffix.png';
  }
}

class OpenCvException implements Exception {
  final String message;
  const OpenCvException(this.message);

  @override
  String toString() => 'OpenCvException: $message';
}
