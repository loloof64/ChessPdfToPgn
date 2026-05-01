import '../../core/models/game_extraction_config.dart';
import '../../core/models/chess_move.dart';
import '../../core/models/chess_game.dart';
import 'fan_normalizer.dart';
import 'piece_localizer.dart';
import 'annotation_parser.dart';

/// Parses raw OCR text into a [ChessGame].
///
/// Comment detection strategy (in priority order):
///   1. Delimited inline comments  : { ... }  ( ... )  [ ... ]
///   2. Paragraph comments         : block separated by \n\n with no SAN tokens
///   3. Undelimited inline comments: any token that is not SAN, not a move
///                                   number, not a result → comment
///
/// Comment attachment rules:
///   - Comment before any move         → [ChessGame.headers] key 'Comment'
///   - Comment immediately after move  → [ChessMove.commentAfter]
///   - Comment immediately before move → [ChessMove.commentBefore]
///   - Two consecutive comments        → merged with a space separator
///   - Comment after result            → [ChessGame.headers] key 'CommentAfterResult'
class PgnParser {
  final GameExtractionConfig config;
  late final PieceLocalizer _localizer;

  PgnParser(this.config) {
    _localizer = PieceLocalizer(config.locale);
  }

  // ---------------------------------------------------------------------------
  // Public entry point
  // ---------------------------------------------------------------------------

  ChessGame parse(String rawOcr) {
    // Pre-pass: convert paragraph comments into explicit { } delimiters
    final normalized = _normalizeParagraphComments(rawOcr);
    return _parseTokens(_tokenize(normalized));
  }

  // ---------------------------------------------------------------------------
  // Pre-pass — paragraph comment normalization
  // ---------------------------------------------------------------------------

  /// Converts paragraph-style comments into braced comments.
  ///
  /// A paragraph is considered a comment if it is separated from surrounding
  /// text by blank lines (\n\n) AND contains no SAN tokens or move numbers.
  String _normalizeParagraphComments(String text) {
    // Split on double newlines to get paragraphs
    final paragraphs = text.split(RegExp(r'\n{2,}'));
    final result = <String>[];

    for (final para in paragraphs) {
      final trimmed = para.trim();
      if (trimmed.isEmpty) continue;

      if (_looksLikeComment(trimmed)) {
        // Wrap in braces so the main tokenizer handles it uniformly
        result.add('{ $trimmed }');
      } else {
        result.add(trimmed);
      }
    }

    return result.join('\n');
  }

  /// Returns true if [text] contains no SAN moves and no move numbers.
  /// Such a paragraph is treated as a comment.
  bool _looksLikeComment(String text) {
    final hasMoveNumber = RegExp(r'\d+\.').hasMatch(text);
    final hasSanMove = _sanPattern.hasMatch(text);
    return !hasMoveNumber && !hasSanMove;
  }

  // ---------------------------------------------------------------------------
  // Core parser
  // ---------------------------------------------------------------------------

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
            headers['CommentAfterResult'] = _merge(
              headers['CommentAfterResult'],
              text,
            )!;
            break;
          }

          if (!gameStarted) {
            headers['Comment'] = _merge(headers['Comment'], text)!;
            break;
          }

          if (moves.isNotEmpty) {
            // Attach as commentAfter to the last parsed move
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
          if (moves.isEmpty) break;

          final variationGame = _parseTokens(_tokenize(token.value));
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

    final resultValue = tokens
        .where((t) => t.type == _TokenType.result)
        .firstOrNull
        ?.value;
    final result = _validateResult(resultValue);
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

      // --- Delimited comments ---

      // { ... }
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

      // [ ... ] — inside move flow = comment (not a PGN header)
      // Headers are stripped before this stage; anything remaining is a comment.
      if (ch == '[') {
        final end = text.indexOf(']', i + 1);
        if (end != -1) {
          final content = text.substring(i + 1, end).trim();
          // Only treat as comment if it does NOT look like a PGN header tag
          // i.e. it doesn't start with a capitalized word followed by a quote
          final isPgnHeader = RegExp(r'^[A-Z][a-zA-Z]+ "').hasMatch(content);
          if (!isPgnHeader) {
            tokens.add(_Token(_TokenType.comment, content));
          }
          i = end + 1;
          continue;
        }
      }

      // ( ... ) — variation or comment depending on content + config
      if (ch == '(') {
        final end = _findMatchingParen(text, i);
        if (end != -1) {
          final content = text.substring(i + 1, end).trim();
          final looksLikeVariation = RegExp(r'^\d').hasMatch(content);

          if (!looksLikeVariation &&
              (config.commentStyle == CommentStyle.parentheses ||
                  config.commentStyle == CommentStyle.mixed)) {
            tokens.add(_Token(_TokenType.comment, content));
          } else {
            tokens.add(_Token(_TokenType.variation, content));
          }
          i = end + 1;
          continue;
        }
      }

      // --- Result ---
      final resultMatch = RegExp(r'1-0|0-1|1/2-1/2|\*').matchAsPrefix(text, i);
      if (resultMatch != null) {
        tokens.add(_Token(_TokenType.result, resultMatch.group(0)!));
        i = resultMatch.end;
        continue;
      }

      // --- Move number ---
      final moveNumMatch = RegExp(r'\d+\.{1,3}').matchAsPrefix(text, i);
      if (moveNumMatch != null) {
        tokens.add(_Token(_TokenType.moveNumber, moveNumMatch.group(0)!));
        i = moveNumMatch.end;
        continue;
      }

      // --- SAN move ---
      final moveMatch = _sanPattern.matchAsPrefix(text, i);
      if (moveMatch != null && moveMatch.group(0)!.isNotEmpty) {
        tokens.add(_Token(_TokenType.move, moveMatch.group(0)!));
        i = moveMatch.end;
        continue;
      }

      // --- Undelimited comment ---
      // Anything that is not a recognized token is accumulated as a comment
      // until the next whitespace boundary or recognized token.
      final wordMatch = RegExp(r'\S+').matchAsPrefix(text, i);
      if (wordMatch != null) {
        final word = wordMatch.group(0)!;
        // Merge consecutive undelimited comment words into the previous
        // comment token if possible, otherwise create a new one.
        if (tokens.isNotEmpty && tokens.last.type == _TokenType.comment) {
          final prev = tokens.removeLast();
          tokens.add(_Token(_TokenType.comment, '${prev.value} $word'));
        } else {
          tokens.add(_Token(_TokenType.comment, word));
        }
        i = wordMatch.end;
        continue;
      }

      i++; // unrecognized single character — skip
    }

    return tokens;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// SAN pattern — covers standard moves, castling, promotions, FAN glyphs.
  static final _sanPattern = RegExp(
    r'[KQRBN♔♕♖♗♘♚♛♜♝♞]?[a-h]?[1-8]?x?[a-h][1-8](?:=[QRBN])?[+#]?'
    r'|O-O(?:-O)?[+#]?'
    r'|0-0(?:-0)?[+#]?',
  );

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
    return -1;
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

  String? _validateResult(String? value) {
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
