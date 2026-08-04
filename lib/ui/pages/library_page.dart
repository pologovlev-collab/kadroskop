import 'package:flutter/material.dart';

import '../../models/media_item.dart';
import '../app_theme.dart';
import '../widgets/adaptive_media_grid.dart';
import '../widgets/poster_card.dart';

enum LibrarySort { recent, title, yearNewest, rating }

class LibraryPage extends StatefulWidget {
  const LibraryPage({
    super.key,
    required this.items,
    required this.onOpen,
    required this.onSetStatus,
    required this.onFavorite,
  });
  final List<MediaItem> items;
  final ValueChanged<MediaItem> onOpen;
  final Future<void> Function(MediaItem, WatchStatus) onSetStatus;
  final void Function(MediaItem item, bool favorite) onFavorite;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  final _search = TextEditingController();
  WatchStatus? _status;
  MediaKind? _kind;
  LibrarySort _sort = LibrarySort.recent;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final values = widget.items.where((item) {
      return item.status != WatchStatus.none &&
          (_status == null || item.status == _status) &&
          (_kind == null || item.kind == _kind) &&
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
        values.sort((a, b) => b.rating.compareTo(a.rating));
        break;
    }
    final allSaved = widget.items
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
                  _Summary(value: '${allSaved.length}', label: 'всего'),
                  _Summary(
                    value:
                        '${allSaved.where((item) => item.status == WatchStatus.watching).length}',
                    label: 'смотрю',
                  ),
                  _Summary(
                    value:
                        '${allSaved.where((item) => item.status == WatchStatus.watched).length}',
                    label: 'просмотрено',
                  ),
                  _Summary(
                    value:
                        '${allSaved.where((item) => item.status == WatchStatus.planned).length}',
                    label: 'в планах',
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _Filters(
                search: _search,
                status: _status,
                kind: _kind,
                sort: _sort,
                onChanged: () => setState(() {}),
                onStatus: (value) => setState(() => _status = value),
                onKind: (value) => setState(() => _kind = value),
                onSort: (value) => setState(() => _sort = value),
              ),
              const SizedBox(height: 24),
              if (values.isEmpty)
                _Empty(filtered: allSaved.isNotEmpty)
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
                        ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: _StatusMenu(
                            item: item,
                            onSetStatus: widget.onSetStatus,
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
    required this.status,
    required this.kind,
    required this.sort,
    required this.onChanged,
    required this.onStatus,
    required this.onKind,
    required this.onSort,
  });
  final TextEditingController search;
  final WatchStatus? status;
  final MediaKind? kind;
  final LibrarySort sort;
  final VoidCallback onChanged;
  final ValueChanged<WatchStatus?> onStatus;
  final ValueChanged<MediaKind?> onKind;
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
              ChoiceChip(
                label: const Text('Все'),
                selected: status == null,
                onSelected: (_) => onStatus(null),
              ),
              for (final value in WatchStatus.values.where(
                (value) => value != WatchStatus.none,
              )) ...[
                const SizedBox(width: 8),
                ChoiceChip(
                  label: Text(value.label),
                  selected: status == value,
                  onSelected: (_) => onStatus(value),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 760;
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
                    child: Text('По рейтингу'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) onSort(value);
                },
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
                Expanded(child: fields[2]),
              ],
            );
          },
        ),
      ],
    ),
  );
}

class _StatusMenu extends StatelessWidget {
  const _StatusMenu({required this.item, required this.onSetStatus});
  final MediaItem item;
  final Future<void> Function(MediaItem, WatchStatus) onSetStatus;
  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface.withValues(alpha: .94),
    borderRadius: BorderRadius.circular(30),
    child: PopupMenuButton<WatchStatus>(
      tooltip: 'Изменить статус',
      icon: const Icon(Icons.more_horiz_rounded, size: 20),
      onSelected: (status) => onSetStatus(item, status),
      itemBuilder: (context) => [
        for (final status in WatchStatus.values.where(
          (status) => status != WatchStatus.none,
        ))
          PopupMenuItem(value: status, child: Text(status.label)),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: WatchStatus.none,
          child: Text('Удалить из коллекции'),
        ),
      ],
    ),
  );
}

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
