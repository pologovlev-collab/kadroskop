import 'package:flutter/material.dart';

import '../../models/media_item.dart';
import '../../models/recommendation.dart';
import '../app_theme.dart';
import '../widgets/adaptive_media_grid.dart';
import '../widgets/poster_card.dart';

class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
    required this.savedItems,
    required this.popularItems,
    required this.recommendations,
    required this.loadingRecommendations,
    required this.recommendationsError,
    required this.recommendationsGuidance,
    required this.selectedKind,
    required this.onOpen,
    required this.onFavorite,
    required this.onRecall,
    required this.onSelectKind,
    required this.onOpenSearch,
    required this.onLibrary,
    required this.onStatistics,
    required this.onRetryRecommendations,
  });

  final List<MediaItem> savedItems;
  final List<MediaItem> popularItems;
  final List<RecommendationItem> recommendations;
  final bool loadingRecommendations;
  final String? recommendationsError;
  final String? recommendationsGuidance;
  final MediaKind? selectedKind;
  final ValueChanged<MediaItem> onOpen;
  final void Function(MediaItem item, bool favorite) onFavorite;
  final VoidCallback onRecall;
  final ValueChanged<MediaKind?> onSelectKind;
  final VoidCallback onOpenSearch;
  final VoidCallback onLibrary;
  final VoidCallback onStatistics;
  final VoidCallback onRetryRecommendations;

  @override
  Widget build(BuildContext context) {
    final collection = savedItems
        .where((item) => item.status != WatchStatus.none)
        .toList();
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        MediaQuery.sizeOf(context).width < 600 ? 18 : 34,
        24,
        MediaQuery.sizeOf(context).width < 600 ? 18 : 34,
        42,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1500),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Hero(
                item: popularItems.firstOrNull,
                onRecall: onRecall,
                onOpen: onOpen,
              ),
              const SizedBox(height: 24),
              _Kinds(selected: selectedKind, onSelected: onSelectKind),
              const SizedBox(height: 32),
              _Header(
                title: selectedKind == null
                    ? 'Для вас'
                    : '${selectedKind!.label} для вас',
                action: 'Открыть поиск',
                onAction: onOpenSearch,
              ),
              const SizedBox(height: 10),
              if (loadingRecommendations)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 54),
                  child: Center(
                    child: CircularProgressIndicator(color: AppColors.accent),
                  ),
                )
              else if (recommendationsError != null)
                _PopularError(
                  message: recommendationsError!,
                  onRetry: onRetryRecommendations,
                )
              else if (recommendations.isEmpty)
                _NoRecommendations(
                  message:
                      recommendationsGuidance ??
                      'Добавьте несколько произведений в избранное или поставьте им оценки.',
                  onSearch: onOpenSearch,
                )
              else
                AdaptiveMediaGrid(
                  items: recommendations
                      .take(12)
                      .map((entry) => entry.media)
                      .toList(),
                  onOpen: onOpen,
                  cardBuilder: (context, item, width) {
                    final entry = recommendations.firstWhere(
                      (candidate) => candidate.media.id == item.id,
                    );
                    return PosterCard(
                      item: item,
                      width: width,
                      onTap: () => onOpen(item),
                      onFavorite: (favorite) => onFavorite(item, favorite),
                      supportingText: entry.reasons.firstOrNull,
                    );
                  },
                ),
              const SizedBox(height: 36),
              _Header(
                title: 'Ваша коллекция',
                action: 'Открыть коллекцию',
                onAction: onLibrary,
              ),
              const SizedBox(height: 14),
              _CollectionSummary(
                items: collection,
                onLibrary: onLibrary,
                onStatistics: onStatistics,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({
    required this.item,
    required this.onRecall,
    required this.onOpen,
  });
  final MediaItem? item;
  final VoidCallback onRecall;
  final ValueChanged<MediaItem> onOpen;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 720;
      final copy = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'Помните сюжет,\nно забыли название?',
            style: TextStyle(
              color: Colors.white,
              fontSize: 34,
              height: 1.05,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Опишите сцену, героев или примерный год. Кадроскоп проверит реальные каталоги и покажет наиболее похожие произведения.',
            style: TextStyle(color: Colors.white70, height: 1.45),
          ),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: onRecall,
            icon: const Icon(Icons.auto_awesome_rounded),
            label: const Text('Помоги вспомнить'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppColors.ink,
            ),
          ),
        ],
      );
      final poster = item == null
          ? const Icon(
              Icons.manage_search_rounded,
              size: 120,
              color: Colors.white24,
            )
          : GestureDetector(
              onTap: () => onOpen(item!),
              child: SizedBox(
                width: compact ? 150 : 210,
                child: PosterArtwork(item: item!, height: compact ? 210 : 300),
              ),
            );
      return Container(
        padding: EdgeInsets.all(compact ? 24 : 38),
        decoration: BoxDecoration(
          color: const Color(0xFF102B32),
          borderRadius: BorderRadius.circular(28),
        ),
        child: compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  copy,
                  const SizedBox(height: 24),
                  Align(alignment: Alignment.centerRight, child: poster),
                ],
              )
            : Row(
                children: [
                  Expanded(flex: 5, child: copy),
                  const SizedBox(width: 32),
                  Expanded(flex: 2, child: Center(child: poster)),
                ],
              ),
      );
    },
  );
}

class _Kinds extends StatelessWidget {
  const _Kinds({required this.selected, required this.onSelected});
  final MediaKind? selected;
  final ValueChanged<MediaKind?> onSelected;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 10),
          child: ChoiceChip(
            selected: selected == null,
            onSelected: (_) => onSelected(null),
            avatar: const Icon(Icons.apps_rounded, size: 18),
            label: const Text('Все'),
          ),
        ),
        for (final kind in MediaKind.values)
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: ChoiceChip(
              selected: selected == kind,
              onSelected: (_) => onSelected(kind),
              avatar: Icon(kind.icon, size: 18),
              label: Text(kind.label),
              side: const BorderSide(color: AppColors.border),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
            ),
          ),
      ],
    ),
  );
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.action,
    required this.onAction,
  });
  final String title;
  final String action;
  final VoidCallback onAction;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(title, style: Theme.of(context).textTheme.headlineMedium),
      ),
      TextButton(onPressed: onAction, child: Text(action)),
    ],
  );
}

class _CollectionSummary extends StatelessWidget {
  const _CollectionSummary({
    required this.items,
    required this.onLibrary,
    required this.onStatistics,
  });
  final List<MediaItem> items;
  final VoidCallback onLibrary;
  final VoidCallback onStatistics;
  @override
  Widget build(BuildContext context) {
    final watched = items
        .where((item) => item.status == WatchStatus.watched)
        .length;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Wrap(
        spacing: 30,
        runSpacing: 16,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _Value(value: '${items.length}', label: 'в коллекции'),
          _Value(value: '$watched', label: 'просмотрено'),
          _Value(
            value: '${items.expand((item) => item.genres).toSet().length}',
            label: 'жанров',
          ),
          FilledButton.icon(
            onPressed: onLibrary,
            icon: const Icon(Icons.bookmarks_outlined),
            label: const Text('Коллекция'),
          ),
          OutlinedButton.icon(
            onPressed: onStatistics,
            icon: const Icon(Icons.bar_chart_rounded),
            label: const Text('Статистика'),
          ),
        ],
      ),
    );
  }
}

class _Value extends StatelessWidget {
  const _Value({required this.value, required this.label});
  final String value;
  final String label;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(value, style: Theme.of(context).textTheme.headlineMedium),
      Text(label, style: const TextStyle(color: AppColors.muted)),
    ],
  );
}

class _PopularError extends StatelessWidget {
  const _PopularError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF4F1),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      children: [
        const Icon(Icons.cloud_off_rounded, color: AppColors.coral),
        const SizedBox(width: 10),
        Expanded(child: Text(message)),
        TextButton(onPressed: onRetry, child: const Text('Повторить')),
      ],
    ),
  );
}

class _NoRecommendations extends StatelessWidget {
  const _NoRecommendations({required this.message, required this.onSearch});
  final String message;
  final VoidCallback onSearch;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 36),
    child: Center(
      child: Column(
        children: [
          const Icon(
            Icons.favorite_outline_rounded,
            size: 42,
            color: AppColors.muted,
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: onSearch,
            icon: const Icon(Icons.search_rounded),
            label: const Text('Найти произведения'),
          ),
        ],
      ),
    ),
  );
}
