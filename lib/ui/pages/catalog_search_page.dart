import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/media_repository.dart';
import '../../models/media_item.dart';
import '../../models/remember_search.dart';
import '../app_theme.dart';
import '../widgets/adaptive_media_grid.dart';

class CatalogSearchPage extends StatefulWidget {
  const CatalogSearchPage({
    super.key,
    required this.repository,
    required this.onOpen,
    this.initialKind,
  });

  final MediaRepository repository;
  final ValueChanged<MediaItem> onOpen;
  final MediaKind? initialKind;

  @override
  State<CatalogSearchPage> createState() => _CatalogSearchPageState();
}

class _CatalogSearchPageState extends State<CatalogSearchPage> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<MediaItem> _results = const [];
  MediaKind? _kind;
  String? _error;
  List<String> _warnings = const [];
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _page = 1;
  int _requestGeneration = 0;

  @override
  void initState() {
    super.initState();
    _kind = widget.initialKind;
    _load(reset: true);
  }

  @override
  void didUpdateWidget(covariant CatalogSearchPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialKind != oldWidget.initialKind &&
        widget.initialKind != _kind) {
      _kind = widget.initialKind;
      _load(reset: true);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      _load(reset: true);
      return;
    }
    if (trimmed.length < 2) {
      setState(() {
        _results = const [];
        _error = null;
        _warnings = const [];
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 550), () {
      _load(reset: true);
    });
  }

  Future<void> _load({required bool reset}) async {
    final query = _controller.text.trim();
    if (query.isNotEmpty && query.length < 2) return;
    final generation = ++_requestGeneration;
    final nextPage = reset ? 1 : _page + 1;
    setState(() {
      if (reset) {
        _loading = true;
        _error = null;
      } else {
        _loadingMore = true;
      }
    });
    try {
      final CatalogPage page = query.isEmpty
          ? await widget.repository.loadPopular(kind: _kind, page: nextPage)
          : await widget.repository.searchCatalogPage(
              query,
              kind: _kind,
              page: nextPage,
            );
      if (!mounted || generation != _requestGeneration) return;
      final combined = reset ? page.items : [..._results, ...page.items];
      final unique = <String, MediaItem>{};
      for (final item in combined) {
        unique['${item.source}:${item.externalId ?? item.id}'] = item;
      }
      setState(() {
        _results = unique.values.toList();
        _warnings = page.warnings;
        _hasMore = page.hasMore;
        _page = page.page;
      });
    } catch (error) {
      if (mounted && generation == _requestGeneration) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted && generation == _requestGeneration) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _controller.text.trim();
    return _Page(
      title: 'Поиск',
      subtitle: 'Только реальные произведения из TMDB и AniList',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            onChanged: _onChanged,
            onSubmitted: (_) => _load(reset: true),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: 'Введите полное или неполное название',
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Очистить',
                      onPressed: () {
                        _controller.clear();
                        _load(reset: true);
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
            ),
          ),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('Всё'),
                  selected: _kind == null,
                  onSelected: (_) {
                    setState(() => _kind = null);
                    _load(reset: true);
                  },
                ),
                for (final kind in MediaKind.values) ...[
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: Text(kind.label),
                    selected: _kind == kind,
                    onSelected: (_) {
                      setState(() => _kind = kind);
                      _load(reset: true);
                    },
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 26),
          Row(
            children: [
              Expanded(
                child: Text(
                  query.isEmpty ? 'Популярное сейчас' : 'Результаты поиска',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
              if (!_loading)
                Text(
                  '${_results.length}',
                  style: const TextStyle(color: AppColors.muted),
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (_loading)
            const _LoadingCatalog()
          else if (_error != null)
            _CatalogError(message: _error!, onRetry: () => _load(reset: true))
          else if (_results.isEmpty)
            _CatalogEmpty(hasQuery: query.isNotEmpty)
          else ...[
            if (_warnings.isNotEmpty) ...[
              _WarningBanner(messages: _warnings),
              const SizedBox(height: 16),
            ],
            AdaptiveMediaGrid(items: _results, onOpen: widget.onOpen),
            if (_hasMore) ...[
              const SizedBox(height: 26),
              Center(
                child: OutlinedButton.icon(
                  onPressed: _loadingMore ? null : () => _load(reset: false),
                  icon: _loadingMore
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
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({
    required this.title,
    required this.subtitle,
    required this.child,
  });
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
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
            Text(title, style: Theme.of(context).textTheme.displaySmall),
            const SizedBox(height: 7),
            Text(
              subtitle,
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(color: AppColors.muted),
            ),
            const SizedBox(height: 24),
            child,
          ],
        ),
      ),
    ),
  );
}

class _LoadingCatalog extends StatelessWidget {
  const _LoadingCatalog();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 70),
    child: Center(child: CircularProgressIndicator(color: AppColors.accent)),
  );
}

class _CatalogError extends StatelessWidget {
  const _CatalogError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF4F1),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppColors.coral.withValues(alpha: .3)),
    ),
    child: Row(
      children: [
        const Icon(Icons.cloud_off_rounded, color: AppColors.coral),
        const SizedBox(width: 12),
        Expanded(child: Text(message)),
        TextButton(onPressed: onRetry, child: const Text('Повторить')),
      ],
    ),
  );
}

class _CatalogEmpty extends StatelessWidget {
  const _CatalogEmpty({required this.hasQuery});
  final bool hasQuery;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 64),
    child: Center(
      child: Column(
        children: [
          const Icon(
            Icons.search_off_rounded,
            size: 46,
            color: AppColors.muted,
          ),
          const SizedBox(height: 12),
          Text(
            hasQuery ? 'Ничего не найдено' : 'Популярное пока недоступно',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          Text(
            hasQuery
                ? 'Попробуйте более короткую часть названия или другой тип.'
                : 'Проверьте backend и состояние каталогов в профиле.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted),
          ),
        ],
      ),
    ),
  );
}

class _WarningBanner extends StatelessWidget {
  const _WarningBanner({required this.messages});
  final List<String> messages;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.butter.withValues(alpha: .35),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline_rounded, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(messages.join('\n'))),
      ],
    ),
  );
}
