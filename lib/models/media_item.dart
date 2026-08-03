import 'dart:convert';

import 'package:flutter/material.dart';

enum MediaKind { movie, series, anime, cartoon, animatedSeries, documentary }

enum WatchStatus { none, planned, watched }

class MediaItem {
  const MediaItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.year,
    required this.kind,
    required this.rating,
    required this.genres,
    required this.colors,
    this.source = 'local',
    this.externalId,
    this.posterUrl,
    this.runtimeMinutes = 0,
    this.seasonCount = 0,
    this.episodeCount = 0,
    this.episodeRuntimeMinutes = 0,
    this.seasons = const [],
    this.status = WatchStatus.none,
  });

  final int id;
  final String title;
  final String subtitle;
  final String description;
  final int year;
  final MediaKind kind;
  final double rating;
  final List<String> genres;
  final List<Color> colors;
  final String source;
  final String? externalId;
  final String? posterUrl;
  final int runtimeMinutes;
  final int seasonCount;
  final int episodeCount;
  final int episodeRuntimeMinutes;
  final List<SeasonInfo> seasons;
  final WatchStatus status;

  bool get isEpisodic =>
      kind == MediaKind.series ||
      kind == MediaKind.anime ||
      kind == MediaKind.animatedSeries;

  int get totalRuntimeMinutes =>
      isEpisodic ? episodeCount * episodeRuntimeMinutes : runtimeMinutes;

  MediaItem copyWith({WatchStatus? status}) => MediaItem(
    id: id,
    title: title,
    subtitle: subtitle,
    description: description,
    year: year,
    kind: kind,
    rating: rating,
    genres: genres,
    colors: colors,
    source: source,
    externalId: externalId,
    posterUrl: posterUrl,
    runtimeMinutes: runtimeMinutes,
    seasonCount: seasonCount,
    episodeCount: episodeCount,
    episodeRuntimeMinutes: episodeRuntimeMinutes,
    seasons: seasons,
    status: status ?? this.status,
  );

  factory MediaItem.fromMap(Map<String, Object?> map) => MediaItem(
    id: map['id']! as int,
    title: map['title']! as String,
    subtitle: (map['subtitle'] as String?) ?? '',
    description: (map['description'] as String?) ?? '',
    year: (map['release_year'] as int?) ?? 0,
    kind: MediaKind.values.firstWhere(
      (value) => value.name == map['kind'],
      orElse: () => MediaKind.movie,
    ),
    rating: ((map['rating'] as num?) ?? 0).toDouble(),
    genres: ((map['genres'] as String?) ?? '')
        .split(',')
        .where((value) => value.isNotEmpty)
        .toList(),
    colors: [
      Color((map['color_a'] as int?) ?? 0xFF172A36),
      Color((map['color_b'] as int?) ?? 0xFF0D7A72),
    ],
    source: (map['source'] as String?) ?? 'local',
    externalId: map['external_id']?.toString(),
    posterUrl: map['poster_url'] as String?,
    runtimeMinutes: (map['runtime_minutes'] as int?) ?? 0,
    seasonCount: (map['season_count'] as int?) ?? 0,
    episodeCount: (map['episode_count'] as int?) ?? 0,
    episodeRuntimeMinutes: (map['episode_runtime_minutes'] as int?) ?? 0,
    seasons: _decodeSeasons(map['seasons_json'] as String?),
    status: WatchStatus.values.firstWhere(
      (value) => value.name == map['status'],
      orElse: () => WatchStatus.none,
    ),
  );

  factory MediaItem.fromApi(Map<String, dynamic> json) {
    final kind = MediaKind.values.firstWhere(
      (value) => value.name == json['kind'],
      orElse: () => MediaKind.movie,
    );
    final palette = switch (kind) {
      MediaKind.movie => const [Color(0xFF172A36), Color(0xFFC7905B)],
      MediaKind.series => const [Color(0xFF101A2C), Color(0xFF8B3D56)],
      MediaKind.anime => const [Color(0xFF182043), Color(0xFF7752A8)],
      MediaKind.cartoon => const [Color(0xFF244348), Color(0xFFE8A348)],
      MediaKind.animatedSeries => const [Color(0xFF17344A), Color(0xFF3E9B87)],
      MediaKind.documentary => const [Color(0xFF2C3E38), Color(0xFFC19B55)],
    };
    return MediaItem(
      id: (json['id'] as num).toInt(),
      title: (json['title'] as String?) ?? 'Без названия',
      subtitle: (json['subtitle'] as String?) ?? '',
      description: (json['description'] as String?) ?? '',
      year: ((json['year'] as num?) ?? 0).toInt(),
      kind: kind,
      rating: ((json['rating'] as num?) ?? 0).toDouble(),
      genres: (json['genres'] as List<dynamic>? ?? const []).cast<String>(),
      colors: palette,
      source: (json['source'] as String?) ?? 'remote',
      externalId: json['externalId']?.toString(),
      posterUrl: json['posterUrl'] as String?,
      runtimeMinutes: ((json['runtimeMinutes'] as num?) ?? 0).toInt(),
      seasonCount: ((json['seasonCount'] as num?) ?? 0).toInt(),
      episodeCount: ((json['episodeCount'] as num?) ?? 0).toInt(),
      episodeRuntimeMinutes: ((json['episodeRuntimeMinutes'] as num?) ?? 0)
          .toInt(),
      seasons: (json['seasons'] as List<dynamic>? ?? const [])
          .map((row) => SeasonInfo.fromJson(row as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, Object?> toDatabaseMap() => {
    'id': id,
    'title': title,
    'subtitle': subtitle,
    'description': description,
    'release_year': year,
    'kind': kind.name,
    'rating': rating,
    'genres': genres.join(','),
    'color_a': colors.first.toARGB32(),
    'color_b': colors.last.toARGB32(),
    'source': source,
    'external_id': externalId,
    'poster_url': posterUrl,
    'runtime_minutes': runtimeMinutes,
    'season_count': seasonCount,
    'episode_count': episodeCount,
    'episode_runtime_minutes': episodeRuntimeMinutes,
    'seasons_json': jsonEncode(
      seasons.map((season) => season.toJson()).toList(),
    ),
  };

  static List<SeasonInfo> _decodeSeasons(String? value) {
    if (value == null || value.isEmpty) return const [];
    try {
      return (jsonDecode(value) as List<dynamic>)
          .map((row) => SeasonInfo.fromJson(row as Map<String, dynamic>))
          .toList();
    } on FormatException {
      return const [];
    }
  }
}

class SeasonInfo {
  const SeasonInfo({
    required this.number,
    required this.episodeCount,
    this.name,
  });

  final int number;
  final int episodeCount;
  final String? name;

  factory SeasonInfo.fromJson(Map<String, dynamic> json) => SeasonInfo(
    number: (json['number'] as num).toInt(),
    episodeCount: (json['episodeCount'] as num).toInt(),
    name: json['name'] as String?,
  );

  Map<String, Object?> toJson() => {
    'number': number,
    'episodeCount': episodeCount,
    'name': name,
  };
}

class EpisodeProgress {
  const EpisodeProgress({
    required this.seasonNumber,
    required this.episodeNumber,
    required this.watched,
  });

  final int seasonNumber;
  final int episodeNumber;
  final bool watched;
}

extension MediaKindLabel on MediaKind {
  String get label => switch (this) {
    MediaKind.movie => 'Фильмы',
    MediaKind.series => 'Сериалы',
    MediaKind.anime => 'Аниме',
    MediaKind.cartoon => 'Мультфильмы',
    MediaKind.animatedSeries => 'Мультсериалы',
    MediaKind.documentary => 'Документальное',
  };

  IconData get icon => switch (this) {
    MediaKind.movie => Icons.movie_creation_outlined,
    MediaKind.series => Icons.live_tv_outlined,
    MediaKind.anime => Icons.auto_awesome_outlined,
    MediaKind.cartoon => Icons.cruelty_free_outlined,
    MediaKind.animatedSeries => Icons.animation_outlined,
    MediaKind.documentary => Icons.video_camera_back_outlined,
  };
}
