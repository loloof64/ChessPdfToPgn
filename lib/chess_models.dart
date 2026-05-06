import 'package:json_annotation/json_annotation.dart';

part 'chess_models.g.dart';

/// Represents a single text fragment from OCR
@JsonSerializable()
class TextFragment {
  final String text;
  final int x;      // left position
  final int y;      // top position
  final int width;
  final int height;
  final int confidence;  // OCR confidence (0-100)

  TextFragment({
    required this.text,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.confidence,
  });

  factory TextFragment.fromJson(Map<String, dynamic> json) => _$TextFragmentFromJson(json);
  Map<String, dynamic> toJson() => _$TextFragmentToJson(this);
}

/// Represents all OCR data on a single page
@JsonSerializable()
class PageData {
  @JsonKey(name: 'page_number')
  final int pageNumber;
  final int width;
  final int height;
  final List<TextFragment> fragments;

  PageData({
    required this.pageNumber,
    required this.width,
    required this.height,
    required this.fragments,
  });

  /// Get raw text by joining all fragments
  String getRawText() {
    return fragments.map((f) => f.text).join(' ');
  }

  /// Get fragments sorted by position (reading order)
  List<TextFragment> getFragmentsInOrder() {
    final sorted = List<TextFragment>.from(fragments);
    sorted.sort((a, b) {
      // Sort by Y first (top to bottom), then X (left to right)
      if ((a.y - b.y).abs() > 10) {
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
  @JsonKey(name: 'total_fragments')
  final int totalFragments;
  final List<PageData> pages;

  OcrExtraction({
    required this.version,
    required this.totalPages,
    required this.totalFragments,
    required this.pages,
  });

  /// Validate extraction
  bool isValid() {
    return pages.isNotEmpty && pages.every((p) => p.fragments.isNotEmpty);
  }

  /// Get all text as single string
  String getAllText() {
    return pages.map((p) => p.getRawText()).join('\n');
  }

  factory OcrExtraction.fromJson(Map<String, dynamic> json) => _$OcrExtractionFromJson(json);
  Map<String, dynamic> toJson() => _$OcrExtractionToJson(this);
}
