import 'package:flutter/foundation.dart';

import '../../core/models/game_extraction_config.dart';
import '../../core/models/chess_move.dart';
import '../../core/models/chess_game.dart';
import 'fan_normalizer.dart';
import 'piece_localizer.dart';
import 'annotation_parser.dart';

/// Parses raw OCR text into a [ChessGame].
///
/// Comment attachment rules:
///   - Comment before any move         → [ChessGame.headers] key 'Comment'
///   - Comment after move number       → [ChessMove.commentBefore]
///   - Comment immediately after move  → [ChessMove.commentAfter]
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
    final normalized = _normalizeParagraphComments(rawOcr);
    return _parseTokens(_tokenize(normalized));
  }

  // ---------------------------------------------------------------------------
  // Pre-pass — paragraph comment normalization
  // ---------------------------------------------------------------------------

  String _normalizeParagraphComments(String text) {
    final paragraphs = text.split(RegExp(r'\n{2,}'));
    final result = <String>[];

    for (final para in paragraphs) {
      final trimmed = para.trim();
      if (trimmed.isEmpty) continue;

      // Do NOT rewrap text already delimited by braces
      if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
        result.add(trimmed);
        continue;
      }

      if (_looksLikeComment(trimmed)) {
        result.add('{ $trimmed }');
      } else {
        result.add(trimmed);
      }
    }
    return result.join('\n');
  }

  bool _looksLikeComment(String text) {
    // If text contains move numbers (digit + dot), it's NOT a comment
    // even if it starts with a narrative word
    final hasMoveNumber = RegExp(r'\d+\.').hasMatch(text);
    if (hasMoveNumber) return false;

    final hasSanMove = _sanPattern.hasMatch(text);
    if (hasSanMove) return false;

    return true;
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
    _TokenType? lastTokenType; // tracks the previous token type

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

          // PRIORITY: comment right after a move number → commentBefore
          // This must be checked BEFORE gameStarted, because when parsing
          // '1. { before } e4', gameStarted is still false at this point.
          if (lastTokenType == _TokenType.moveNumber) {
            pendingComment = _merge(pendingComment, text);
            break;
          }

          // Comment before the first move and not after a move number → header
          if (!gameStarted) {
            headers['Comment'] = _merge(headers['Comment'], text)!;
            break;
          }

          // Comment after a move → commentAfter on the last parsed move
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
          color = token.value.contains('...')
              ? PieceColor.black
              : PieceColor.white;
          debugPrint('MOVE_NUM: ${token.value} → color=${color.name}');

        // --------------------------------------------------------------------
        case _TokenType.move:
          gameStarted = true;

          final raw = token.value;
          final withNags = AnnotationParser.extract(raw);
          final san = _normalizePiece(withNags.clean);

          debugPrint(
            'MOVE: $san → color=${color.name}, moveNumber=$moveNumber',
          );

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

      // Track the last token type for comment attachment logic
      lastTokenType = token.type;
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

      // [ ... ] — inside move flow = comment
      if (ch == '[') {
        final end = text.indexOf(']', i + 1);
        if (end != -1) {
          final content = text.substring(i + 1, end).trim();
          final isPgnHeader = RegExp(r'^[A-Z][a-zA-Z]+ "').hasMatch(content);
          if (!isPgnHeader) {
            tokens.add(_Token(_TokenType.comment, content));
          }
          i = end + 1;
          continue;
        }
      }

      // ( ... ) — variation or comment
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

      // Result
      final resultMatch = RegExp(r'1-0|0-1|1/2-1/2|\*').matchAsPrefix(text, i);
      if (resultMatch != null) {
        tokens.add(_Token(_TokenType.result, resultMatch.group(0)!));
        i = resultMatch.end;
        continue;
      }

      // Move number — '1.' (white) or '1...' (black)
      final moveNumMatch = RegExp(r'\d+\.{1,3}').matchAsPrefix(text, i);
      if (moveNumMatch != null) {
        final val = moveNumMatch.group(0)!;
        debugPrint(
          'MOVE_NUM TOKEN: "$val" contains...: ${val.contains("...")}',
        );
        tokens.add(_Token(_TokenType.moveNumber, moveNumMatch.group(0)!));
        i = moveNumMatch.end;
        continue;
      }

      // SAN move — includes inline annotation symbols
      final moveMatch = _sanPattern.matchAsPrefix(text, i);
      if (moveMatch != null && moveMatch.group(0)!.isNotEmpty) {
        tokens.add(_Token(_TokenType.move, moveMatch.group(0)!));
        i = moveMatch.end;
        continue;
      }

      final standaloneAnnotation = RegExp(
        r'⊙|□|±|∓|⩲|⩱|\+\-|\-\+|∞|→|⇄',
      ).matchAsPrefix(text, i);
      if (standaloneAnnotation != null) {
        // Attach to previous move by appending to its value
        if (tokens.isNotEmpty && tokens.last.type == _TokenType.move) {
          final prev = tokens.removeLast();
          tokens.add(
            _Token(
              _TokenType.move,
              prev.value + standaloneAnnotation.group(0)!,
            ),
          );
        }
        i = standaloneAnnotation.end;
        continue;
      }

      // Undelimited comment — accumulate unrecognized words
      final wordMatch = RegExp(r'\S+').matchAsPrefix(text, i);
      if (wordMatch != null) {
        final word = wordMatch.group(0)!;
        if (tokens.isNotEmpty && tokens.last.type == _TokenType.comment) {
          final prev = tokens.removeLast();
          tokens.add(_Token(_TokenType.comment, '${prev.value} $word'));
        } else {
          tokens.add(_Token(_TokenType.comment, word));
        }
        i = wordMatch.end;
        continue;
      }

      i++;
    }

    return tokens;
  }

  // ---------------------------------------------------------------------------
  // SAN pattern — includes inline annotation symbols after the move
  // ---------------------------------------------------------------------------

  RegExp get _sanPattern {
    // Always include both Unicode glyphs AND Latin letters for piece prefix
    // because books may mix FAN glyphs (♘) with Latin letters (N) after OCR correction
    const piecesLatin = 'KQRBN';
    const piecesUnicode = '♔♕♖♗♘♚♛♜♝♞';

    final localPieces = config.usesFigurine
        ? '$piecesLatin$piecesUnicode' // both — OCR correction produces Latin
        : config.locale.pieceMap.keys.join();

    const annotation = r'(?:!!|\?\?|!\?|\?!|!|\?)?';

    return RegExp(
      '[$localPieces]?[a-h]?[1-8]?x?[a-h][1-8](=[QRBN])?$annotation[+#]?'
      '|O-O(?:-O)?$annotation[+#]?'
      '|0-0(?:-0)?$annotation[+#]?',
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

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
