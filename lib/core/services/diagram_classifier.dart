import 'dart:io';
import 'dart:math' as math;
import 'package:dartcv4/dartcv.dart' as cv;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

enum PieceColor { empty, white, black }

enum PieceType { K, Q, R, B, N, P }

class SquareContent {
  final PieceColor color;
  final PieceType? type; // null if empty
  final double confidence;

  const SquareContent({
    required this.color,
    this.type,
    required this.confidence,
  });

  bool get isEmpty => color == PieceColor.empty;

  /// Returns standard FEN character or '.' for empty.
  String get fenChar {
    if (isEmpty) return '.';
    final letter = type!.name; // 'K','Q','R','B','N','P'
    return color == PieceColor.white ? letter : letter.toLowerCase();
  }

  @override
  String toString() =>
      isEmpty ? '.' : '${color.name[0].toUpperCase()}${type!.name}';
}

// ---------------------------------------------------------------------------
// DiagramClassifier
// ---------------------------------------------------------------------------

/// Classifies chess pieces from a segmented board image.
///
/// Pipeline for each square:
///   1. Color detection  — heuristic (very dark pixel ratio)
///   2. Type detection   — TFLite CNN (K/Q/R/B/N/P)
///
/// Usage:
/// ```dart
/// final classifier = DiagramClassifier();
/// await classifier.init();
/// final fen = await classifier.boardToFen(boardImage800x800);
/// ```
class DiagramClassifier {
  static const String _modelAsset =
      'assets/models/chess_type_classifier.tflite';
  static const int _imgSize = 64;
  static const int _squareSize = 100; // 800px board / 8 squares

  // Color heuristic thresholds (calibrated from training data)
  static const double _emptyThreshold = 0.02;
  static const double _blackThreshold = 0.10;

  late final Interpreter _interpreter;
  bool _initialized = false;

  // ---------------------------------------------------------------------------
  // Initialization
  // ---------------------------------------------------------------------------

  /// Loads the TFLite model from assets.
  /// Must be called once before any classification.
  Future<void> init() async {
    if (_initialized) return;

    // Copy asset to temp file (required by tflite_flutter on desktop)
    final modelData = await rootBundle.load(_modelAsset);
    final tmpDir = await getTemporaryDirectory();
    final modelPath = p.join(tmpDir.path, 'chess_type_classifier.tflite');
    final modelFile = File(modelPath);
    await modelFile.writeAsBytes(modelData.buffer.asUint8List());

    _interpreter = Interpreter.fromFile(modelFile);
    _interpreter.allocateTensors();
    _initialized = true;
  }

  void dispose() {
    if (_initialized) {
      _interpreter.close();
      _initialized = false;
    }
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Classifies all 64 squares of an 800×800 board image.
  /// Returns a list of 64 [SquareContent], ordered rank 8→1, file a→h
  /// (i.e. top-left to bottom-right as printed).
  Future<List<SquareContent>> classifyBoard(cv.Mat board800) async {
    assert(_initialized, 'Call init() before classifyBoard()');
    assert(
      board800.cols == 800 && board800.rows == 800,
      'Board image must be 800×800',
    );

    final results = <SquareContent>[];

    for (var row = 0; row < 8; row++) {
      for (var col = 0; col < 8; col++) {
        final square = board800.region(
          cv.Rect(
            col * _squareSize,
            row * _squareSize,
            _squareSize,
            _squareSize,
          ),
        );
        final content = await _classifySquare(square);
        results.add(content);
        square.dispose();
      }
    }

    return results;
  }

  /// Converts a list of 64 [SquareContent] into a FEN position string.
  /// Example: `rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKB1R`
  String toFen(List<SquareContent> squares) {
    assert(squares.length == 64);
    final rows = <String>[];

    for (var row = 0; row < 8; row++) {
      var fenRow = '';
      var empty = 0;

      for (var col = 0; col < 8; col++) {
        final sq = squares[row * 8 + col];
        if (sq.isEmpty) {
          empty++;
        } else {
          if (empty > 0) {
            fenRow += '$empty';
            empty = 0;
          }
          fenRow += sq.fenChar;
        }
      }
      if (empty > 0) fenRow += '$empty';
      rows.add(fenRow);
    }

    return rows.join('/');
  }

  /// Convenience: classify board and return FEN in one call.
  Future<String> boardToFen(cv.Mat board800) async {
    final squares = await classifyBoard(board800);
    return toFen(squares);
  }

  // ---------------------------------------------------------------------------
  // Private — square classification
  // ---------------------------------------------------------------------------

  Future<SquareContent> _classifySquare(cv.Mat square) async {
    // Step 1 — Convert to grayscale
    final gray = await cv.cvtColorAsync(square, cv.COLOR_BGR2GRAY);

    // Step 2 — Color heuristic
    final color = _detectColor(gray);

    gray.dispose();

    if (color == PieceColor.empty) {
      return const SquareContent(
        color: PieceColor.empty,
        type: null,
        confidence: 1.0,
      );
    }

    // Step 3 — Normalize to white background
    final normalized = await _normalizeSquare(square);

    // Step 4 — TFLite type classification
    final (type, confidence) = await _classifyType(normalized);

    normalized.dispose();

    return SquareContent(color: color, type: type, confidence: confidence);
  }

  // ---------------------------------------------------------------------------
  // Private — color heuristic
  // ---------------------------------------------------------------------------

  /// Detects piece color using the ratio of very dark pixels in the center.
  PieceColor _detectColor(cv.Mat graySquare) {
    final h = graySquare.rows;
    final w = graySquare.cols;
    final m = h ~/ 6;

    // Sample the center region (avoids square border pixels)
    final center = graySquare.region(cv.Rect(m, m, w - 2 * m, h - 2 * m));

    int veryDark = 0;
    final total = center.rows * center.cols;

    for (var y = 0; y < center.rows; y++) {
      for (var x = 0; x < center.cols; x++) {
        if (center.at<int>(y, x) < 60) veryDark++;
      }
    }
    center.dispose();

    final ratio = veryDark / total;

    if (ratio < _emptyThreshold) return PieceColor.empty;
    if (ratio > _blackThreshold) return PieceColor.black;
    return PieceColor.white;
  }

  // ---------------------------------------------------------------------------
  // Private — normalization
  // ---------------------------------------------------------------------------

  /// Removes hatch pattern and gray background.
  /// Returns a binary image with white background and black piece silhouette.
  Future<cv.Mat> _normalizeSquare(cv.Mat square) async {
    final gray = await cv.cvtColorAsync(square, cv.COLOR_BGR2GRAY);

    // Morphological closing to fill hatch lines
    final kernel = cv.getStructuringElement(cv.MORPH_ELLIPSE, (5, 5));
    final closed = await cv.morphologyExAsync(gray, cv.MORPH_CLOSE, kernel);

    // Adaptive threshold to isolate piece from background
    final binary = await cv.adaptiveThresholdAsync(
      closed,
      255,
      cv.ADAPTIVE_THRESH_GAUSSIAN_C,
      cv.THRESH_BINARY,
      21,
      5.0,
    );

    gray.dispose();
    closed.dispose();
    kernel.dispose();

    return binary;
  }

  // ---------------------------------------------------------------------------
  // Private — TFLite type classification
  // ---------------------------------------------------------------------------

  /// Runs the TFLite model on a normalized square image.
  /// Returns (PieceType, confidence).
  Future<(PieceType, double)> _classifyType(cv.Mat normalizedSquare) async {
    // Resize to model input size (64×64)
    final resized = await cv.resizeAsync(normalizedSquare, ((
      _imgSize,
      _imgSize,
    )));

    // Convert to float32 tensor [1, 64, 64, 1], normalized 0→1
    final input = List.generate(
      1,
      (_) => List.generate(
        _imgSize,
        (y) => List.generate(
          _imgSize,
          (x) => List.generate(1, (_) => resized.at<int>(y, x) / 255.0),
        ),
      ),
    );
    resized.dispose();

    // Run inference
    final output = List.generate(1, (_) => List.filled(6, 0.0));
    _interpreter.run(input, output);

    final probs = output[0];
    final maxIdx = probs.indexOf(probs.reduce(math.max));
    final confidence = probs[maxIdx];
    final type = PieceType.values[maxIdx];

    return (type, confidence);
  }
}
