import 'package:flutter/material.dart';

enum MediaKind { movie, series, anime, cartoon, documentary }

enum WatchStatus { none, planned, watching, watched }

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
    this.progress = 0,
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
  final double progress;
  final WatchStatus status;

  MediaItem copyWith({WatchStatus? status, double? progress}) => MediaItem(
    id: id,
    title: title,
    subtitle: subtitle,
    description: description,
    year: year,
    kind: kind,
    rating: rating,
    genres: genres,
    colors: colors,
    progress: progress ?? this.progress,
    status: status ?? this.status,
  );

  factory MediaItem.fromMap(Map<String, Object?> map) => MediaItem(
    id: map['id']! as int,
    title: map['title']! as String,
    subtitle: map['subtitle']! as String,
    description: map['description']! as String,
    year: map['release_year']! as int,
    kind: MediaKind.values.firstWhere(
      (value) => value.name == map['kind'],
      orElse: () => MediaKind.movie,
    ),
    rating: (map['rating']! as num).toDouble(),
    genres: (map['genres']! as String)
        .split(',')
        .where((e) => e.isNotEmpty)
        .toList(),
    colors: [Color(map['color_a']! as int), Color(map['color_b']! as int)],
    progress: (map['progress'] as num?)?.toDouble() ?? 0,
    status: WatchStatus.values.firstWhere(
      (value) => value.name == map['status'],
      orElse: () => WatchStatus.none,
    ),
  );
}

extension MediaKindLabel on MediaKind {
  String get label => switch (this) {
    MediaKind.movie => 'Фильмы',
    MediaKind.series => 'Сериалы',
    MediaKind.anime => 'Аниме',
    MediaKind.cartoon => 'Мультфильмы',
    MediaKind.documentary => 'Документальное',
  };

  IconData get icon => switch (this) {
    MediaKind.movie => Icons.movie_creation_outlined,
    MediaKind.series => Icons.live_tv_outlined,
    MediaKind.anime => Icons.auto_awesome_outlined,
    MediaKind.cartoon => Icons.cruelty_free_outlined,
    MediaKind.documentary => Icons.video_camera_back_outlined,
  };
}
