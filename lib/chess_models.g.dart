// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chess_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

TextLine _$TextLineFromJson(Map<String, dynamic> json) => TextLine(
  text: json['text'] as String,
  x: (json['x'] as num).toInt(),
  y: (json['y'] as num).toInt(),
  width: (json['width'] as num).toInt(),
  height: (json['height'] as num).toInt(),
  confidence: (json['confidence'] as num).toInt(),
  column: (json['column'] as num).toInt(),
);

Map<String, dynamic> _$TextLineToJson(TextLine instance) => <String, dynamic>{
  'text': instance.text,
  'x': instance.x,
  'y': instance.y,
  'width': instance.width,
  'height': instance.height,
  'confidence': instance.confidence,
  'column': instance.column,
};

PageData _$PageDataFromJson(Map<String, dynamic> json) => PageData(
  pageNumber: (json['page_number'] as num).toInt(),
  width: (json['width'] as num).toInt(),
  height: (json['height'] as num).toInt(),
  lines: (json['lines'] as List<dynamic>)
      .map((e) => TextLine.fromJson(e as Map<String, dynamic>))
      .toList(),
);

Map<String, dynamic> _$PageDataToJson(PageData instance) => <String, dynamic>{
  'page_number': instance.pageNumber,
  'width': instance.width,
  'height': instance.height,
  'lines': instance.lines,
};

OcrExtraction _$OcrExtractionFromJson(Map<String, dynamic> json) =>
    OcrExtraction(
      version: json['version'] as String,
      totalPages: (json['total_pages'] as num).toInt(),
      totalLines: (json['total_lines'] as num).toInt(),
      pages: (json['pages'] as List<dynamic>)
          .map((e) => PageData.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$OcrExtractionToJson(OcrExtraction instance) =>
    <String, dynamic>{
      'version': instance.version,
      'total_pages': instance.totalPages,
      'total_lines': instance.totalLines,
      'pages': instance.pages,
    };
