enum NotationLocale {
  english,
  french,
  spanish,
  german,
  russian,
  dutch;

  /// Mapping Tesseract language
  String get tessLang => switch (this) {
    NotationLocale.english => 'eng',
    NotationLocale.french => 'fra',
    NotationLocale.spanish => 'spa',
    NotationLocale.german => 'deu',
    NotationLocale.russian => 'rus',
    NotationLocale.dutch => 'nld',
  };

  /// Mapping local letter →  english SAN letter (except pawn)
  Map<String, String> get pieceMap => switch (this) {
    NotationLocale.french => {'R': 'K', 'D': 'Q', 'T': 'R', 'F': 'B', 'C': 'N'},
    NotationLocale.spanish => {
      'R': 'K',
      'D': 'Q',
      'T': 'R',
      'A': 'B',
      'C': 'N',
    },
    NotationLocale.german => {'K': 'K', 'D': 'Q', 'T': 'R', 'L': 'B', 'S': 'N'},
    NotationLocale.russian => {
      'Кр': 'K',
      'Ф': 'Q',
      'Л': 'R',
      'С': 'B',
      'К': 'N',
    },
    NotationLocale.dutch => {'K': 'K', 'D': 'Q', 'T': 'R', 'L': 'B', 'P': 'N'},
    NotationLocale.english => {
      'K': 'K',
      'Q': 'Q',
      'R': 'R',
      'B': 'B',
      'N': 'N',
    },
  };
}

enum CommentStyle {
  braces, // { comment }  — standard PGN
  parentheses, // ( comment )  — some old books
  mixed, // both - detected on content
}

class GameExtractionConfig {
  final NotationLocale locale;
  final bool usesFigurine; // true = FAN (♔), false = local letters
  final CommentStyle commentStyle;

  const GameExtractionConfig({
    required this.locale,
    required this.usesFigurine,
    this.commentStyle = CommentStyle.mixed,
  });
}
