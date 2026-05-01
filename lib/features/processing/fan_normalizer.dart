/// Converts Unicode FAN glyphs to English SAN letters.
/// Only used when GameExtractionConfig.usesFigurine == true.
class FanNormalizer {
  static const _fanToSan = {
    '♔': 'K',
    '♚': 'K',
    '♕': 'Q',
    '♛': 'Q',
    '♖': 'R',
    '♜': 'R',
    '♗': 'B',
    '♝': 'B',
    '♘': 'N',
    '♞': 'N',
  };

  static String normalize(String input) {
    var result = input;
    _fanToSan.forEach((fan, san) {
      result = result.replaceAll(fan, san);
    });
    return result;
  }
}
