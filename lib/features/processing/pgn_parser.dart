import '../../core/models/game_extraction_config.dart';
import '../../core/models/chess_move.dart';
import '../../core/models/chess_game.dart';
import 'fan_normalizer.dart';
import 'piece_localizer.dart';
import 'annotation_parser.dart';

/// Parses raw OCR text into a [ChessGame].
///
/// Comment attachment rules:
///   - Comment before any move       → stored in [ChessGame.headers] as 'Comment'
///   - Comment immediately after a move → stored as [ChessMove.commentAfter]
///   - Comment immediately before a move → stored as [ChessMove.commentBefore]
///   - Two consecutive comments      → merged with a space separator
///   - Comment after the result      → stored in [ChessGame.headers] as 'CommentAfterResult'
///
/// Variation rules:
///   - Variations are parsed recursively into [ChessMove.variations]
///   - Variations can be nested to any depth
///   - The position context (move number + color) is inferred from the
///     variation content itself, not from the parent game state
class PgnParser {
  final GameExtractionConfig config;
  late final PieceLocalizer _localizer;

  PgnParser(this.config) {
    _localizer = PieceLocalizer(config.locale);
  }

  // ---------------------------------------------------------------------------
  // Public entry point
  // ---------------------------------------------------------------------------

  ChessGame parse(String rawOcr) => _parseTokens(_tokenize(rawOcr));

  // ---------------------------------------------------------------------------
  // Core parser — shared by main game and recursive variation calls
  // ---------------------------------------------------------------------------

  /// Parses a flat list of tokens into a [ChessGame].
  /// Used both for the main game and for each variation recursively.
  ChessGame _parseTokens(List<_Token> tokens) {
    final moves = <ChessMove>[];
    final headers = <String, String>{
      'Event': '?',
      'Site': '?',
      'Date': '????.??.??',
    };

    int moveNumber = 1;
    PieceColor color = PieceColor.white;
    String? pendingComment;
    bool gameStarted = false;
    bool resultSeen = false;

    for (final token in tokens) {
      switch (token.type) {
        // --------------------------------------------------------------------
        case _TokenType.comment:
          final text = token.value;

          if (resultSeen) {
            // Comment after result
            final existing = headers['CommentAfterResult'];
            headers['CommentAfterResult'] = _merge(existing, text)!;
            break;
          }

          if (!gameStarted) {
            // Comment before first move → header comment
            headers['Comment'] = _merge(headers['Comment'], text)!;
            break;
          }

          // Attach as commentAfter to the last parsed move (merge if needed)
          if (moves.isNotEmpty) {
            final last = moves.removeLast();
            moves.add(
              ChessMove(
                moveNumber: last.moveNumber,
                color: last.color,
                san: last.san,
                rawOcr: last.rawOcr,
                nags: last.nags,
                commentBefore: last.commentBefore,
                commentAfter: _merge(last.commentAfter, text),
                variations: last.variations,
              ),
            );
          } else {
            pendingComment = _merge(pendingComment, text);
          }

        // --------------------------------------------------------------------
        case _TokenType.moveNumber:
          moveNumber = int.parse(
            token.value.replaceAll(RegExp(r'\.+'), '').trim(),
          );
          // '1...' indicates a black move
          color = token.value.contains('...')
              ? PieceColor.black
              : PieceColor.white;

        // --------------------------------------------------------------------
        case _TokenType.move:
          gameStarted = true;

          final raw = token.value;
          final withNags = AnnotationParser.extract(raw);
          final san = _normalizePiece(withNags.clean);

          moves.add(
            ChessMove(
              moveNumber: moveNumber,
              color: color,
              san: san,
              rawOcr: raw,
              nags: withNags.nags,
              commentBefore: pendingComment,
              commentAfter: null,
              variations: const [],
            ),
          );
          pendingComment = null;

          if (color == PieceColor.white) {
            color = PieceColor.black;
          } else {
            moveNumber++;
            color = PieceColor.white;
          }

        // --------------------------------------------------------------------
        case _TokenType.variation:
          // Parse variation content recursively, then attach to the last move
          if (moves.isEmpty) break; // variation before any move — ignore

          final variationGame = _parseTokens(_tokenize(token.value));

          // Attach the variation to the last parsed move
          final last = moves.removeLast();
          moves.add(
            ChessMove(
              moveNumber: last.moveNumber,
              color: last.color,
              san: last.san,
              rawOcr: last.rawOcr,
              nags: last.nags,
              commentBefore: last.commentBefore,
              commentAfter: last.commentAfter,
              variations: [...last.variations, variationGame],
            ),
          );

        // --------------------------------------------------------------------
        case _TokenType.result:
          resultSeen = true;
      }
    }

    // Leftover pending comment → header comment
    if (pendingComment != null) {
      headers['Comment'] = _merge(headers['Comment'], pendingComment)!;
    }

    final result = _extractResult(
      tokens.where((t) => t.type == _TokenType.result).firstOrNull?.value,
    );
    if (result != null) headers['Result'] = result;

    return ChessGame(headers: headers, moves: moves, result: result);
  }

  // ---------------------------------------------------------------------------
  // Tokenizer
  // ---------------------------------------------------------------------------

  List<_Token> _tokenize(String text) {
    final tokens = <_Token>[];
    var i = 0;

    while (i < text.length) {
      final ch = text[i];

      // Whitespace
      if (ch == ' ' || ch == '\n' || ch == '\r' || ch == '\t') {
        i++;
        continue;
      }

      // Comment { ... }
      if (ch == '{') {
        final end = text.indexOf('}', i + 1);
        if (end != -1) {
          tokens.add(
            _Token(_TokenType.comment, text.substring(i + 1, end).trim()),
          );
          i = end + 1;
          continue;
        }
      }

      // Parenthesis block ( ... ) — variation or comment depending on content
      if (ch == '(') {
        final end = _findMatchingParen(text, i);
        if (end != -1) {
          final content = text.substring(i + 1, end).trim();

          // Heuristic: starts with a digit → variation ; otherwise → comment
          // (applies only when commentStyle allows parentheses)
          final looksLikeVariation = RegExp(r'^\d').hasMatch(content);

          if (!looksLikeVariation &&
              (config.commentStyle == CommentStyle.parentheses ||
                  config.commentStyle == CommentStyle.mixed)) {
            tokens.add(_Token(_TokenType.comment, content));
          } else {
            // Variation — raw content is kept, parsed recursively later
            tokens.add(_Token(_TokenType.variation, content));
          }
          i = end + 1;
          continue;
        }
      }

      // Result token
      final resultMatch = RegExp(r'1-0|0-1|1/2-1/2|\*').matchAsPrefix(text, i);
      if (resultMatch != null) {
        tokens.add(_Token(_TokenType.result, resultMatch.group(0)!));
        i = resultMatch.end;
        continue;
      }

      // Move number — '1.' (white) or '1...' (black)
      final moveNumMatch = RegExp(r'\d+\.{1,3}').matchAsPrefix(text, i);
      if (moveNumMatch != null) {
        tokens.add(_Token(_TokenType.moveNumber, moveNumMatch.group(0)!));
        i = moveNumMatch.end;
        continue;
      }

      // SAN move (standard, castling, promotion, FAN glyphs)
      final moveMatch = RegExp(
        r'[KQRBN♔♕♖♗♘♚♛♜♝♞]?[a-h]?[1-8]?x?[a-h][1-8](?:=[QRBN])?[+#]?'
        r'|O-O(?:-O)?[+#]?'
        r'|0-0(?:-0)?[+#]?',
      ).matchAsPrefix(text, i);
      if (moveMatch != null && moveMatch.group(0)!.isNotEmpty) {
        tokens.add(_Token(_TokenType.move, moveMatch.group(0)!));
        i = moveMatch.end;
        continue;
      }

      i++; // unrecognized character — skip
    }

    return tokens;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Finds the closing parenthesis matching the opening one at [open].
  /// Handles arbitrary nesting depth.
  int _findMatchingParen(String text, int open) {
    var depth = 0;
    for (var j = open; j < text.length; j++) {
      if (text[j] == '(') depth++;
      if (text[j] == ')') {
        depth--;
        if (depth == 0) return j;
      }
    }
    return -1; // unmatched parenthesis
  }

  /// Merges two nullable strings with a space separator.
  String? _merge(String? a, String? b) {
    if (a == null) return b;
    if (b == null) return a;
    return '$a $b';
  }

  String _normalizePiece(String move) => config.usesFigurine
      ? FanNormalizer.normalize(move)
      : _localizer.normalize(move);

  String? _extractResult(String? value) {
    if (value == null) return null;
    const valid = {'1-0', '0-1', '1/2-1/2', '*'};
    return valid.contains(value) ? value : null;
  }
}

// ---------------------------------------------------------------------------
// Internal token model
// ---------------------------------------------------------------------------

enum _TokenType { moveNumber, move, comment, variation, result }

class _Token {
  final _TokenType type;
  final String value;
  const _Token(this.type, this.value);
}
