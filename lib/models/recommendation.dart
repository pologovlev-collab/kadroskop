import 'media_item.dart';

class RecommendationSeed {
  const RecommendationSeed({
    required this.source,
    required this.sourceId,
    required this.weight,
  });

  final String source;
  final String sourceId;
  final int weight;

  String get compact => '$source:$sourceId:$weight';
  String get identity => '$source:$sourceId';
}

class RecommendationItem {
  const RecommendationItem({
    required this.media,
    required this.score,
    required this.reasons,
  });

  final MediaItem media;
  final int score;
  final List<String> reasons;

  factory RecommendationItem.fromJson(Map<String, dynamic> json) =>
      RecommendationItem(
        media: MediaItem.fromApi(json),
        score: ((json['recommendationScore'] as num?) ?? 0).round(),
        reasons: (json['recommendationReasons'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList(),
      );
}

class RecommendationPage {
  const RecommendationPage({
    required this.items,
    required this.page,
    required this.hasMore,
    required this.warnings,
    this.guidance,
  });

  final List<RecommendationItem> items;
  final int page;
  final bool hasMore;
  final List<String> warnings;
  final String? guidance;
}
