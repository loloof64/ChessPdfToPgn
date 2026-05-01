import 'chess_move.dart';

class ChessGame {
  final Map<String, String> headers; // PGN keys : Event, Site, FEN, SetUp...
  final List<ChessMove> moves;
  final String? result; // '1-0' | '0-1' | '1/2-1/2' | '*'

  const ChessGame({required this.headers, required this.moves, this.result});

  bool get hasCustomStartPosition => headers.containsKey('FEN');
}
