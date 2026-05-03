/// Converts annotation symbols to PGN NAG codes ($N).
class AnnotationParser {
  static const _annotationToNag = {
    '!!': r'$3',
    '??': r'$4',
    '!?': r'$5',
    '?!': r'$6',
    '!': r'$1',
    '?': r'$2',
    '□': r'$7', // only move
    '⊙': r'$22', // zugzwang
    '±': r'$14', // white slightly better
    '∓': r'$15', // black slightly better
    '⩲': r'$16', // white better
    '⩱': r'$17', // black better
    '+-': r'$18', // white wins
    '-+': r'$19', // black wins
    '=': r'$10', // equal
    '∞': r'$13', // unclear position
    '→': r'$40', // attack
    '⇄': r'$32', // compensation
  };

  /// Extracts NAGs present in [token] and returns
  /// the cleaned token + the list of found NAGs.
  static ({String clean, List<String> nags}) extract(String token) {
    var clean = token;
    final nags = <String>[];

    // Preserve promotion suffix BEFORE scanning for annotations
    // e.g. e8=Q — the '=' here is promotion, not equality symbol
    final promotionMatch = RegExp(r'=[QRBN]').firstMatch(clean);
    final promotionSuffix = promotionMatch?.group(0); // '=Q', '=R', etc.
    if (promotionSuffix != null) {
      // Temporarily remove promotion to avoid '=' being treated as NAG
      clean = clean.replaceFirst(promotionSuffix, '\x00PROMO\x00');
    }

    // Process annotations longest-first to avoid partial matches
    _annotationToNag.forEach((symbol, nag) {
      if (clean.contains(symbol)) {
        clean = clean.replaceAll(symbol, '');
        nags.add(nag);
      }
    });

    // Restore promotion suffix
    if (promotionSuffix != null) {
      clean = clean.replaceFirst('\x00PROMO\x00', promotionSuffix);
    }

    return (clean: clean.trim(), nags: nags);
  }
}
