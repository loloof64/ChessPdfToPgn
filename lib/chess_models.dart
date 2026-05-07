import 'package:json_annotation/json_annotation.dart';

part 'chess_models.g.dart';

/// Represents a single text line from OCR
@JsonSerializable()
class TextLine {
  final String text;
  final int x;
  final int y;
  final int width;
  final int height;
  final int confidence;
  final int column; // Column index

  TextLine({
    required this.text,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.confidence,
    required this.column,
  });

  factory TextLine.fromJson(Map<String, dynamic> json) => _$TextLineFromJson(json);
  Map<String, dynamic> toJson() => _$TextLineToJson(this);
}

/// Represents all OCR data on a single page
@JsonSerializable()
class PageData {
  @JsonKey(name: 'page_number')
  final int pageNumber;
  final int width;
  final int height;
  final List<TextLine> lines;

  PageData({
    required this.pageNumber,
    required this.width,
    required this.height,
    required this.lines,
  });

  /// Get raw text by joining all lines
  String getRawText() {
    return lines.map((line) => line.text).join('\n');
  }

  /// Get lines sorted by position (reading order)
  List<TextLine> getLinesInOrder() {
    final sorted = List<TextLine>.from(lines);
    sorted.sort((a, b) {
      // Sort by Y first (top to bottom), then X (left to right)
      if ((a.y - b.y).abs() > 15) {
        return a.y.compareTo(b.y);
      }
      return a.x.compareTo(b.x);
    });
    return sorted;
  }

  factory PageData.fromJson(Map<String, dynamic> json) => _$PageDataFromJson(json);
  Map<String, dynamic> toJson() => _$PageDataToJson(this);
}

/// Represents the complete OCR extraction from a PDF
@JsonSerializable()
class OcrExtraction {
  final String version;
  @JsonKey(name: 'total_pages')
  final int totalPages;
  @JsonKey(name: 'total_lines')
  final int totalLines;
  final List<PageData> pages;

  OcrExtraction({
    required this.version,
    required this.totalPages,
    required this.totalLines,
    required this.pages,
  });

  /// Validate extraction
  bool isValid() {
    return pages.isNotEmpty && pages.every((p) => p.lines.isNotEmpty);
  }

  /// Get all text as single string
  String getAllText() {
    return pages.map((p) => p.getRawText()).join('\n\n');
  }

  factory OcrExtraction.fromJson(Map<String, dynamic> json) => _$OcrExtractionFromJson(json);
  Map<String, dynamic> toJson() => _$OcrExtractionToJson(this);
}
