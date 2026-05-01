import 'package:chess_pdf_to_pgn/core/models/chess_game.dart';

enum PieceColor { white, black }

class ChessMove {
  final int moveNumber;
  final PieceColor color;
  final String san; // normalized english SAN move (ex: Nf3)
  final String? rawOcr; // raw OCR text before normalization
  final List<String> nags; // ex: ['$1', '$14']
  final String? commentBefore;
  final String? commentAfter;
  final List<ChessGame> variations; // variants subparts

  const ChessMove({
    required this.moveNumber,
    required this.color,
    required this.san,
    this.rawOcr,
    this.nags = const [],
    this.commentBefore,
    this.commentAfter,
    this.variations = const [],
  });
}
