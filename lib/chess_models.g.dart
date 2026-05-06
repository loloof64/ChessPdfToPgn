// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chess_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

TextFragment _$TextFragmentFromJson(Map<String, dynamic> json) => TextFragment(
  text: json['text'] as String,
  x: (json['x'] as num).toInt(),
  y: (json['y'] as num).toInt(),
  width: (json['width'] as num).toInt(),
  height: (json['height'] as num).toInt(),
  confidence: (json['confidence'] as num).toInt(),
);

Map<String, dynamic> _$TextFragmentToJson(TextFragment instance) =>
    <String, dynamic>{
      'text': instance.text,
      'x': instance.x,
      'y': instance.y,
      'width': instance.width,
      'height': instance.height,
      'confidence': instance.confidence,
    };

PageData _$PageDataFromJson(Map<String, dynamic> json) => PageData(
  pageNumber: (json['page_number'] as num).toInt(),
  width: (json['width'] as num).toInt(),
  height: (json['height'] as num).toInt(),
  fragments: (json['fragments'] as List<dynamic>)
      .map((e) => TextFragment.fromJson(e as Map<String, dynamic>))
      .toList(),
);

Map<String, dynamic> _$PageDataToJson(PageData instance) => <String, dynamic>{
  'page_number': instance.pageNumber,
  'width': instance.width,
  'height': instance.height,
  'fragments': instance.fragments,
};

OcrExtraction _$OcrExtractionFromJson(Map<String, dynamic> json) =>
    OcrExtraction(
      version: json['version'] as String,
      totalPages: (json['total_pages'] as num).toInt(),
      totalFragments: (json['total_fragments'] as num).toInt(),
      pages: (json['pages'] as List<dynamic>)
          .map((e) => PageData.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$OcrExtractionToJson(OcrExtraction instance) =>
    <String, dynamic>{
      'version': instance.version,
      'total_pages': instance.totalPages,
      'total_fragments': instance.totalFragments,
      'pages': instance.pages,
    };
