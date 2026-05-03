import 'package:flutter_test/flutter_test.dart';
import 'package:chess_pdf_to_pgn/core/models/game_extraction_config.dart';
import 'package:chess_pdf_to_pgn/core/models/chess_move.dart';
import 'package:chess_pdf_to_pgn/features/processing/pgn_parser.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  PgnParser parserFor({
    NotationLocale locale = NotationLocale.english,
    bool usesFigurine = false,
    CommentStyle commentStyle = CommentStyle.braces,
  }) {
    return PgnParser(
      GameExtractionConfig(
        locale: locale,
        usesFigurine: usesFigurine,
        commentStyle: commentStyle,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Basic move parsing
  // ---------------------------------------------------------------------------

  group('Basic move parsing', () {
    test('parses a simple sequence of moves', () {
      final game = parserFor().parse('1. e4 e5 2. Nf3 Nc6 3. Bb5');

      expect(game.moves.length, 5);
      expect(game.moves[0].san, 'e4');
      expect(game.moves[0].moveNumber, 1);
      expect(game.moves[0].color, PieceColor.white);
      expect(game.moves[1].san, 'e5');
      expect(game.moves[1].color, PieceColor.black);
      expect(game.moves[4].san, 'Bb5');
      expect(game.moves[4].moveNumber, 3);
    });

    test('parses castling moves', () {
      final game = parserFor().parse('1. e4 e5 2. O-O O-O-O');

      expect(game.moves[2].san, 'O-O');
      expect(game.moves[3].san, 'O-O-O');
    });

    test('parses promotion', () {
      final game = parserFor().parse('1. e8=Q');
      expect(game.moves[0].san, 'e8=Q');
    });

    test('parses check and checkmate symbols', () {
      final game = parserFor().parse('1. Qh5+ Ke7 2. Qxf7#');
      expect(game.moves[0].san, 'Qh5+');
      expect(game.moves[2].san, 'Qxf7#');
    });

    test('parses captures', () {
      final game = parserFor().parse('1. e4 d5 2. exd5');
      expect(game.moves[2].san, 'exd5');
    });

    test('parses game result', () {
      final game = parserFor().parse('1. e4 e5 1-0');
      expect(game.result, '1-0');
    });

    test('parses all result types', () {
      expect(parserFor().parse('1. e4 1-0').result, '1-0');
      expect(parserFor().parse('1. e4 0-1').result, '0-1');
      expect(parserFor().parse('1. e4 1/2-1/2').result, '1/2-1/2');
      expect(parserFor().parse('1. e4 *').result, '*');
    });

    test('handles black move indicator (1...)', () {
      final game = parserFor().parse('1... e5 2. Nf3');
      expect(game.moves[0].color, PieceColor.black);
      expect(game.moves[0].moveNumber, 1);
      expect(game.moves[1].color, PieceColor.white);
    });
  });

  // ---------------------------------------------------------------------------
  // FAN notation
  // ---------------------------------------------------------------------------

  group('FAN notation', () {
    test('normalizes FAN glyphs to SAN', () {
      final game = parserFor(usesFigurine: true).parse('1. ♘f3 ♞c6');
      expect(game.moves[0].san, 'Nf3');
      expect(game.moves[1].san, 'Nc6');
    });

    test('normalizes all FAN piece types', () {
      final game = parserFor(
        usesFigurine: true,
      ).parse('1. ♔e1 ♚e8 2. ♕d1 ♛d8 3. ♖a1 ♜a8 4. ♗c1 ♝c8 5. ♘b1 ♞b8');
      expect(game.moves[0].san, 'Ke1');
      expect(game.moves[2].san, 'Qd1');
      expect(game.moves[4].san, 'Ra1');
      expect(game.moves[6].san, 'Bc1');
      expect(game.moves[8].san, 'Nb1');
    });
  });

  // ---------------------------------------------------------------------------
  // Locale normalization
  // ---------------------------------------------------------------------------

  group('Locale normalization', () {
    test('normalizes French notation', () {
      final game = parserFor(
        locale: NotationLocale.french,
      ).parse('1. e4 e5 2. Cf3 Cc6 3. Fb5');
      expect(game.moves[2].san, 'Nf3');
      expect(game.moves[3].san, 'Nc6');
      expect(game.moves[4].san, 'Bb5');
    });

    test('normalizes German notation', () {
      final game = parserFor(
        locale: NotationLocale.german,
      ).parse('1. e4 e5 2. Sf3 Sc6 3. Lb5');
      expect(game.moves[2].san, 'Nf3');
      expect(game.moves[3].san, 'Nc6');
      expect(game.moves[4].san, 'Bb5');
    });

    test('normalizes Spanish notation', () {
      final game = parserFor(
        locale: NotationLocale.spanish,
      ).parse('1. e4 e5 2. Cf3 Cc6 3. Ab5');
      expect(game.moves[2].san, 'Nf3');
      expect(game.moves[4].san, 'Bb5');
    });
  });

  // ---------------------------------------------------------------------------
  // Annotations (NAG)
  // ---------------------------------------------------------------------------

  group('Annotations', () {
    test('parses single annotation', () {
      final game = parserFor().parse('1. e4! e5?');
      expect(game.moves[0].nags, [r'$1']);
      expect(game.moves[1].nags, [r'$2']);
    });

    test('parses double annotations', () {
      final game = parserFor().parse('1. e4!! e5??');
      expect(game.moves[0].nags, [r'$3']);
      expect(game.moves[1].nags, [r'$4']);
    });

    test('parses combined annotation and comment', () {
      final game = parserFor().parse('1. e4!? { interesting }');
      expect(game.moves[0].nags, [r'$5']);
      expect(game.moves[0].commentAfter, 'interesting');
    });

    test('parses zugzwang symbol', () {
      final game = parserFor().parse('1. e4⊙');
      expect(game.moves[0].nags, contains(r'$22'));
    });

    test('parses evaluation symbols', () {
      final game = parserFor().parse('1. e4 e5± 2. Nf3 Nc6∞');
      expect(game.moves[1].nags, contains(r'$14'));
      expect(game.moves[3].nags, contains(r'$13'));
    });
  });

  // ---------------------------------------------------------------------------
  // Comments — delimited
  // ---------------------------------------------------------------------------

  group('Delimited comments', () {
    test('attaches brace comment after move', () {
      final game = parserFor().parse('1. e4 { good move } e5');
      expect(game.moves[0].commentAfter, 'good move');
    });

    test('attaches brace comment before move', () {
      final game = parserFor().parse('1. e4 { opening comment } e5');
      // Comment AFTER e4, before e5
      expect(game.moves[0].commentAfter, 'opening comment');
    });

    test('comment between move number and move becomes commentBefore', () {
      // This is an edge case — comment parser attaches it as commentBefore
      // when it appears after a move number but before the move itself
      final game = parserFor().parse('1. { before } e4 e5');
      expect(game.moves[0].commentBefore, 'before');
    });

    test('stores pre-game comment in header', () {
      final game = parserFor().parse('{ Sicilian Defence } 1. e4 c5');
      expect(game.headers['Comment'], 'Sicilian Defence');
      expect(game.moves[0].commentBefore, isNull);
    });

    test('merges consecutive comments', () {
      final game = parserFor().parse('1. e4 { first } { second }');
      expect(game.moves[0].commentAfter, 'first second');
    });

    test('stores comment after result', () {
      final game = parserFor().parse('1. e4 e5 1-0 { White wins }');
      expect(game.headers['CommentAfterResult'], 'White wins');
    });

    test('parses parenthesis comment with parentheses style', () {
      final game = parserFor(
        commentStyle: CommentStyle.parentheses,
      ).parse('1. e4 (good move) e5');
      expect(game.moves[0].commentAfter, 'good move');
    });
  });

  // ---------------------------------------------------------------------------
  // Comments — paragraph style
  // ---------------------------------------------------------------------------

  group('Paragraph comments', () {
    test('converts paragraph without moves to comment', () {
      const input = '''
1. e4 e5

This is a classic opening that has been played for centuries.

2. Nf3 Nc6
''';
      final game = parserFor().parse(input);
      // The paragraph should be attached as a comment
      final hasComment = game.moves.any(
        (m) =>
            (m.commentAfter != null && m.commentAfter!.contains('classic')) ||
            (m.commentBefore != null && m.commentBefore!.contains('classic')),
      );
      expect(hasComment, isTrue);
    });

    test('does not convert paragraph with moves to comment', () {
      const input = '''
1. e4 e5
2. Nf3 Nc6
''';
      final game = parserFor().parse(input);
      expect(game.moves.length, 4);
    });
  });

  // ---------------------------------------------------------------------------
  // Bracket comments
  // ---------------------------------------------------------------------------

  group('Bracket comments', () {
    test('treats bracket content as comment in move flow', () {
      final game = parserFor().parse('1. e4 [see diagram] e5');
      expect(game.moves[0].commentAfter, 'see diagram');
    });

    test('does not treat PGN headers as comments', () {
      final game = parserFor().parse('[Event "Test"]\n[Site "?"]\n1. e4 e5');
      // Headers should not appear as move comments
      expect(game.moves[0].commentBefore, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // Variations
  // ---------------------------------------------------------------------------

  group('Variations', () {
    test('parses a simple variation', () {
      final game = parserFor().parse('1. e4 e5 2. Nf3 (2. f4 exf4) 2... Nc6');
      expect(game.moves[2].san, 'Nf3');
      expect(game.moves[2].variations.length, 1);
      expect(game.moves[2].variations[0].moves[0].san, 'f4');
    });

    test('parses nested variations', () {
      final game = parserFor().parse(
        '1. e4 e5 2. Nf3 (2. f4 (2. d4 d5) exf4) 2... Nc6',
      );
      final variation = game.moves[2].variations[0];
      expect(variation.moves[0].san, 'f4');
      expect(variation.moves[0].variations.isNotEmpty, isTrue);
      expect(variation.moves[0].variations[0].moves[0].san, 'd4');
    });

    test('parses multiple variations on same move', () {
      final game = parserFor().parse(
        '1. e4 e5 2. Nf3 (2. f4) (2. d4) 2... Nc6',
      );
      expect(game.moves[2].variations.length, 2);
    });

    test('variation does not affect main line move count', () {
      final game = parserFor().parse(
        '1. e4 e5 2. Nf3 (2. f4 exf4 3. Nf3) 2... Nc6 3. Bb5',
      );
      expect(game.moves.length, 5);
    });
  });

  // ---------------------------------------------------------------------------
  // Edge cases
  // ---------------------------------------------------------------------------

  group('Edge cases', () {
    test('returns empty moves for empty input', () {
      final game = parserFor().parse('');
      expect(game.moves, isEmpty);
    });

    test('returns empty moves for comment-only input', () {
      final game = parserFor().parse('{ just a comment }');
      expect(game.moves, isEmpty);
      expect(game.headers['Comment'], 'just a comment');
    });

    test('handles missing move numbers gracefully', () {
      final game = parserFor().parse('e4 e5 Nf3');
      expect(game.moves.isNotEmpty, isTrue);
    });

    test('preserves rawOcr on each move', () {
      final game = parserFor().parse('1. e4 e5');
      expect(game.moves[0].rawOcr, 'e4');
    });
  });
}
