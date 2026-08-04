import 'package:flutter/material.dart';

import 'media_item.dart';

class RememberSearchFilters {
  const RememberSearchFilters({
    required this.query,
    this.type,
    this.yearFrom,
    this.yearTo,
    this.country,
    this.visualStyle,
    this.excluded = const [],
    this.similarTo,
  });

  final String query;
  final MediaKind? type;
  final int? yearFrom;
  final int? yearTo;
  final String? country;
  final String? visualStyle;
  final List<String> excluded;
  final RememberReference? similarTo;

  Map<String, Object?> toJson() => {
    'query': query.trim(),
    if (type != null) 'type': type!.apiName,
    if (yearFrom != null) 'yearFrom': yearFrom,
    if (yearTo != null) 'yearTo': yearTo,
    if (country?.trim().isNotEmpty == true) 'country': country!.trim(),
    if (visualStyle != null) 'visualStyle': visualStyle,
    if (excluded.isNotEmpty) 'excluded': excluded,
    if (similarTo != null) 'similarTo': similarTo!.toJson(),
  };

  RememberSearchFilters copyWith({
    List<String>? excluded,
    RememberReference? similarTo,
  }) => RememberSearchFilters(
    query: query,
    type: type,
    yearFrom: yearFrom,
    yearTo: yearTo,
    country: country,
    visualStyle: visualStyle,
    excluded: excluded ?? this.excluded,
    similarTo: similarTo ?? this.similarTo,
  );
}

class RememberReference {
  const RememberReference({required this.source, required this.sourceId});
  final String source;
  final String sourceId;

  Map<String, Object?> toJson() => {'source': source, 'sourceId': sourceId};
}

class RememberCandidate {
  const RememberCandidate({
    required this.source,
    required this.sourceId,
    required this.title,
    required this.originalTitle,
    required this.year,
    required this.type,
    required this.posterUrl,
    required this.overview,
    required this.matchScore,
    required this.matchReasons,
    required this.scoreBreakdown,
    required this.lowConfidence,
    required this.rating,
    required this.genres,
  });

  final String source;
  final String sourceId;
  final String title;
  final String originalTitle;
  final int year;
  final MediaKind type;
  final String? posterUrl;
  final String overview;
  final double matchScore;
  final List<String> matchReasons;
  final Map<String, double> scoreBreakdown;
  final bool lowConfidence;
  final double rating;
  final List<String> genres;

  String get key => '$source:$sourceId';

  factory RememberCandidate.fromJson(Map<String, dynamic> json) {
    final kindName = (json['type'] as String?) ?? 'movie';
    final kind = MediaKind.values.firstWhere(
      (value) => value.apiName == kindName,
      orElse: () => MediaKind.movie,
    );
    return RememberCandidate(
      source: json['source'] as String,
      sourceId: json['sourceId'].toString(),
      title: json['title'] as String,
      originalTitle: (json['originalTitle'] as String?) ?? '',
      year: ((json['year'] as num?) ?? 0).toInt(),
      type: kind,
      posterUrl: json['posterUrl'] as String?,
      overview: (json['overview'] as String?) ?? '',
      matchScore: ((json['matchScore'] as num?) ?? 0).toDouble(),
      matchReasons: (json['matchReasons'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
      scoreBreakdown: ((json['scoreBreakdown'] as Map?) ?? const {}).map(
        (key, value) => MapEntry('$key', value is num ? value.toDouble() : 0),
      ),
      lowConfidence: (json['lowConfidence'] as bool?) ?? false,
      rating: ((json['rating'] as num?) ?? 0).toDouble(),
      genres: (json['genres'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
    );
  }

  MediaItem toMediaItem() => MediaItem(
    id: switch (source) {
      'tmdb_movie' => 1000000000 + int.parse(sourceId),
      'tmdb_tv' => 2000000000 + int.parse(sourceId),
      'anilist' => 3000000000 + int.parse(sourceId),
      _ => sourceId.hashCode,
    },
    title: title,
    subtitle: originalTitle,
    description: overview,
    year: year,
    kind: type,
    rating: rating,
    genres: genres,
    colors: type.palette,
    source: source,
    externalId: sourceId,
    posterUrl: posterUrl,
  );
}

class RememberSearchResult {
  const RememberSearchResult({
    required this.candidates,
    required this.warnings,
    required this.ai,
    this.guidance,
  });
  final List<RememberCandidate> candidates;
  final List<String> warnings;
  final Map<String, dynamic> ai;
  final String? guidance;
}

class CatalogPage {
  const CatalogPage({
    required this.items,
    required this.page,
    required this.hasMore,
    required this.warnings,
  });
  final List<MediaItem> items;
  final int page;
  final bool hasMore;
  final List<String> warnings;
}

extension MediaKindApi on MediaKind {
  String get apiName => switch (this) {
    MediaKind.animatedSeries => 'animated_series',
    _ => name,
  };

  List<Color> get palette => switch (this) {
    MediaKind.movie => const [Color(0xFF172A36), Color(0xFFC7905B)],
    MediaKind.series => const [Color(0xFF101A2C), Color(0xFF8B3D56)],
    MediaKind.anime => const [Color(0xFF182043), Color(0xFF7752A8)],
    MediaKind.cartoon => const [Color(0xFF244348), Color(0xFFE8A348)],
    MediaKind.animatedSeries => const [Color(0xFF17344A), Color(0xFF3E9B87)],
    MediaKind.documentary => const [Color(0xFF2C3E38), Color(0xFFC19B55)],
  };
}
