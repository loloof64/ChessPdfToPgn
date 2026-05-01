import '../../core/models/game_extraction_config.dart';

/// Converts local piece letters to English SAN letters.
/// Only used when GameExtractionConfig.usesFigurine == false.
class PieceLocalizer {
  final Map<String, String> _pieceMap;

  PieceLocalizer(NotationLocale locale) : _pieceMap = locale.pieceMap;

  String normalize(String move) {
    var result = move;
    _pieceMap.forEach((local, san) {
      result = result.replaceAll(local, san);
    });
    return result;
  }
}
