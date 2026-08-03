import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/media_repository.dart';
import '../../models/media_item.dart';
import '../../models/remember_search.dart';
import '../app_theme.dart';
import '../widgets/poster_card.dart';

class RememberPage extends StatefulWidget {
  const RememberPage({
    super.key,
    required this.repository,
    required this.onOpen,
  });

  final MediaRepository repository;
  final ValueChanged<MediaItem> onOpen;

  @override
  State<RememberPage> createState() => _RememberPageState();
}

class _RememberPageState extends State<RememberPage> {
  final _query = TextEditingController();
  final _yearFrom = TextEditingController();
  final _yearTo = TextEditingController();
  final _country = TextEditingController();
  MediaKind? _type;
  String? _visualStyle;
  List<RememberCandidate> _candidates = const [];
  List<String> _warnings = const [];
  Map<String, dynamic> _ai = const {};
  RememberSearchFilters? _lastFilters;
  String? _error;
  bool _loading = false;
  bool _cardsMode = false;
  int _cardIndex = 0;

  @override
  void dispose() {
    _query.dispose();
    _yearFrom.dispose();
    _yearTo.dispose();
    _country.dispose();
    super.dispose();
  }

  Future<void> _search({RememberSearchFilters? filters}) async {
    final query = _query.text.trim();
    if (query.length < 8) {
      setState(
        () => _error = 'Опишите хотя бы несколько запомнившихся деталей.',
      );
      return;
    }
    final from = int.tryParse(_yearFrom.text.trim());
    final to = int.tryParse(_yearTo.text.trim());
    if (from != null && to != null && from > to) {
      setState(() => _error = 'Год «от» не может быть больше года «до».');
      return;
    }
    final request =
        filters ??
        RememberSearchFilters(
          query: query,
          type: _type,
          yearFrom: from,
          yearTo: to,
          country: _country.text,
          visualStyle: _visualStyle,
          excluded: _lastFilters?.excluded ?? const [],
        );
    setState(() {
      _loading = true;
      _error = null;
      _cardsMode = false;
    });
    try {
      final result = await widget.repository.rememberSearch(request);
      if (!mounted) return;
      setState(() {
        _lastFilters = request;
        _candidates = result.candidates;
        _warnings = result.warnings;
        _ai = result.ai;
        _cardIndex = 0;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _exclude(RememberCandidate candidate) {
    final filters = _lastFilters;
    if (filters == null) return;
    setState(() {
      _lastFilters = filters.copyWith(
        excluded: {...filters.excluded, candidate.key}.toList(),
      );
      _candidates = _candidates
          .where((item) => item.key != candidate.key)
          .toList();
      if (_cardIndex >= _candidates.length) _cardIndex = 0;
    });
  }

  Future<void> _similar(RememberCandidate candidate) async {
    final filters = _lastFilters;
    if (filters == null) return;
    await _search(
      filters: filters.copyWith(
        similarTo: RememberReference(
          source: candidate.source,
          sourceId: candidate.sourceId,
        ),
      ),
    );
  }

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
            Text('Вспомнить', style: Theme.of(context).textTheme.displaySmall),
            const SizedBox(height: 7),
            Text(
              'Опишите сюжет своими словами — названия в ответе будут только из TMDB и AniList',
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(color: AppColors.muted),
            ),
            const SizedBox(height: 24),
            _SearchForm(
              query: _query,
              yearFrom: _yearFrom,
              yearTo: _yearTo,
              country: _country,
              type: _type,
              visualStyle: _visualStyle,
              loading: _loading,
              onType: (value) => setState(() => _type = value),
              onVisualStyle: (value) => setState(() => _visualStyle = value),
              onSearch: () => _search(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              _RememberError(message: _error!, onRetry: () => _search()),
            ],
            if (_loading) ...[
              const SizedBox(height: 18),
              const LinearProgressIndicator(
                minHeight: 3,
                color: AppColors.accent,
              ),
              const SizedBox(height: 12),
              const Text(
                'Разбираем признаки и проверяем реальные каталоги…',
                style: TextStyle(color: AppColors.muted),
              ),
            ] else if (_candidates.isNotEmpty) ...[
              const SizedBox(height: 30),
              _ResultsHeader(
                count: _candidates.length,
                ai: _ai,
                cardsMode: _cardsMode,
                onToggleMode: () => setState(() => _cardsMode = !_cardsMode),
              ),
              if (_warnings.isNotEmpty) ...[
                const SizedBox(height: 12),
                _Warnings(messages: _warnings),
              ],
              const SizedBox(height: 18),
              if (_cardsMode)
                _CandidateDeck(
                  candidate: _candidates[_cardIndex % _candidates.length],
                  position: _cardIndex + 1,
                  total: _candidates.length,
                  onOpen: widget.onOpen,
                  onExclude: (candidate) {
                    _exclude(candidate);
                    if (_candidates.isNotEmpty) {
                      setState(() => _cardIndex %= _candidates.length);
                    }
                  },
                  onSimilar: _similar,
                  onNext: () => setState(
                    () => _cardIndex = (_cardIndex + 1) % _candidates.length,
                  ),
                )
              else
                _CandidateGrid(
                  candidates: _candidates,
                  onOpen: widget.onOpen,
                  onExclude: _exclude,
                  onSimilar: _similar,
                ),
            ] else if (_lastFilters != null && _error == null) ...[
              const SizedBox(height: 50),
              const _NoCandidates(),
            ] else ...[
              const SizedBox(height: 34),
              const _RememberIntro(),
            ],
          ],
        ),
      ),
    ),
  );
}

class _SearchForm extends StatelessWidget {
  const _SearchForm({
    required this.query,
    required this.yearFrom,
    required this.yearTo,
    required this.country,
    required this.type,
    required this.visualStyle,
    required this.loading,
    required this.onType,
    required this.onVisualStyle,
    required this.onSearch,
  });
  final TextEditingController query;
  final TextEditingController yearFrom;
  final TextEditingController yearTo;
  final TextEditingController country;
  final MediaKind? type;
  final String? visualStyle;
  final bool loading;
  final ValueChanged<MediaKind?> onType;
  final ValueChanged<String?> onVisualStyle;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 18 : 24),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: AppColors.border),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0C0F172A),
          blurRadius: 24,
          offset: Offset(0, 8),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Опишите всё, что помните',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: query,
          minLines: 5,
          maxLines: 9,
          maxLength: 1000,
          decoration: const InputDecoration(
            alignLabelWithHint: true,
            hintText:
                'Мультсериал примерно из 2000-х. Подростки попадали через порталы\nв другой мир, там были механические существа.',
          ),
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 760;
            final fields = [
              DropdownButtonFormField<MediaKind?>(
                initialValue: type,
                decoration: const InputDecoration(
                  labelText: 'Тип произведения',
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Любой тип')),
                  for (final kind in MediaKind.values)
                    DropdownMenuItem(value: kind, child: Text(kind.label)),
                ],
                onChanged: onType,
              ),
              Row(
                children: [
                  Expanded(
                    child: _YearField(controller: yearFrom, label: 'Год от'),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _YearField(controller: yearTo, label: 'Год до'),
                  ),
                ],
              ),
              TextField(
                controller: country,
                decoration: const InputDecoration(
                  labelText: 'Страна (необязательно)',
                  hintText: 'Например, Япония',
                ),
              ),
              DropdownButtonFormField<String?>(
                initialValue: visualStyle,
                decoration: const InputDecoration(labelText: 'Формат анимации'),
                items: const [
                  DropdownMenuItem(value: null, child: Text('Не указывать')),
                  DropdownMenuItem(value: '2d', child: Text('2D / рисованный')),
                  DropdownMenuItem(value: '3d', child: Text('3D')),
                  DropdownMenuItem(value: 'puppet', child: Text('Кукольный')),
                  DropdownMenuItem(value: 'unknown', child: Text('Неизвестно')),
                ],
                onChanged: onVisualStyle,
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
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final field in fields)
                  SizedBox(
                    width: (constraints.maxWidth - 12) / 2,
                    child: field,
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: loading ? null : onSearch,
          icon: const Icon(Icons.auto_awesome_rounded),
          label: const Text('Найти произведение'),
          style: FilledButton.styleFrom(
            minimumSize: const Size(220, 52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
          ),
        ),
      ],
    ),
  );
}

class _YearField extends StatelessWidget {
  const _YearField({required this.controller, required this.label});
  final TextEditingController controller;
  final String label;
  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    keyboardType: TextInputType.number,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    maxLength: 4,
    decoration: InputDecoration(labelText: label, counterText: ''),
  );
}

class _ResultsHeader extends StatelessWidget {
  const _ResultsHeader({
    required this.count,
    required this.ai,
    required this.cardsMode,
    required this.onToggleMode,
  });
  final int count;
  final Map<String, dynamic> ai;
  final bool cardsMode;
  final VoidCallback onToggleMode;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 14,
    runSpacing: 12,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Text(
        'Кандидаты · $count',
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      Chip(
        avatar: const Icon(Icons.psychology_alt_outlined, size: 17),
        label: Text(
          '${ai['provider'] ?? 'Fallback'} · ${ai['cacheHit'] == true ? 'из кэша' : ai['status'] ?? ''}',
        ),
      ),
      OutlinedButton.icon(
        onPressed: onToggleMode,
        icon: Icon(cardsMode ? Icons.grid_view_rounded : Icons.swipe_rounded),
        label: Text(
          cardsMode ? 'Показать сеткой' : 'Уточнить результаты карточками',
        ),
      ),
    ],
  );
}

class _CandidateGrid extends StatelessWidget {
  const _CandidateGrid({
    required this.candidates,
    required this.onOpen,
    required this.onExclude,
    required this.onSimilar,
  });
  final List<RememberCandidate> candidates;
  final ValueChanged<MediaItem> onOpen;
  final ValueChanged<RememberCandidate> onExclude;
  final Future<void> Function(RememberCandidate) onSimilar;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const gap = 16.0;
      final columns = constraints.maxWidth >= 1250
          ? 3
          : constraints.maxWidth >= 760
          ? 2
          : 1;
      final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final candidate in candidates)
            SizedBox(
              width: width,
              child: _CandidateCard(
                candidate: candidate,
                onOpen: onOpen,
                onExclude: onExclude,
                onSimilar: onSimilar,
              ),
            ),
        ],
      );
    },
  );
}

class _CandidateCard extends StatelessWidget {
  const _CandidateCard({
    super.key,
    required this.candidate,
    required this.onOpen,
    required this.onExclude,
    required this.onSimilar,
  });
  final RememberCandidate candidate;
  final ValueChanged<MediaItem> onOpen;
  final ValueChanged<RememberCandidate> onExclude;
  final Future<void> Function(RememberCandidate) onSimilar;

  @override
  Widget build(BuildContext context) {
    final item = candidate.toMediaItem();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 118,
                child: PosterArtwork(item: item, height: 168),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      candidate.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    if (candidate.originalTitle.isNotEmpty &&
                        candidate.originalTitle != candidate.title) ...[
                      const SizedBox(height: 4),
                      Text(
                        candidate.originalTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.muted),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text('${candidate.year} · ${candidate.type.label}'),
                    const SizedBox(height: 10),
                    _MatchBadge(score: candidate.matchScore),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          Text(
            candidate.overview.isEmpty
                ? 'Описание у источника пока отсутствует.'
                : candidate.overview,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.muted, height: 1.35),
          ),
          const SizedBox(height: 12),
          for (final reason in candidate.matchReasons.take(3))
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.check_rounded,
                    size: 16,
                    color: AppColors.accent,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(reason, style: const TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: () => onOpen(item),
                child: const Text('Это оно'),
              ),
              OutlinedButton(
                onPressed: () => onSimilar(candidate),
                child: const Text('Похоже'),
              ),
              TextButton(
                onPressed: () => onExclude(candidate),
                child: const Text('Не оно'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CandidateDeck extends StatelessWidget {
  const _CandidateDeck({
    required this.candidate,
    required this.position,
    required this.total,
    required this.onOpen,
    required this.onExclude,
    required this.onSimilar,
    required this.onNext,
  });
  final RememberCandidate candidate;
  final int position;
  final int total;
  final ValueChanged<MediaItem> onOpen;
  final ValueChanged<RememberCandidate> onExclude;
  final Future<void> Function(RememberCandidate) onSimilar;
  final VoidCallback onNext;
  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 680),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '$position из $total',
              style: const TextStyle(color: AppColors.muted),
            ),
          ),
          const SizedBox(height: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: _CandidateCard(
              key: ValueKey(candidate.key),
              candidate: candidate,
              onOpen: onOpen,
              onExclude: onExclude,
              onSimilar: onSimilar,
            ),
          ),
          const SizedBox(height: 14),
          TextButton.icon(
            onPressed: onNext,
            icon: const Icon(Icons.navigate_next_rounded),
            label: const Text('Следующий кандидат'),
          ),
        ],
      ),
    ),
  );
}

class _MatchBadge extends StatelessWidget {
  const _MatchBadge({required this.score});
  final double score;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: AppColors.accent.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      'Совпадение ${(score * 100).round()}%',
      style: const TextStyle(
        color: AppColors.accent,
        fontWeight: FontWeight.w800,
        fontSize: 12,
      ),
    ),
  );
}

class _RememberIntro extends StatelessWidget {
  const _RememberIntro();
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: AppColors.accent.withValues(alpha: .06),
      borderRadius: BorderRadius.circular(20),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.tips_and_updates_outlined, color: AppColors.accent),
        SizedBox(width: 12),
        Expanded(
          child: Text(
            'Полезны любые детали: примерный период, герои, место действия, визуальный стиль, отдельная сцена или канал, где вы это видели. AI извлекает только признаки — названия проверяются по каталогам.',
          ),
        ),
      ],
    ),
  );
}

class _NoCandidates extends StatelessWidget {
  const _NoCandidates();
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      children: [
        const Icon(
          Icons.manage_search_rounded,
          size: 48,
          color: AppColors.muted,
        ),
        const SizedBox(height: 12),
        Text(
          'Кандидатов не найдено',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 6),
        const Text(
          'Добавьте ещё одну сюжетную деталь или расширьте период.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.muted),
        ),
      ],
    ),
  );
}

class _RememberError extends StatelessWidget {
  const _RememberError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF4F1),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.coral.withValues(alpha: .3)),
    ),
    child: Row(
      children: [
        const Icon(Icons.error_outline_rounded, color: AppColors.coral),
        const SizedBox(width: 10),
        Expanded(child: Text(message)),
        TextButton(onPressed: onRetry, child: const Text('Повторить')),
      ],
    ),
  );
}

class _Warnings extends StatelessWidget {
  const _Warnings({required this.messages});
  final List<String> messages;
  @override
  Widget build(BuildContext context) => Text(
    messages.join('\n'),
    style: const TextStyle(color: AppColors.muted, fontSize: 13),
  );
}
