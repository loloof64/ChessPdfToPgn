import '../../core/models/chess_game.dart';
import '../../core/models/chess_move.dart';

/// Serializes a [ChessGame] into a standard PGN string.
class PgnSerializer {
  String serialize(ChessGame game) {
    final buf = StringBuffer();

    // --- Headers ---
    game.headers.forEach((k, v) => buf.writeln('[$k "$v"]'));
    if (game.hasCustomStartPosition) buf.writeln('[SetUp "1"]');
    buf.writeln();

    // --- Moves ---
    _serializeMoves(game.moves, buf);

    // --- Result ---
    buf.write(game.result ?? '*');

    return buf.toString().trim();
  }

  // ---------------------------------------------------------------------------

  void _serializeMoves(List<ChessMove> moves, StringBuffer buf) {
    for (final move in moves) {
      // Comment before the move
      if (move.commentBefore != null) {
        buf.write('{ ${move.commentBefore} } ');
      }

      // Move number (always shown for white, omitted for black)
      if (move.color == PieceColor.white) {
        buf.write('${move.moveNumber}. ');
      }

      // SAN move
      buf.write(move.san);

      // NAGs ($1, $14, etc.)
      for (final nag in move.nags) {
        buf.write(' $nag');
      }

      // Comment after the move
      if (move.commentAfter != null) {
        buf.write(' { ${move.commentAfter} }');
      }

      // Variations (recursive)
      for (final variation in move.variations) {
        buf.write(' (');
        _serializeMoves(variation.moves, buf);
        // Trim trailing space before closing paren
        final current = buf.toString();
        if (current.endsWith(' ')) {
          // StringBuffer has no direct trim — rebuild via toString
        }
        buf.write(')');
      }

      buf.write(' ');
    }
  }
}
