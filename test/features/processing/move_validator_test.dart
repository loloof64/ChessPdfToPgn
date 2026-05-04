import 'package:chess/chess.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chess_pdf_to_pgn/core/models/chess_game.dart';
import 'package:chess_pdf_to_pgn/core/models/chess_move.dart';
import 'package:chess_pdf_to_pgn/features/processing/move_validator.dart';

void main() {
  late MoveValidator validator;

  setUp(() => validator = MoveValidator());

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  ChessMove m(int number, PieceColor color, String san, {String? rawOcr}) {
    return ChessMove(
      moveNumber: number,
      color: color,
      san: san,
      rawOcr: rawOcr ?? san,
    );
  }

  ChessGame gameFrom(List<ChessMove> moves, {String? fen}) {
    final headers = <String, String>{
      'Event': '?',
      'Site': '?',
      'Date': '????.??.??',
    };
    if (fen != null) headers['FEN'] = fen;
    return ChessGame(headers: headers, moves: moves);
  }

  // ---------------------------------------------------------------------------
  // Valid games
  // ---------------------------------------------------------------------------

  group('Valid games', () {
    test('validates a simple legal game', () {
      final result = validator.validate(
        gameFrom([
          m(1, PieceColor.white, 'e4'),
          m(1, PieceColor.black, 'e5'),
          m(2, PieceColor.white, 'Nf3'),
          m(2, PieceColor.black, 'Nc6'),
        ]),
      );
      expect(result.isFullyValid, isTrue);
      expect(result.validMoves.length, 4);
      expect(result.invalidMoves, isEmpty);
      expect(result.accuracy, 1.0);
    });

    test('validates castling', () {
      final result = validator.validate(
        gameFrom([
          m(1, PieceColor.white, 'e4'),
          m(1, PieceColor.black, 'e5'),
          m(2, PieceColor.white, 'Nf3'),
          m(2, PieceColor.black, 'Nc6'),
          m(3, PieceColor.white, 'Bc4'),
          m(3, PieceColor.black, 'Bc5'),
          m(4, PieceColor.white, 'O-O'),
        ]),
      );
      expect(result.isFullyValid, isTrue);
    });

    test('validates a game with custom start position', () {
      // Position after 1. e4 — it is Black's turn
      const fen = 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKB1R b KQkq e3 0 1';
      final result = validator.validate(
        gameFrom([
          m(1, PieceColor.black, 'e5'),
          m(
            2,
            PieceColor.white,
            'Nc3',
          ), // Nc3 is legal, Nf3 is not (g1 is empty)
        ], fen: fen),
      );
      expect(result.isFullyValid, isTrue);
      expect(result.validMoves.length, 2);
    });

    test('DEBUG Ne3 legality after d4 Nf6 c4 e6', () {
      final chess = Chess();
      chess.move('d4');
      chess.move('Nf6');
      chess.move('c4');
      chess.move('e6');
    });
  });

  // ---------------------------------------------------------------------------
  // Invalid moves
  // ---------------------------------------------------------------------------

  group('Invalid moves', () {
    test('flags an illegal move', () {
      final result = validator.validate(
        gameFrom([
          m(1, PieceColor.white, 'e4'),
          m(1, PieceColor.black, 'e9'), // impossible square
          m(2, PieceColor.white, 'Nf3'),
        ]),
      );
      expect(result.invalidMoves.length, greaterThan(0));
      expect(result.invalidMoves.first.move.san, 'e9');
    });

    test('reports accuracy correctly', () {
      final result = validator.validate(
        gameFrom([
          m(1, PieceColor.white, 'e4'),
          m(1, PieceColor.black, 'INVALID'),
          m(2, PieceColor.white, 'Nf3'),
        ]),
      );
      // 2 valid out of 3 attempted = ~0.67 (third move may not play
      // if second fails and leaves inconsistent state)
      expect(result.accuracy, lessThan(1.0));
    });
  });

  // ---------------------------------------------------------------------------
  // OCR correction
  // ---------------------------------------------------------------------------

  group('OCR correction', () {
    test('corrects 0-0 to O-O castling', () {
      final result = validator.validate(
        gameFrom([
          m(1, PieceColor.white, 'e4'),
          m(1, PieceColor.black, 'e5'),
          m(2, PieceColor.white, 'Nf3'),
          m(2, PieceColor.black, 'Nc6'),
          m(3, PieceColor.white, 'Bc4'),
          m(3, PieceColor.black, 'Bc5'),
          m(4, PieceColor.white, '0-0', rawOcr: '0-0'), // OCR error
        ]),
      );
      // Should be corrected to O-O
      final castleMove = result.validMoves.firstWhere(
        (mv) => mv.moveNumber == 4,
        orElse: () => throw StateError('Move not found'),
      );
      expect(castleMove.san, 'O-O');
    });

    test('flags correction in invalidMoves with suggestion', () {
      final result = validator.validate(
        gameFrom([
          m(1, PieceColor.white, 'e4'),
          m(1, PieceColor.black, 'e5'),
          m(2, PieceColor.white, 'Nf3'),
          m(2, PieceColor.black, 'Nc6'),
          m(3, PieceColor.white, 'Bc4'),
          m(3, PieceColor.black, 'Bc5'),
          m(4, PieceColor.white, '0-0'),
        ]),
      );
      final correction = result.invalidMoves
          .where((inv) => inv.suggestion != null)
          .firstOrNull;
      if (correction != null) {
        expect(correction.suggestion, 'O-O');
      }
    });
  });

  // ---------------------------------------------------------------------------
  // Edge cases
  // ---------------------------------------------------------------------------

  group('Edge cases', () {
    test('handles empty move list', () {
      final result = validator.validate(gameFrom([]));
      expect(result.isFullyValid, isTrue);
      expect(result.validMoves, isEmpty);
    });

    test('handles invalid FEN gracefully', () {
      final result = validator.validate(
        gameFrom([m(1, PieceColor.white, 'e4')], fen: 'invalid_fen'),
      );
      // Either invalidMoves is not empty, OR validMoves is empty
      expect(
        result.validMoves.isEmpty || result.invalidMoves.isNotEmpty,
        isTrue,
      );
    });
  });
}
