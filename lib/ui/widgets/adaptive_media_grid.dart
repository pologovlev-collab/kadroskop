import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/media_item.dart';
import 'poster_card.dart';

class AdaptiveMediaGrid extends StatelessWidget {
  const AdaptiveMediaGrid({
    super.key,
    required this.items,
    required this.onOpen,
    this.cardBuilder,
    this.onFavorite,
    this.onSimilar,
  });

  final List<MediaItem> items;
  final ValueChanged<MediaItem> onOpen;
  final Widget Function(BuildContext context, MediaItem item, double width)?
  cardBuilder;
  final void Function(MediaItem item, bool favorite)? onFavorite;
  final ValueChanged<MediaItem>? onSimilar;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const gap = 16.0;
      final compact = constraints.maxWidth < 600;
      final columns = compact
          ? 2
          : math.max(2, ((constraints.maxWidth + gap) / 216).floor());
      final availableWidth =
          (constraints.maxWidth - gap * (columns - 1)) / columns;
      final width = compact ? availableWidth : math.min(220.0, availableWidth);
      return Wrap(
        spacing: gap,
        runSpacing: 24,
        alignment: compact ? WrapAlignment.start : WrapAlignment.spaceBetween,
        children: [
          for (final item in items)
            cardBuilder?.call(context, item, width) ??
                PosterCard(
                  item: item,
                  onTap: () => onOpen(item),
                  onFavorite: onFavorite == null
                      ? null
                      : (favorite) => onFavorite!(item, favorite),
                  onSimilar: onSimilar == null ? null : () => onSimilar!(item),
                  width: width,
                ),
        ],
      );
    },
  );
}
