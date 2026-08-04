import 'package:flutter/material.dart';

import '../../data/media_repository.dart';
import '../../models/media_item.dart';
import '../../models/similar_media.dart';
import '../app_theme.dart';
import '../widgets/adaptive_media_grid.dart';
import '../widgets/poster_card.dart';

class SimilarMediaSheet extends StatefulWidget {
  const SimilarMediaSheet({
    super.key,
    required this.reference,
    required this.repository,
    required this.onOpen,
    required this.onFavorite,
  });

  final MediaItem reference;
  final MediaRepository repository;
  final ValueChanged<MediaItem> onOpen;
  final void Function(MediaItem item, bool favorite) onFavorite;

  @override
  State<SimilarMediaSheet> createState() => _SimilarMediaSheetState();
}

class _SimilarMediaSheetState extends State<SimilarMediaSheet> {
  SimilarMode mode = SimilarMode.overall;
  List<SimilarMediaItem> items = const [];
  List<String> warnings = const [];
  String? guidance;
  String? error;
  bool loading = true;
  bool loadingMore = false;
  bool hasMore = false;
  int page = 1;
  int generation = 0;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({required bool reset, bool refresh = false}) async {
    final requestGeneration = ++generation;
    setState(() {
      if (reset) {
        loading = true;
        error = null;
      } else {
        loadingMore = true;
      }
    });
    try {
      final result = await widget.repository.loadSimilar(
        widget.reference,
        mode: mode,
        page: reset ? 1 : page + 1,
        refresh: refresh,
      );
      if (!mounted || generation != requestGeneration) return;
      final combined = reset ? result.items : [...items, ...result.items];
      final unique = <String, SimilarMediaItem>{};
      for (final item in combined) {
        unique['${item.media.source}:${item.media.externalId ?? item.media.id}'] =
            item;
      }
      setState(() {
        items = unique.values.toList();
        warnings = result.warnings;
        guidance = result.guidance;
        hasMore = result.hasMore;
        page = result.page;
      });
    } catch (value) {
      if (mounted && generation == requestGeneration) {
        setState(() => error = value.toString());
      }
    } finally {
      if (mounted && generation == requestGeneration) {
        setState(() {
          loading = false;
          loadingMore = false;
        });
      }
    }
  }

  void _selectMode(SimilarMode value) {
    if (mode == value) return;
    setState(() => mode = value);
    _load(reset: true);
  }

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.bottomCenter,
    child: Container(
      constraints: BoxConstraints(
        maxWidth: 1500,
        maxHeight: MediaQuery.sizeOf(context).height * .94,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 12, 22, 38),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Похожие на «${widget.reference.title}»',
                    style: Theme.of(context).textTheme.displaySmall,
                  ),
                ),
                IconButton(
                  tooltip: 'Закрыть',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 7),
            const Text(
              'Только реальные произведения из каталогов. Оценка похожести считается обычным кодом.',
              style: TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 18),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final value in SimilarMode.values.where(
                    (value) =>
                        value != SimilarMode.characters ||
                        widget.reference.source == 'tvmaze',
                  )) ...[
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        selected: mode == value,
                        label: Text(value.label),
                        onSelected: (_) => _selectMode(value),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 22),
            if (loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 70),
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.accent),
                ),
              )
            else if (error != null)
              _ErrorState(
                message: error!,
                onRetry: () => _load(reset: true, refresh: true),
              )
            else if (items.isEmpty)
              _EmptyState(
                message: guidance ?? 'Для выбранного режима ничего не найдено.',
              )
            else ...[
              if (warnings.isNotEmpty) ...[
                Text(
                  warnings.join('\n'),
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
                const SizedBox(height: 14),
              ],
              AdaptiveMediaGrid(
                items: items.map((item) => item.media).toList(),
                onOpen: (item) {
                  Navigator.pop(context);
                  widget.onOpen(item);
                },
                cardBuilder: (context, media, width) {
                  final result = items.firstWhere(
                    (item) => item.media.id == media.id,
                  );
                  return PosterCard(
                    item: media,
                    width: width,
                    onTap: () {
                      Navigator.pop(context);
                      widget.onOpen(media);
                    },
                    onFavorite: (favorite) =>
                        widget.onFavorite(media, favorite),
                    supportingText: result.reasons.firstOrNull,
                  );
                },
              ),
              if (hasMore) ...[
                const SizedBox(height: 24),
                Center(
                  child: OutlinedButton.icon(
                    onPressed: loadingMore ? null : () => _load(reset: false),
                    icon: loadingMore
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.expand_more_rounded),
                    label: const Text('Показать ещё'),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    ),
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 48),
    child: Center(
      child: Column(
        children: [
          const Icon(Icons.cloud_off_rounded, color: AppColors.coral, size: 38),
          const SizedBox(height: 10),
          Text(message, textAlign: TextAlign.center),
          TextButton(onPressed: onRetry, child: const Text('Повторить')),
        ],
      ),
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 60),
    child: Center(
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.muted),
      ),
    ),
  );
}
