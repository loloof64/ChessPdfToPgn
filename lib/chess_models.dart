import 'package:json_annotation/json_annotation.dart';

part 'chess_models.g.dart';

/// Represents a single chess move with its metadata
@JsonSerializable()
class ChessMove {
  final int number;
  final String white;
  final String? black;
  @JsonKey(name: 'comment_white')
  final String? commentWhite;
  @JsonKey(name: 'comment_black')
  final String? commentBlack;
  @JsonKey(name: 'has_diagram')
  final bool hasDiagram;

  ChessMove({
    required this.number,
    required this.white,
    this.black,
    this.commentWhite,
    this.commentBlack,
    this.hasDiagram = false,
  });

  /// Converts the move to PGN format with comments
  String toPgn({bool includeComments = true}) {
    final buffer = StringBuffer();
    
    // Add move number (every 2 moves, after each black move)
    if (black != null) {
      buffer.write('$number. $white ');
      
      if (commentWhite != null && includeComments && !hasDiagram) {
        buffer.write('{${commentWhite!}} ');
      }
      
      buffer.write('$black');
      
      if (commentBlack != null && includeComments && !hasDiagram) {
        buffer.write(' {${commentBlack!}}');
      }
    } else {
      buffer.write('$number. $white');
      
      if (commentWhite != null && includeComments && !hasDiagram) {
        buffer.write(' {${commentWhite!}}');
      }
    }
    
    return buffer.toString();
  }

  factory ChessMove.fromJson(Map<String, dynamic> json) => _$ChessMoveFromJson(json);
  Map<String, dynamic> toJson() => _$ChessMoveToJson(this);
}

/// Represents a complete chess game
@JsonSerializable()
class ChessGame {
  final String white;
  final String black;
  final String? date;
  final String? event;
  final String? site;
  @JsonKey(name: 'elo_white')
  final String? eloWhite;
  @JsonKey(name: 'elo_black')
  final String? eloBlack;
  final String result;
  @JsonKey(name: 'starting_position')
  final String startingPosition;
  final int page;
  @JsonKey(name: 'game_number')
  final int gameNumber;
  final List<ChessMove> moves;

  ChessGame({
    required this.white,
    required this.black,
    this.date,
    this.event,
    this.site,
    this.eloWhite,
    this.eloBlack,
    this.result = '*',
    this.startingPosition = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
    required this.page,
    required this.gameNumber,
    required this.moves,
  });

  /// Exports the game in complete PGN format
  String toPgn({bool includeComments = true}) {
    final buffer = StringBuffer();
    
    // PGN headers (mandatory)
    buffer.writeln('[Event "${ event ?? 'Chess Game'}"]');
    buffer.writeln('[Site "${ site ?? '?'}"]');
    buffer.writeln('[Date "${ date ?? '????.??.??'}"]');
    buffer.writeln('[White "$white"]');
    buffer.writeln('[Black "$black"]');
    buffer.writeln('[Result "$result"]');
    
    // Optional headers
    if (eloWhite != null) buffer.writeln('[WhiteElo "$eloWhite"]');
    if (eloBlack != null) buffer.writeln('[BlackElo "$eloBlack"]');
    
    // Starting position if non-standard
    if (startingPosition != 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1') {
      buffer.writeln('[FEN "$startingPosition"]');
    }
    
    buffer.writeln();
    
    // Game moves and comments
    final pgnMoves = moves.map((m) => m.toPgn(includeComments: includeComments)).join(' ');
    buffer.write(pgnMoves);
    buffer.write(' $result');
    
    return buffer.toString();
  }

  /// Validates that the game has at least one move
  bool isValid() => moves.isNotEmpty && white.isNotEmpty && black.isNotEmpty;

  factory ChessGame.fromJson(Map<String, dynamic> json) => _$ChessGameFromJson(json);
  Map<String, dynamic> toJson() => _$ChessGameToJson(this);
}

/// Container for complete PDF extraction
@JsonSerializable()
class ChessExtraction {
  final String version;
  @JsonKey(name: 'total_games')
  final int totalGames;
  final List<ChessGame> games;

  ChessExtraction({
    required this.version,
    required this.totalGames,
    required this.games,
  });

  /// Validates the extraction
  bool isValid() => games.isNotEmpty && games.every((g) => g.isValid());

  /// Total number of moves extracted
  int get totalMoves => games.fold(0, (sum, game) => sum + game.moves.length);

  factory ChessExtraction.fromJson(Map<String, dynamic> json) => _$ChessExtractionFromJson(json);
  Map<String, dynamic> toJson() => _$ChessExtractionToJson(this);
}
