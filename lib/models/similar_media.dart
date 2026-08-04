import 'media_item.dart';

enum SimilarMode { overall, plot, genres, atmosphere, characters }

extension SimilarModeLabel on SimilarMode {
  String get label => switch (this) {
    SimilarMode.overall => 'Общее',
    SimilarMode.plot => 'По сюжету',
    SimilarMode.genres => 'По жанрам',
    SimilarMode.atmosphere => 'По атмосфере',
    SimilarMode.characters => 'По персонажам и темам',
  };
}

class SimilarMediaItem {
  const SimilarMediaItem({
    required this.media,
    required this.score,
    required this.reasons,
    required this.breakdown,
  });

  final MediaItem media;
  final int score;
  final List<String> reasons;
  final Map<String, double> breakdown;

  factory SimilarMediaItem.fromJson(Map<String, dynamic> json) =>
      SimilarMediaItem(
        media: MediaItem.fromApi(json),
        score: ((json['similarityScore'] as num?) ?? 0).round(),
        reasons: (json['similarityReasons'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList(),
        breakdown: ((json['similarityBreakdown'] as Map?) ?? const {}).map(
          (key, value) => MapEntry('$key', value is num ? value.toDouble() : 0),
        ),
      );
}

class SimilarMediaPage {
  const SimilarMediaPage({
    required this.items,
    required this.page,
    required this.hasMore,
    required this.warnings,
    this.guidance,
  });

  final List<SimilarMediaItem> items;
  final int page;
  final bool hasMore;
  final List<String> warnings;
  final String? guidance;
}
