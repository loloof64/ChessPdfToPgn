import 'dart:io';
import 'dart:convert';
import 'chess_models.dart';

/// Service to process JSON extractions and generate PGN files
class ChessPgnService {
  /// Parse the JSON extracted from Colab
  static Future<ChessExtraction> loadFromJson(String jsonString) async {
    try {
      final json = jsonDecode(jsonString);
      return ChessExtraction.fromJson(json);
    } catch (e) {
      throw Exception('JSON parsing error: $e');
    }
  }

  /// Load JSON from a file
  static Future<ChessExtraction> loadFromFile(String filePath) async {
    try {
      final file = File(filePath);
      final jsonString = await file.readAsString();
      return loadFromJson(jsonString);
    } catch (e) {
      throw Exception('File read error: $e');
    }
  }

  /// Convert figurine notation to algebraic notation
  /// Example: ♘f3 → Nf3, ♙e4 → e4
  static String convertFigurineToAlgebraic(String notation) {
    const figurineMap = {
      '♔': 'K',
      '♕': 'Q',
      '♖': 'R',
      '♗': 'B',
      '♘': 'N',
      '♙': '', // Pawns have no letter
      '♚': 'k',
      '♛': 'q',
      '♜': 'r',
      '♝': 'b',
      '♞': 'n',
      '♟': '',
    };

    String result = notation;
    figurineMap.forEach((figurine, letter) {
      result = result.replaceAll(figurine, letter);
    });

    return result.trim();
  }

  /// Validate a move in PGN format
  /// Accepts: e4, Nf3, O-O, exd5, Qh5+, f8=Q, etc.
  static bool isValidMove(String move) {
    // Pattern for valid moves in algebraic notation
    final pattern = RegExp(
      r'^[KQRBN]?[a-h]?[1-8]?[x@]?[a-h][1-8](?:=[QRBN])?[+#!?]*$|^O-O(?:-O)?[+#!?]*$',
    );
    return pattern.hasMatch(move);
  }

  /// Fix invalid moves with heuristics
  static String fixMove(String move) {
    String fixed = move.trim();

    // Remove spaces
    fixed = fixed.replaceAll(' ', '');

    // Convert figurine to algebraic
    fixed = convertFigurineToAlgebraic(fixed);

    // Normalize castling
    if (fixed.contains('O-O-O') || fixed.contains('0-0-0')) {
      fixed = 'O-O-O${RegExp(r'[+#!?]*').firstMatch(fixed)!.group(0)!}';
    }
    if (fixed.contains('O-O') || fixed.contains('0-0')) {
      fixed = 'O-O${RegExp(r'[+#!?]*').firstMatch(fixed)!.group(0)!}';
    }

    // Remove invalid characters
    fixed = fixed.replaceAll(RegExp(r'[^a-hKQRBN0-9x=+#!?\-O]'), '');

    return fixed;
  }

  /// Analyze a game and report issues
  static List<String> validateGame(ChessGame game) {
    final issues = <String>[];

    if (game.white.isEmpty) issues.add('White player missing');
    if (game.black.isEmpty) issues.add('Black player missing');
    if (game.moves.isEmpty) issues.add('No moves in game');

    for (int i = 0; i < game.moves.length; i++) {
      final move = game.moves[i];

      if (!isValidMove(move.white)) {
        issues.add('Invalid white move at line $i: "${move.white}"');
      }

      if (move.black != null && !isValidMove(move.black!)) {
        issues.add('Invalid black move at line $i: "${move.black}"');
      }
    }

    return issues;
  }

  /// Export all games to a single PGN file
  static Future<File> exportMultipleGamesPgn(
    ChessExtraction extraction,
    String outputPath, {
    bool includeComments = true,
    bool fixInvalidMoves = false,
  }) async {
    final file = File(outputPath);
    final sink = file.openWrite();

    for (int i = 0; i < extraction.games.length; i++) {
      var game = extraction.games[i];

      // Fix moves if necessary
      if (fixInvalidMoves) {
        game = _fixGameMoves(game);
      }

      // Add game
      sink.writeln(game.toPgn(includeComments: includeComments));
      sink.writeln();

      // Separator between games
      if (i < extraction.games.length - 1) {
        sink.writeln('\n');
      }
    }

    await sink.close();
    return file;
  }

  /// Export each game to separate files
  static Future<List<File>> exportIndividualGames(
    ChessExtraction extraction,
    String outputDirectory, {
    bool includeComments = true,
    bool fixInvalidMoves = false,
  }) async {
    final dir = Directory(outputDirectory);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final files = <File>[];

    for (int i = 0; i < extraction.games.length; i++) {
      var game = extraction.games[i];

      if (fixInvalidMoves) {
        game = _fixGameMoves(game);
      }

      final filename = _generateFilename(game, i + 1);
      final filePath = '${dir.path}/$filename';
      final file = File(filePath);

      await file.writeAsString(game.toPgn(includeComments: includeComments));

      files.add(file);
    }

    return files;
  }

  /// Generate filename for a game
  static String _generateFilename(ChessGame game, int index) {
    final whiteName = game.white
        .replaceAll(RegExp(r'[^a-zA-Z]'), '')
        .substring(0, 3)
        .toUpperCase();
    final blackName = game.black
        .replaceAll(RegExp(r'[^a-zA-Z]'), '')
        .substring(0, 3)
        .toUpperCase();
    final date = game.date?.replaceAll(RegExp(r'\D'), '') ?? 'ND';

    return '${index.toString().padLeft(2, '0')}_${whiteName}_vs_${blackName}_$date.pgn';
  }

  /// Fix invalid moves in a game
  static ChessGame _fixGameMoves(ChessGame game) {
    final fixedMoves = game.moves.map((move) {
      final fixedWhite = isValidMove(move.white)
          ? move.white
          : fixMove(move.white);
      final fixedBlack = move.black == null
          ? null
          : isValidMove(move.black!)
          ? move.black
          : fixMove(move.black!);

      return ChessMove(
        number: move.number,
        white: fixedWhite,
        black: fixedBlack,
        commentWhite: move.commentWhite,
        commentBlack: move.commentBlack,
        hasDiagram: move.hasDiagram,
      );
    }).toList();

    return ChessGame(
      white: game.white,
      black: game.black,
      date: game.date,
      event: game.event,
      site: game.site,
      eloWhite: game.eloWhite,
      eloBlack: game.eloBlack,
      result: game.result,
      startingPosition: game.startingPosition,
      page: game.page,
      gameNumber: game.gameNumber,
      moves: fixedMoves,
    );
  }

  /// Generate extraction report
  static String generateReport(ChessExtraction extraction) {
    final buffer = StringBuffer();
    buffer.writeln('╔════════════════════════════════════════╗');
    buffer.writeln('║     EXTRACTION REPORT                  ║');
    buffer.writeln('╚════════════════════════════════════════╝\n');

    buffer.writeln('Global statistics:');
    buffer.writeln('  • Total games: ${extraction.totalGames}');
    buffer.writeln('  • Total moves: ${extraction.totalMoves}');
    buffer.writeln(
      '  • Average moves/game: ${(extraction.totalMoves / extraction.totalGames).toStringAsFixed(1)}',
    );
    buffer.writeln();

    for (int i = 0; i < extraction.games.length; i++) {
      final game = extraction.games[i];
      final issues = validateGame(game);

      buffer.writeln('Game ${i + 1}: ${game.white} vs ${game.black}');
      buffer.writeln('  Page: ${game.page} | Moves: ${game.moves.length}');

      if (game.date != null) buffer.writeln('  Date: ${game.date}');

      if (issues.isEmpty) {
        buffer.writeln('  ✓ No issues detected');
      } else {
        buffer.writeln('  ⚠ Issues detected:');
        for (final issue in issues) {
          buffer.writeln('    - $issue');
        }
      }

      buffer.writeln();
    }

    return buffer.toString();
  }
}
