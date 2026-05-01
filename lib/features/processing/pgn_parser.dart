import '../../core/models/game_extraction_config.dart';
import '../../core/models/chess_move.dart';
import '../../core/models/chess_game.dart';
import 'fan_normalizer.dart';
import 'piece_localizer.dart';
import 'annotation_parser.dart';

class PgnParser {
  final GameExtractionConfig config;
  late final PieceLocalizer _localizer;

  PgnParser(this.config) {
    _localizer = PieceLocalizer(config.locale);
  }

  ChessGame parse(String rawOcr) {
    final tokens = _tokenize(rawOcr);
    final moves = <ChessMove>[];

    int moveNumber = 1;
    PieceColor color = PieceColor.white;
    String? pendingComment;

    for (final token in tokens) {
      switch (token.type) {
        case _TokenType.moveNumber:
          moveNumber = int.parse(token.value.replaceAll('.', '').trim());
          color = PieceColor.white;

        case _TokenType.move:
          final raw = token.value;
          final withNags = AnnotationParser.extract(raw);
          final normalized = _normalizePiece(withNags.clean);

          moves.add(
            ChessMove(
              moveNumber: moveNumber,
              color: color,
              san: normalized,
              rawOcr: raw,
              nags: withNags.nags,
              commentBefore: pendingComment,
            ),
          );
          pendingComment = null;

          if (color == PieceColor.white) {
            color = PieceColor.black;
          } else {
            moveNumber++;
            color = PieceColor.white;
          }

        case _TokenType.comment:
          // Comment attaches to the next move (commentBefore)
          // or to the last already-parsed move (commentAfter)
          if (moves.isEmpty) {
            pendingComment = token.value;
          } else {
            final last = moves.removeLast();
            moves.add(
              ChessMove(
                moveNumber: last.moveNumber,
                color: last.color,
                san: last.san,
                rawOcr: last.rawOcr,
                nags: last.nags,
                commentBefore: last.commentBefore,
                commentAfter: token.value,
                variations: last.variations,
              ),
            );
          }

        case _TokenType.result:
          break; // handled separately
      }
    }

    final result = _extractResult(rawOcr);
    return ChessGame(
      headers: {'Event': '?', 'Site': '?', 'Date': '????.??.??'},
      moves: moves,
      result: result,
    );
  }

  String _normalizePiece(String move) {
    if (config.usesFigurine) {
      return FanNormalizer.normalize(move);
    }
    return _localizer.normalize(move);
  }

  List<_Token> _tokenize(String text) {
    final tokens = <_Token>[];
    var i = 0;

    // Comment patterns based on config
    final openComment = switch (config.commentStyle) {
      CommentStyle.braces => '{',
      CommentStyle.parentheses => '(',
      CommentStyle.mixed => RegExp(r'[{(]'),
    };
    final closeComment = switch (config.commentStyle) {
      CommentStyle.braces => '}',
      CommentStyle.parentheses => ')',
      CommentStyle.mixed => null, // determined at opening
    };

    while (i < text.length) {
      // Skip whitespace
      if (text[i] == ' ' || text[i] == '\n' || text[i] == '\r') {
        i++;
        continue;
      }

      // Move number: 1. or 1...
      final moveNumMatch = RegExp(r'\d+\.+').matchAsPrefix(text, i);
      if (moveNumMatch != null) {
        tokens.add(_Token(_TokenType.moveNumber, moveNumMatch.group(0)!));
        i = moveNumMatch.end;
        continue;
      }

      // Result
      final resultMatch = RegExp(r'1-0|0-1|1/2-1/2|\*').matchAsPrefix(text, i);
      if (resultMatch != null) {
        tokens.add(_Token(_TokenType.result, resultMatch.group(0)!));
        i = resultMatch.end;
        continue;
      }

      // Comment { }
      if (text[i] == '{') {
        final end = text.indexOf('}', i);
        if (end != -1) {
          tokens.add(
            _Token(_TokenType.comment, text.substring(i + 1, end).trim()),
          );
          i = end + 1;
          continue;
        }
      }

      // Comment ( ) — only for parentheses or mixed style
      if ((config.commentStyle == CommentStyle.parentheses ||
              config.commentStyle == CommentStyle.mixed) &&
          text[i] == '(') {
        final end = text.indexOf(')', i);
        if (end != -1) {
          final content = text.substring(i + 1, end).trim();
          // In mixed mode: if it starts with a digit → variation (ignored for now)
          // otherwise → comment
          if (config.commentStyle == CommentStyle.mixed &&
              RegExp(r'^\d').hasMatch(content)) {
            i = end + 1; // TODO: parse variations
            continue;
          }
          tokens.add(_Token(_TokenType.comment, content));
          i = end + 1;
          continue;
        }
      }

      // SAN move (including castling and promotion)
      final moveMatch = RegExp(
        r'[KQRBN]?[a-h]?[1-8]?x?[a-h][1-8](?:=[QRBN])?[+#]?'
        r'|O-O(?:-O)?[+#]?'
        r'|[♔♕♖♗♘♚♛♜♝♞][a-h]?[1-8]?x?[a-h][1-8][+#]?',
      ).matchAsPrefix(text, i);
      if (moveMatch != null) {
        tokens.add(_Token(_TokenType.move, moveMatch.group(0)!));
        i = moveMatch.end;
        continue;
      }

      i++; // unrecognized character, skip
    }

    return tokens;
  }

  String? _extractResult(String text) {
    final match = RegExp(r'1-0|0-1|1/2-1/2|\*').firstMatch(text);
    return match?.group(0);
  }
}

enum _TokenType { moveNumber, move, comment, result }

class _Token {
  final _TokenType type;
  final String value;
  const _Token(this.type, this.value);
}
