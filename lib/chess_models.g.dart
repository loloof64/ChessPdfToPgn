// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chess_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ChessMove _$ChessMoveFromJson(Map<String, dynamic> json) => ChessMove(
  number: (json['number'] as num).toInt(),
  white: json['white'] as String,
  black: json['black'] as String?,
  commentWhite: json['comment_white'] as String?,
  commentBlack: json['comment_black'] as String?,
  hasDiagram: json['has_diagram'] as bool? ?? false,
);

Map<String, dynamic> _$ChessMoveToJson(ChessMove instance) => <String, dynamic>{
  'number': instance.number,
  'white': instance.white,
  'black': instance.black,
  'comment_white': instance.commentWhite,
  'comment_black': instance.commentBlack,
  'has_diagram': instance.hasDiagram,
};

ChessGame _$ChessGameFromJson(Map<String, dynamic> json) => ChessGame(
  white: json['white'] as String,
  black: json['black'] as String,
  date: json['date'] as String?,
  event: json['event'] as String?,
  site: json['site'] as String?,
  eloWhite: json['elo_white'] as String?,
  eloBlack: json['elo_black'] as String?,
  result: json['result'] as String? ?? '*',
  startingPosition:
      json['starting_position'] as String? ??
      'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
  page: (json['page'] as num).toInt(),
  gameNumber: (json['game_number'] as num).toInt(),
  moves: (json['moves'] as List<dynamic>)
      .map((e) => ChessMove.fromJson(e as Map<String, dynamic>))
      .toList(),
);

Map<String, dynamic> _$ChessGameToJson(ChessGame instance) => <String, dynamic>{
  'white': instance.white,
  'black': instance.black,
  'date': instance.date,
  'event': instance.event,
  'site': instance.site,
  'elo_white': instance.eloWhite,
  'elo_black': instance.eloBlack,
  'result': instance.result,
  'starting_position': instance.startingPosition,
  'page': instance.page,
  'game_number': instance.gameNumber,
  'moves': instance.moves,
};

ChessExtraction _$ChessExtractionFromJson(Map<String, dynamic> json) =>
    ChessExtraction(
      version: json['version'] as String,
      totalGames: (json['total_games'] as num).toInt(),
      games: (json['games'] as List<dynamic>)
          .map((e) => ChessGame.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$ChessExtractionToJson(ChessExtraction instance) =>
    <String, dynamic>{
      'version': instance.version,
      'total_games': instance.totalGames,
      'games': instance.games,
    };
