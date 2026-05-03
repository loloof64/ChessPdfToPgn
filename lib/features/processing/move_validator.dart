import 'package:chess/chess.dart' as ch;
import '../../core/models/chess_game.dart';
import '../../core/models/chess_move.dart';

// ---------------------------------------------------------------------------
// Validation result
// ---------------------------------------------------------------------------

/// Result of a full game validation.
class ValidationResult {
  /// Moves that were successfully played on the chess engine.
  final List<ChessMove> validMoves;

  /// Moves rejected by the chess engine (illegal or OCR errors).
  final List<InvalidMove> invalidMoves;

  /// FEN position after the last valid move.
  final String finalFen;

  /// True if all moves in the game are legal.
  bool get isFullyValid => invalidMoves.isEmpty;

  /// Ratio of valid moves to total moves (0.0 → 1.0).
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
  final String? suggestion; // best-guess corrected SAN, if any

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
///
/// Uses chess.dart to verify move legality, detect OCR errors,
/// and attempt automatic correction of common mistakes.
class MoveValidator {
  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Validates all moves in [game] and returns a [ValidationResult].
  ///
  /// If [game] has a custom start position (FEN header), the engine
  /// is initialized from that position instead of the standard one.
  ValidationResult validate(ChessGame game) {
    final chess = ch.Chess();

    // Load custom start position if present
    if (game.hasCustomStartPosition) {
      final fen = game.headers['FEN']!;
      final loaded = chess.load(fen);
      if (!loaded) {
        return ValidationResult(
          validMoves: [],
          invalidMoves: game.moves
              .map(
                (m) => InvalidMove(
                  move: m,
                  reason: 'Invalid start position FEN: $fen',
                ),
              )
              .toList(),
          finalFen: chess.fen,
        );
      }
    }

    final validMoves = <ChessMove>[];
    final invalidMoves = <InvalidMove>[];

    for (final move in game.moves) {
      // Skip moves from variations — they are validated recursively
      final result = _tryMove(chess, move.san);

      if (result != null) {
        // Move accepted by engine
        validMoves.add(
          ChessMove(
            moveNumber: move.moveNumber,
            color: move.color,
            san: result, // use engine-normalized SAN
            rawOcr: move.rawOcr,
            nags: move.nags,
            commentBefore: move.commentBefore,
            commentAfter: move.commentAfter,
            variations: _validateVariations(move.variations, chess.fen),
          ),
        );
      } else {
        // Move rejected — attempt correction
        final corrected = _attemptCorrection(chess, move.san);

        if (corrected != null) {
          // Correction found — play the corrected move
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
          // No correction found — flag and skip
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

  /// Tries to play [san] on [chess].
  /// Returns the engine-normalized SAN if successful, null otherwise.
  String? _tryMove(ch.Chess chess, String san) {
    final success = chess.move(san);
    if (!success) return null;
    // chess.dart matches by exact SAN, so the input is already normalized
    return san;
  }

  // ---------------------------------------------------------------------------
  // Private — variation validation
  // ---------------------------------------------------------------------------

  /// Recursively validates all variations of a move.
  /// Each variation starts from [fenBefore] — the position before the move.
  List<ChessGame> _validateVariations(
    List<ChessGame> variations,
    String fenBefore,
  ) {
    if (variations.isEmpty) return const [];

    return variations.map((variation) {
      // Create a temporary game with the pre-move position
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

  /// Attempts to correct common OCR mistakes in [san].
  ///
  /// Tries all legal moves in the current position and returns the one
  /// whose SAN most closely resembles the OCR output.
  String? _attemptCorrection(ch.Chess chess, String san) {
    final legal = chess.moves({'verbose': false}) as List<String>;
    if (legal.isEmpty) return null;

    // Step 1 — Apply chess-specific substitutions first
    final candidates = _generateCandidates(san);

    for (final candidate in candidates) {
      if (legal.contains(candidate)) return candidate;
    }

    // Step 2 — Find the legal move with the highest similarity score
    String? bestMove;
    double bestScore = 0.0;

    for (final legalMove in legal) {
      final score = _similarity(san, legalMove);
      if (score > bestScore) {
        bestScore = score;
        bestMove = legalMove;
      }
    }

    // Only suggest if similarity is high enough (> 0.6)
    return bestScore > 0.6 ? bestMove : null;
  }

  /// Generates candidate corrections by applying common OCR substitutions.
  List<String> _generateCandidates(String san) {
    final candidates = <String>{san};

    // Common OCR confusions specific to chess notation
    const substitutions = <String, List<String>>{
      '0': ['O'], // castling: 0-0 → O-O
      'O': ['0'],
      'l': ['1'], // l vs 1
      '1': ['l'],
      'I': ['1'], // capital I vs 1
      'B': ['8'], // B vs 8 (bishop vs rank)
      '8': ['B'],
      'S': ['5'], // S vs 5
      'G': ['6'], // G vs 6
    };

    for (final entry in substitutions.entries) {
      if (san.contains(entry.key)) {
        for (final replacement in entry.value) {
          candidates.add(san.replaceAll(entry.key, replacement));
        }
      }
    }

    // Castling normalization
    candidates.add(san.replaceAll('0-0-0', 'O-O-O'));
    candidates.add(san.replaceAll('0-0', 'O-O'));

    // Remove trailing check/checkmate symbols (sometimes misread)
    candidates.add(san.replaceAll('+', '').replaceAll('#', ''));

    // Strip promotion suffix (misread promotion)
    if (san.contains('=')) {
      candidates.add(san.split('=').first);
    }

    return candidates.toList();
  }

  /// Computes a simple character-overlap similarity score between [a] and [b].
  /// Returns a value between 0.0 (no overlap) and 1.0 (identical).
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
