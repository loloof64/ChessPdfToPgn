import 'package:chess/chess.dart' as ch;
import 'package:flutter/cupertino.dart';
import '../../core/models/chess_game.dart';
import '../../core/models/chess_move.dart';

// ---------------------------------------------------------------------------
// Validation result
// ---------------------------------------------------------------------------

/// Result of a full game validation.
class ValidationResult {
  final List<ChessMove> validMoves;
  final List<InvalidMove> invalidMoves;
  final String finalFen;

  bool get isFullyValid => invalidMoves.isEmpty;
  double get accuracy {
    final total = validMoves.length + invalidMoves.length;
    return total == 0 ? 1.0 : validMoves.length / total;
  }

  const ValidationResult({
    required this.validMoves,
    required this.invalidMoves,
    required this.finalFen,
  });
}

/// A move that failed validation, with the reason and suggested correction.
class InvalidMove {
  final ChessMove move;
  final String reason;
  final String? suggestion;

  const InvalidMove({
    required this.move,
    required this.reason,
    this.suggestion,
  });
}

// ---------------------------------------------------------------------------
// MoveValidator
// ---------------------------------------------------------------------------

/// Validates a [ChessGame] by replaying all moves through the chess engine.
class MoveValidator {
  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  ValidationResult validate(ChessGame game) {
    final chess = ch.Chess();

    // Load custom start position if present
    if (game.hasCustomStartPosition) {
      final fen = game.headers['FEN']!;
      final fenParts = fen.trim().split(' ');

      if (fenParts.length != 6) {
        return ValidationResult(
          validMoves: [],
          invalidMoves: game.moves
              .map(
                (m) => InvalidMove(
                  move: m,
                  reason: 'Invalid FEN: must have 6 space-delimited fields',
                ),
              )
              .toList(),
          finalFen: '',
        );
      }

      final loaded = chess.load(fen);
      if (!loaded) {
        return ValidationResult(
          validMoves: [],
          invalidMoves: game.moves
              .map((m) => InvalidMove(move: m, reason: 'Invalid FEN: $fen'))
              .toList(),
          finalFen: '',
        );
      }
    }
    // else: chess stays at default starting position

    final validMoves = <ChessMove>[];
    final invalidMoves = <InvalidMove>[];

    for (final move in game.moves) {
      final result = _tryMove(chess, move.san);

      if (result != null) {
        validMoves.add(
          ChessMove(
            moveNumber: move.moveNumber,
            color: move.color,
            san: result,
            rawOcr: move.rawOcr,
            nags: move.nags,
            commentBefore: move.commentBefore,
            commentAfter: move.commentAfter,
            variations: _validateVariations(move.variations, chess.fen),
          ),
        );
      } else {
        final corrected = _attemptCorrection(chess, move.san);

        if (corrected != null) {
          _tryMove(chess, corrected);
          validMoves.add(
            ChessMove(
              moveNumber: move.moveNumber,
              color: move.color,
              san: corrected,
              rawOcr: move.rawOcr,
              nags: move.nags,
              commentBefore: move.commentBefore,
              commentAfter: move.commentAfter,
              variations: _validateVariations(move.variations, chess.fen),
            ),
          );
          invalidMoves.add(
            InvalidMove(
              move: move,
              reason: 'OCR error corrected',
              suggestion: corrected,
            ),
          );
        } else {
          invalidMoves.add(
            InvalidMove(
              move: move,
              reason: 'Illegal move — no correction found',
            ),
          );
        }
      }
    }

    return ValidationResult(
      validMoves: validMoves,
      invalidMoves: invalidMoves,
      finalFen: chess.fen,
    );
  }

  // ---------------------------------------------------------------------------
  // Private — move attempt
  // ---------------------------------------------------------------------------

  String? _tryMove(ch.Chess chess, String san) {
    final result = chess.move(san);
    if (!result) return null;
    return san;
  }

  // ---------------------------------------------------------------------------
  // Private — variation validation
  // ---------------------------------------------------------------------------

  List<ChessGame> _validateVariations(
    List<ChessGame> variations,
    String fenBefore,
  ) {
    if (variations.isEmpty) return const [];

    return variations.map((variation) {
      final tempGame = ChessGame(
        headers: {...variation.headers, 'FEN': fenBefore},
        moves: variation.moves,
        result: variation.result,
      );
      final result = validate(tempGame);
      return ChessGame(
        headers: variation.headers,
        moves: result.validMoves,
        result: variation.result,
      );
    }).toList();
  }

  // ---------------------------------------------------------------------------
  // Private — OCR correction
  // ---------------------------------------------------------------------------

  String? _attemptCorrection(ch.Chess chess, String san) {
    // Fix cast: chess.moves() returns List<dynamic>
    final legal = chess
        .moves({'verbose': false})
        .map((m) => m.toString())
        .toList();

    // DEBUG
    debugPrint('  Attempting correction for: $san');
    debugPrint('  Legal moves: $legal');

    if (legal.isEmpty) return null;

    final candidates = _generateCandidates(san);
    for (final candidate in candidates) {
      if (legal.contains(candidate)) return candidate;
    }

    String? bestMove;
    double bestScore = 0.0;
    for (final legalMove in legal) {
      final score = _similarity(san, legalMove);
      if (score > bestScore) {
        bestScore = score;
        bestMove = legalMove;
      }
    }

    return bestScore > 0.6 ? bestMove : null;
  }

  List<String> _generateCandidates(String san) {
    final candidates = <String>{san};

    const substitutions = <String, List<String>>{
      '0': ['O'],
      'O': ['0'],
      'l': ['1'],
      '1': ['l'],
      'I': ['1'],
      'B': ['8'],
      '8': ['B'],
      'S': ['5'],
      'G': ['6'],
    };

    for (final entry in substitutions.entries) {
      if (san.contains(entry.key)) {
        for (final replacement in entry.value) {
          candidates.add(san.replaceAll(entry.key, replacement));
        }
      }
    }

    candidates.add(san.replaceAll('0-0-0', 'O-O-O'));
    candidates.add(san.replaceAll('0-0', 'O-O'));
    candidates.add(san.replaceAll('+', '').replaceAll('#', ''));
    if (san.contains('=')) {
      candidates.add(san.split('=').first);
    }

    return candidates.toList();
  }

  double _similarity(String a, String b) {
    if (a == b) return 1.0;
    if (a.isEmpty || b.isEmpty) return 0.0;

    final longer = a.length > b.length ? a : b;
    final shorter = a.length > b.length ? b : a;

    var matches = 0;
    for (var i = 0; i < shorter.length; i++) {
      if (i < longer.length && shorter[i] == longer[i]) matches++;
    }
    return matches / longer.length;
  }
}
