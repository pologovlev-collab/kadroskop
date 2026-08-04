import 'package:flutter/material.dart';

import '../../models/media_item.dart';
import '../app_theme.dart';
import '../widgets/adaptive_media_grid.dart';
import '../widgets/poster_card.dart';

enum LibrarySort { recent, title, yearNewest, rating }

enum LibraryTab { all, favorite, planned, watching, watched, dropped }

extension on LibraryTab {
  String get label => switch (this) {
    LibraryTab.all => 'Все',
    LibraryTab.favorite => 'Избранное',
    LibraryTab.planned => 'В планах',
    LibraryTab.watching => 'Смотрю',
    LibraryTab.watched => 'Просмотрено',
    LibraryTab.dropped => 'Брошено',
  };

  WatchStatus? get status => switch (this) {
    LibraryTab.planned => WatchStatus.planned,
    LibraryTab.watching => WatchStatus.watching,
    LibraryTab.watched => WatchStatus.watched,
    LibraryTab.dropped => WatchStatus.dropped,
    LibraryTab.all || LibraryTab.favorite => null,
  };
}

class LibraryPage extends StatefulWidget {
  const LibraryPage({
    super.key,
    required this.items,
    required this.onOpen,
    required this.onSetStatus,
    required this.onRating,
    required this.onFavorite,
    required this.onSimilar,
  });
  final List<MediaItem> items;
  final ValueChanged<MediaItem> onOpen;
  final Future<void> Function(MediaItem, WatchStatus, {bool resetProgress})
  onSetStatus;
  final Future<void> Function(MediaItem, double?) onRating;
  final void Function(MediaItem item, bool favorite) onFavorite;
  final ValueChanged<MediaItem> onSimilar;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  final _search = TextEditingController();
  LibraryTab _tab = LibraryTab.all;
  MediaKind? _kind;
  String? _genre;
  LibrarySort _sort = LibrarySort.recent;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final libraryItems = widget.items
        .where((item) => item.status != WatchStatus.none)
        .toList();
    final filterableItems = widget.items
        .where((item) => item.status != WatchStatus.none || item.isFavorite)
        .toList();
    final genres =
        filterableItems.expand((item) => item.genres).toSet().toList()..sort();
    final values = widget.items.where((item) {
      final belongsToTab = switch (_tab) {
        LibraryTab.all => item.status != WatchStatus.none,
        LibraryTab.favorite => item.isFavorite,
        _ => item.status == _tab.status,
      };
      return belongsToTab &&
          (_kind == null || item.kind == _kind) &&
          (_genre == null || item.genres.contains(_genre)) &&
          (query.isEmpty ||
              item.title.toLowerCase().contains(query) ||
              item.subtitle.toLowerCase().contains(query) ||
              item.genres.any((genre) => genre.toLowerCase().contains(query)));
    }).toList();
    switch (_sort) {
      case LibrarySort.recent:
        break;
      case LibrarySort.title:
        values.sort((a, b) => a.title.compareTo(b.title));
        break;
      case LibrarySort.yearNewest:
        values.sort((a, b) => b.year.compareTo(a.year));
        break;
      case LibrarySort.rating:
        values.sort((a, b) {
          final personal = (b.userRating ?? -1).compareTo(a.userRating ?? -1);
          return personal != 0 ? personal : b.rating.compareTo(a.rating);
        });
        break;
    }
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
              Text(
                'Моя коллекция',
                style: Theme.of(context).textTheme.displaySmall,
              ),
              const SizedBox(height: 7),
              const Text(
                'Статусы, поиск, сортировка и отметки серий',
                style: TextStyle(color: AppColors.muted, fontSize: 16),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _Summary(value: '${libraryItems.length}', label: 'всего'),
                  _Summary(
                    value:
                        '${filterableItems.where((item) => item.isFavorite).length}',
                    label: 'избранное',
                  ),
                  _Summary(
                    value:
                        '${libraryItems.where((item) => item.status == WatchStatus.watching).length}',
                    label: 'смотрю',
                  ),
                  _Summary(
                    value:
                        '${libraryItems.where((item) => item.status == WatchStatus.watched).length}',
                    label: 'просмотрено',
                  ),
                  _Summary(
                    value:
                        '${libraryItems.where((item) => item.status == WatchStatus.planned).length}',
                    label: 'в планах',
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _Filters(
                search: _search,
                tab: _tab,
                kind: _kind,
                genre: _genre,
                genres: genres,
                sort: _sort,
                onChanged: () => setState(() {}),
                onTab: (value) => setState(() => _tab = value),
                onKind: (value) => setState(() => _kind = value),
                onGenre: (value) => setState(() => _genre = value),
                onSort: (value) => setState(() => _sort = value),
              ),
              const SizedBox(height: 24),
              if (values.isEmpty)
                _Empty(filtered: filterableItems.isNotEmpty)
              else
                AdaptiveMediaGrid(
                  items: values,
                  onOpen: widget.onOpen,
                  cardBuilder: (context, item, width) => SizedBox(
                    width: width,
                    child: Stack(
                      children: [
                        PosterCard(
                          item: item,
                          width: width,
                          onTap: () => widget.onOpen(item),
                          onFavorite: (favorite) =>
                              widget.onFavorite(item, favorite),
                          onSimilar: () => widget.onSimilar(item),
                        ),
                        Positioned(
                          top: 8,
                          left: 8,
                          child: _StatusMenu(
                            item: item,
                            onSetStatus: widget.onSetStatus,
                            onOpen: widget.onOpen,
                            onRating: widget.onRating,
                            onFavorite: widget.onFavorite,
                            onSimilar: widget.onSimilar,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters({
    required this.search,
    required this.tab,
    required this.kind,
    required this.genre,
    required this.genres,
    required this.sort,
    required this.onChanged,
    required this.onTab,
    required this.onKind,
    required this.onGenre,
    required this.onSort,
  });
  final TextEditingController search;
  final LibraryTab tab;
  final MediaKind? kind;
  final String? genre;
  final List<String> genres;
  final LibrarySort sort;
  final VoidCallback onChanged;
  final ValueChanged<LibraryTab> onTab;
  final ValueChanged<MediaKind?> onKind;
  final ValueChanged<String?> onGenre;
  final ValueChanged<LibrarySort> onSort;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (
                var index = 0;
                index < LibraryTab.values.length;
                index++
              ) ...[
                if (index > 0) const SizedBox(width: 8),
                ChoiceChip(
                  avatar: LibraryTab.values[index] == LibraryTab.favorite
                      ? const Icon(Icons.favorite_rounded, size: 16)
                      : null,
                  label: Text(LibraryTab.values[index].label),
                  selected: tab == LibraryTab.values[index],
                  onSelected: (_) => onTab(LibraryTab.values[index]),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 1050;
            final fields = [
              TextField(
                controller: search,
                onChanged: (_) => onChanged(),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded),
                  labelText: 'Поиск в коллекции',
                ),
              ),
              DropdownButtonFormField<MediaKind?>(
                initialValue: kind,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Тип'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Все типы')),
                  for (final value in MediaKind.values)
                    DropdownMenuItem(value: value, child: Text(value.label)),
                ],
                onChanged: onKind,
              ),
              DropdownButtonFormField<LibrarySort>(
                initialValue: sort,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Сортировка'),
                items: const [
                  DropdownMenuItem(
                    value: LibrarySort.recent,
                    child: Text('Недавно изменённые'),
                  ),
                  DropdownMenuItem(
                    value: LibrarySort.title,
                    child: Text('По названию'),
                  ),
                  DropdownMenuItem(
                    value: LibrarySort.yearNewest,
                    child: Text('Сначала новые'),
                  ),
                  DropdownMenuItem(
                    value: LibrarySort.rating,
                    child: Text('По моей оценке'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) onSort(value);
                },
              ),
              DropdownButtonFormField<String?>(
                initialValue: genre,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Жанр'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Все жанры')),
                  for (final value in genres)
                    DropdownMenuItem(
                      value: value,
                      child: Text(value, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: onGenre,
              ),
            ];
            if (compact) {
              return Column(
                children: [
                  for (var i = 0; i < fields.length; i++) ...[
                    fields[i],
                    if (i != fields.length - 1) const SizedBox(height: 10),
                  ],
                ],
              );
            }
            return Row(
              children: [
                Expanded(flex: 2, child: fields[0]),
                const SizedBox(width: 10),
                Expanded(child: fields[1]),
                const SizedBox(width: 10),
                Expanded(child: fields[3]),
                const SizedBox(width: 10),
                Expanded(child: fields[2]),
              ],
            );
          },
        ),
      ],
    ),
  );
}

enum _LibraryAction {
  open,
  similar,
  favorite,
  rate,
  planned,
  watching,
  watched,
  dropped,
  remove,
}

class _StatusMenu extends StatelessWidget {
  const _StatusMenu({
    required this.item,
    required this.onSetStatus,
    required this.onOpen,
    required this.onRating,
    required this.onFavorite,
    required this.onSimilar,
  });
  final MediaItem item;
  final Future<void> Function(MediaItem, WatchStatus, {bool resetProgress})
  onSetStatus;
  final ValueChanged<MediaItem> onOpen;
  final Future<void> Function(MediaItem, double?) onRating;
  final void Function(MediaItem, bool) onFavorite;
  final ValueChanged<MediaItem> onSimilar;

  Future<void> _handle(BuildContext context, _LibraryAction action) async {
    switch (action) {
      case _LibraryAction.open:
        onOpen(item);
        return;
      case _LibraryAction.similar:
        onSimilar(item);
        return;
      case _LibraryAction.favorite:
        onFavorite(item, !item.isFavorite);
        return;
      case _LibraryAction.rate:
        final rating = await _showLibraryRatingDialog(context, item.userRating);
        if (rating == null) return;
        await onRating(item, rating == 0 ? null : rating);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(rating == 0 ? 'Оценка снята' : 'Оценка сохранена'),
            ),
          );
        }
        return;
      case _LibraryAction.remove:
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Удалить из коллекции?'),
            content: Text(
              '«${item.title}» исчезнет из статусов, а прогресс эпизодов будет очищен. Избранное останется отдельной отметкой.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Отмена'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Удалить'),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
        if (!context.mounted) return;
        await _saveStatus(context, WatchStatus.none, resetProgress: true);
        return;
      case _LibraryAction.planned:
        var resetProgress = false;
        if (item.watchedEpisodeCount > 0) {
          final choice = await _showLibraryProgressChoice(context);
          if (choice == null) return;
          resetProgress = choice;
        }
        if (!context.mounted) return;
        await _saveStatus(
          context,
          WatchStatus.planned,
          resetProgress: resetProgress,
        );
        return;
      case _LibraryAction.watching:
        await _saveStatus(context, WatchStatus.watching);
        return;
      case _LibraryAction.watched:
        await _saveStatus(context, WatchStatus.watched);
        return;
      case _LibraryAction.dropped:
        await _saveStatus(context, WatchStatus.dropped);
        return;
    }
  }

  Future<void> _saveStatus(
    BuildContext context,
    WatchStatus status, {
    bool resetProgress = false,
  }) async {
    try {
      await onSetStatus(item, status, resetProgress: resetProgress);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status == WatchStatus.none
                ? 'Удалено из коллекции'
                : 'Статус изменён: ${status.label}',
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Не удалось сохранить: $error')));
    }
  }

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface.withValues(alpha: .94),
    borderRadius: BorderRadius.circular(30),
    child: PopupMenuButton<_LibraryAction>(
      tooltip: 'Действия с произведением',
      icon: const Icon(Icons.more_horiz_rounded, size: 20),
      onSelected: (action) => _handle(context, action),
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: _LibraryAction.open,
          child: ListTile(
            leading: Icon(Icons.open_in_new_rounded),
            title: Text('Открыть карточку'),
          ),
        ),
        const PopupMenuItem(
          value: _LibraryAction.similar,
          child: ListTile(
            leading: Icon(Icons.hub_outlined),
            title: Text('Найти похожее'),
          ),
        ),
        PopupMenuItem(
          value: _LibraryAction.favorite,
          child: ListTile(
            leading: Icon(
              item.isFavorite
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
            ),
            title: Text(
              item.isFavorite ? 'Убрать из избранного' : 'В избранное',
            ),
          ),
        ),
        PopupMenuItem(
          value: _LibraryAction.rate,
          child: ListTile(
            leading: const Icon(Icons.star_outline_rounded),
            title: Text(
              item.userRating == null
                  ? 'Поставить оценку'
                  : 'Моя оценка: ${item.userRating!.toStringAsFixed(0)}',
            ),
          ),
        ),
        const PopupMenuDivider(),
        for (final entry in const [
          (_LibraryAction.planned, WatchStatus.planned),
          (_LibraryAction.watching, WatchStatus.watching),
          (_LibraryAction.watched, WatchStatus.watched),
          (_LibraryAction.dropped, WatchStatus.dropped),
        ])
          PopupMenuItem(
            value: entry.$1,
            child: ListTile(
              leading: Icon(
                item.status == entry.$2
                    ? Icons.check_circle_rounded
                    : Icons.circle_outlined,
                color: item.status == entry.$2 ? AppColors.accent : null,
              ),
              title: Text(entry.$2.label),
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: _LibraryAction.remove,
          child: ListTile(
            leading: Icon(Icons.delete_outline_rounded),
            title: Text('Удалить из коллекции'),
          ),
        ),
      ],
    ),
  );
}

Future<bool?> _showLibraryProgressChoice(BuildContext context) =>
    showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Перенести в планы'),
        content: const Text('Сохранить уже отмеченные эпизоды?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Сохранить'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Сбросить'),
          ),
        ],
      ),
    );

Future<double?> _showLibraryRatingDialog(
  BuildContext context,
  double? current,
) => showDialog<double>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('Моя оценка'),
    content: Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var rating = 1; rating <= 10; rating++)
          ChoiceChip(
            label: Text('$rating'),
            selected: current?.round() == rating,
            onSelected: (_) => Navigator.pop(context, rating.toDouble()),
          ),
      ],
    ),
    actions: [
      if (current != null)
        TextButton(
          onPressed: () => Navigator.pop(context, 0),
          child: const Text('Снять оценку'),
        ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Отмена'),
      ),
    ],
  ),
);

class _Summary extends StatelessWidget {
  const _Summary({required this.value, required this.label});
  final String value;
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.border),
    ),
    child: Text(
      '$value  $label',
      style: const TextStyle(fontWeight: FontWeight.w700),
    ),
  );
}

class _Empty extends StatelessWidget {
  const _Empty({required this.filtered});
  final bool filtered;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 70),
    child: Center(
      child: Column(
        children: [
          const Icon(
            Icons.bookmarks_outlined,
            size: 48,
            color: AppColors.muted,
          ),
          const SizedBox(height: 12),
          Text(
            filtered ? 'По этим фильтрам ничего нет' : 'Коллекция пока пуста',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          Text(
            filtered
                ? 'Измените статус, тип или поисковую строку.'
                : 'Добавьте первое реальное произведение из поиска.',
            style: const TextStyle(color: AppColors.muted),
          ),
        ],
      ),
    ),
  );
}
