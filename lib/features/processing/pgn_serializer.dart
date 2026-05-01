import '../../core/models/chess_game.dart';
import '../../core/models/chess_move.dart';

class PgnSerializer {
  String serialize(ChessGame game) {
    final buf = StringBuffer();

    // Headers
    game.headers.forEach((k, v) => buf.writeln('[$k "$v"]'));
    if (game.hasCustomStartPosition) buf.writeln('[SetUp "1"]');
    buf.writeln();

    // Moves
    for (final move in game.moves) {
      if (move.commentBefore != null) {
        buf.write('{ ${move.commentBefore} } ');
      }
      if (move.color == PieceColor.white) {
        buf.write('${move.moveNumber}. ');
      }
      buf.write(move.san);
      for (final nag in move.nags) {
        buf.write(' $nag');
      }
      if (move.commentAfter != null) {
        buf.write(' { ${move.commentAfter} }');
      }
      for (final variation in move.variations) {
        buf.write(' (${_serializeMoves(variation.moves)})');
      }
      buf.write(' ');
    }

    buf.write(game.result ?? '*');
    return buf.toString().trim();
  }

  String _serializeMoves(List<ChessMove> moves) {
    final buf = StringBuffer();
    for (final move in moves) {
      if (move.color == PieceColor.white) buf.write('${move.moveNumber}. ');
      buf.write(move.san);
      for (final nag in move.nags) {
        buf.write(' $nag');
      }
      if (move.commentAfter != null) buf.write(' { ${move.commentAfter} }');
      buf.write(' ');
    }
    return buf.toString().trim();
  }
}
