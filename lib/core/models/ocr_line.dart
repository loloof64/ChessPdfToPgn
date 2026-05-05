import 'dart:math';

/// Represents a single line of text extracted from OCR with spatial coordinates
class OCRLine {
  final String text;
  final int x; // Left position in pixels
  final int y; // Top position in pixels
  final int width;
  final int height;
  final double confidence;

  const OCRLine({
    required this.text,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.confidence,
  });

  /// Center X coordinate
  int get centerX => x + (width ~/ 2);

  /// Center Y coordinate
  int get centerY => y + (height ~/ 2);

  /// Bottom Y coordinate
  int get bottom => y + height;

  /// Right X coordinate
  int get right => x + width;

  /// Check if this line is approximately on the same horizontal level as another
  /// (within tolerance of 15 pixels)
  bool isSameRowAs(OCRLine other, {int tolerance = 15}) {
    return (y - other.y).abs() < tolerance;
  }

  /// Check if this line is approximately in the same vertical column as another
  /// (within tolerance of 50 pixels)
  bool isSameColumnAs(OCRLine other, {int tolerance = 50}) {
    return (centerX - other.centerX).abs() < tolerance;
  }

  /// Check if this line is to the left of another
  bool isLeftOf(OCRLine other) => right < other.x;

  /// Check if this line is to the right of another
  bool isRightOf(OCRLine other) => x > other.right;

  /// Distance to another line (center to center)
  double distanceTo(OCRLine other) {
    final dx = centerX - other.centerX;
    final dy = centerY - other.centerY;
    return sqrt((dx * dx + dy * dy).toDouble());
  }

  @override
  String toString() =>
      'OCRLine(text: "$text", x: $x, y: $y, conf: $confidence)';
}
