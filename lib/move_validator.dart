import 'package:chess/chess.dart';

/// Validates and corrects extracted moves using actual chess rules
/// Uses backtracking to find legal moves when OCR produces illegal ones
class MoveValidator {
  late Chess _game;
  List<String> validatedMoves = [];
  List<String> corrections = [];
  
  MoveValidator() {
    _game = Chess();
  }

  /// Try to play a move. Returns true if successful, false otherwise.
  bool tryMove(String moveStr) {
    final normalized = _normalizeMoveNotation(moveStr);
    
    // Try exact match first
    if (_tryPlayMove(normalized)) {
      validatedMoves.add(normalized);
      return true;
    }
    
    // Try with backtracking - find similar legal moves
    final suggestions = _findSimilarLegalMoves(normalized);
    if (suggestions.isNotEmpty) {
      final corrected = suggestions.first;
      _tryPlayMove(corrected);
      validatedMoves.add(corrected);
      corrections.add('$moveStr → $corrected');
      return true;
    }
    
    return false;
  }

  /// Normalize notation to standard format
  String _normalizeMoveNotation(String move) {
    return move.trim().toUpperCase()
        .replaceAll('0', 'O')
        .replaceAll('Ø', 'O')
        .replaceAll('−', '-')
        .replaceAll('–', '-');
  }

  /// Try to play a move in the current position
  bool _tryPlayMove(String moveStr) {
    try {
      final legalMoves = _game.moves();
      
      if (legalMoves.contains(moveStr)) {
        _game.move(moveStr);
        return true;
      }
      
      final baseMove = moveStr.replaceAll(RegExp(r'[+#!?]'), '');
      if (legalMoves.contains(baseMove)) {
        _game.move(baseMove);
        return true;
      }
      
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Find similar legal moves
  List<String> _findSimilarLegalMoves(String moveStr) {
    final similar = <String>[];
    
    try {
      final legalMoves = _game.moves();
      
      if (moveStr.length < 2) return [];
      
      for (final file in ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h']) {
        final variant = moveStr.replaceAll(RegExp(r'[a-h](?=[1-8])'), file);
        if (legalMoves.contains(variant)) {
          similar.add(variant);
        }
      }
      
      for (final rank in ['1', '2', '3', '4', '5', '6', '7', '8']) {
        final variant = moveStr.replaceAll(RegExp(r'[1-8]$'), rank);
        if (legalMoves.contains(variant)) {
          similar.add(variant);
        }
      }
      
      if (moveStr.length >= 2) {
        for (final file in ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h']) {
          for (final rank in ['1', '2', '3', '4', '5', '6', '7', '8']) {
            final variant = moveStr.replaceRange(
              moveStr.length - 2,
              moveStr.length,
              '$file$rank',
            );
            if (legalMoves.contains(variant)) {
              similar.add(variant);
            }
          }
        }
      }
    } catch (e) {
      // Ignore
    }
    
    return similar.toSet().toList();
  }

  /// Get current FEN position
  String getFen() => _game.fen;

  /// Get validation report
  String getReport() {
    final buffer = StringBuffer();
    buffer.writeln('Move Validation Report');
    buffer.writeln('====================');
    buffer.writeln('Valid moves: ${validatedMoves.length}');
    buffer.writeln('Corrections made: ${corrections.length}');
    
    if (corrections.isNotEmpty) {
      buffer.writeln('\nOCR Corrections:');
      for (final correction in corrections) {
        buffer.writeln('  • $correction');
      }
    }
    
    return buffer.toString();
  }

  /// Reset the game
  void reset() {
    _game = Chess();
    validatedMoves.clear();
    corrections.clear();
  }
}
