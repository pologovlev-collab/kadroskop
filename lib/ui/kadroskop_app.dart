import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/media_repository.dart';
import '../data/episode_range_parser.dart';
import '../models/app_profile.dart';
import '../models/media_item.dart';
import '../models/recommendation.dart';
import 'app_theme.dart';
import 'pages/auth_page.dart';
import 'pages/catalog_search_page.dart';
import 'pages/home_page.dart';
import 'pages/library_page.dart';
import 'pages/profile_page.dart';
import 'pages/remember_page.dart';
import 'pages/similar_media_sheet.dart';
import 'widgets/poster_card.dart';

class KadroskopApp extends StatefulWidget {
  const KadroskopApp({super.key, required this.repository});

  final MediaRepository repository;

  @override
  State<KadroskopApp> createState() => _KadroskopAppState();
}

class _KadroskopAppState extends State<KadroskopApp> {
  AppProfile? _profile;
  bool _profileLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final profile = await widget.repository.loadProfile();
    if (mounted) {
      setState(() {
        _profile = profile;
        _profileLoaded = true;
      });
    }
  }

  Future<void> _logout() async {
    await widget.repository.logout();
    if (mounted) setState(() => _profile = null);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Кадроскоп',
    debugShowCheckedModeBanner: false,
    theme: buildTheme(),
    darkTheme: buildTheme(brightness: Brightness.dark),
    themeMode: _profile?.darkTheme == true ? ThemeMode.dark : ThemeMode.light,
    home: !_profileLoaded
        ? const Scaffold(body: Center(child: CircularProgressIndicator()))
        : _profile == null
        ? AuthPage(
            repository: widget.repository,
            onAuthenticated: (profile) => setState(() => _profile = profile),
          )
        : KadroskopShell(
            repository: widget.repository,
            profile: _profile!,
            onProfileChanged: (profile) => setState(() => _profile = profile),
            onLogout: _logout,
          ),
  );
}

class KadroskopShell extends StatefulWidget {
  const KadroskopShell({
    super.key,
    required this.repository,
    required this.profile,
    required this.onProfileChanged,
    required this.onLogout,
  });

  final MediaRepository repository;
  final AppProfile profile;
  final ValueChanged<AppProfile> onProfileChanged;
  final Future<void> Function() onLogout;

  @override
  State<KadroskopShell> createState() => _KadroskopShellState();
}

class _KadroskopShellState extends State<KadroskopShell> {
  int _index = 0;
  bool _loading = true;
  List<MediaItem> _items = const [];
  List<MediaItem> _popularItems = const [];
  List<RecommendationItem> _recommendations = const [];
  bool _recommendationsLoading = true;
  String? _recommendationsError;
  String? _recommendationsGuidance;
  MediaKind? _recommendationKind;
  MediaKind? _searchKind;

  static const _destinations = [
    (Icons.home_outlined, Icons.home_rounded, 'Главная'),
    (Icons.search_outlined, Icons.search_rounded, 'Поиск'),
    (Icons.bubble_chart_outlined, Icons.bubble_chart_rounded, 'Вспомнить'),
    (Icons.bookmarks_outlined, Icons.bookmarks_rounded, 'Коллекция'),
    (Icons.bar_chart_outlined, Icons.bar_chart_rounded, 'Статистика'),
    (Icons.person_outline_rounded, Icons.person_rounded, 'Профиль'),
  ];

  @override
  void initState() {
    super.initState();
    _reload();
    _loadPopular();
    _loadRecommendations();
  }

  Future<void> _reload() async {
    final items = await widget.repository.loadMedia();
    if (mounted) {
      setState(() {
        _items = items;
        _loading = false;
      });
    }
  }

  Future<void> _loadPopular() async {
    try {
      final page = await widget.repository.loadPopular();
      if (mounted) setState(() => _popularItems = page.items);
    } catch (_) {
      // The personalized section shows its own retryable backend state.
    }
  }

  Future<void> _setStatus(MediaItem item, WatchStatus status) async {
    await widget.repository.setStatus(item, status);
    await _reload();
    await _loadRecommendations(refresh: true);
  }

  Future<void> _setRating(MediaItem item, double? rating) async {
    await widget.repository.setRating(item, rating);
    await _reload();
    await _loadRecommendations(refresh: true);
  }

  Future<void> _setFavorite(MediaItem item, [bool? value]) async {
    await widget.repository.setFavorite(item, value ?? !item.isFavorite);
    await _reload();
    await _loadRecommendations(refresh: true);
  }

  Future<void> _loadRecommendations({bool refresh = false}) async {
    if (mounted) {
      setState(() {
        _recommendationsLoading = true;
        _recommendationsError = null;
      });
    }
    try {
      final result = await widget.repository.loadRecommendations(
        kind: _recommendationKind,
        refresh: refresh,
      );
      if (mounted) {
        setState(() {
          _recommendations = result.items;
          _recommendationsGuidance = result.guidance;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _recommendationsError = error.toString());
    } finally {
      if (mounted) setState(() => _recommendationsLoading = false);
    }
  }

  void _selectRecommendationKind(MediaKind? kind) {
    if (_recommendationKind == kind) return;
    setState(() => _recommendationKind = kind);
    _loadRecommendations();
  }

  Future<void> _openDetails(MediaItem item) async {
    widget.repository.recordInteraction(item, 'opened');
    var detailed = item;
    try {
      detailed = await widget.repository.loadDetails(item);
    } catch (_) {
      // The locally cached card remains useful when the backend is offline.
    }
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: 1100),
      builder: (context) => _DetailsSheet(
        item: detailed,
        repository: widget.repository,
        onStatus: (status) {
          Navigator.pop(context);
          _setStatus(detailed, status);
        },
        onEpisodesChanged: _reload,
        onRating: (rating) => _setRating(detailed, rating),
        onFavorite: (favorite) => _setFavorite(detailed, favorite),
        onSimilar: () {
          Navigator.pop(context);
          _showSimilar(detailed);
        },
      ),
    );
  }

  void _showSimilar(MediaItem item) {
    widget.repository.recordInteraction(item, 'similar_opened');
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: 1500),
      builder: (context) => SimilarMediaSheet(
        reference: item,
        repository: widget.repository,
        onOpen: _openDetails,
        onFavorite: _setFavorite,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppColors.accent)),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 900;
        final page = switch (_index) {
          0 => HomePage(
            savedItems: _items,
            popularItems: _popularItems,
            recommendations: _recommendations,
            loadingRecommendations: _recommendationsLoading,
            recommendationsError: _recommendationsError,
            recommendationsGuidance: _recommendationsGuidance,
            selectedKind: _recommendationKind,
            onOpen: _openDetails,
            onFavorite: _setFavorite,
            onSimilar: _showSimilar,
            onRecall: () => setState(() => _index = 2),
            onSelectKind: _selectRecommendationKind,
            onOpenSearch: () => setState(() {
              _searchKind = _recommendationKind;
              _index = 1;
            }),
            onLibrary: () => setState(() => _index = 3),
            onStatistics: () => setState(() => _index = 4),
            onRetryRecommendations: () => _loadRecommendations(refresh: true),
          ),
          1 => CatalogSearchPage(
            repository: widget.repository,
            initialKind: _searchKind,
            onOpen: _openDetails,
            onFavorite: _setFavorite,
            onSimilar: _showSimilar,
          ),
          2 => RememberPage(
            repository: widget.repository,
            onOpen: _openDetails,
            onFavorite: _setFavorite,
            onExploreSimilar: _showSimilar,
          ),
          3 => LibraryPage(
            items: _items,
            onOpen: _openDetails,
            onSetStatus: _setStatus,
            onFavorite: _setFavorite,
            onSimilar: _showSimilar,
          ),
          4 => _StatisticsPage(items: _items, repository: widget.repository),
          _ => ProfilePage(
            items: _items,
            repository: widget.repository,
            profile: widget.profile,
            onProfileChanged: widget.onProfileChanged,
            onCollectionChanged: _reload,
            onLogout: widget.onLogout,
          ),
        };
        return Scaffold(
          body: SafeArea(
            child: Row(
              children: [
                if (desktop)
                  _DesktopNavigation(
                    selectedIndex: _index,
                    onSelected: (value) => setState(() => _index = value),
                    destinations: _destinations,
                  ),
                Expanded(child: page),
              ],
            ),
          ),
          bottomNavigationBar: desktop
              ? null
              : NavigationBar(
                  selectedIndex: _index,
                  onDestinationSelected: (value) =>
                      setState(() => _index = value),
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  indicatorColor: AppColors.accent.withValues(alpha: .12),
                  labelBehavior:
                      NavigationDestinationLabelBehavior.onlyShowSelected,
                  destinations: [
                    for (final item in _destinations)
                      NavigationDestination(
                        icon: Icon(item.$1),
                        selectedIcon: Icon(item.$2),
                        label: item.$3,
                      ),
                  ],
                ),
        );
      },
    );
  }
}

class _DesktopNavigation extends StatelessWidget {
  const _DesktopNavigation({
    required this.selectedIndex,
    required this.onSelected,
    required this.destinations,
  });
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<(IconData, IconData, String)> destinations;

  @override
  Widget build(BuildContext context) => Container(
    width: 252,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      border: const Border(right: BorderSide(color: AppColors.border)),
    ),
    padding: const EdgeInsets.fromLTRB(18, 24, 18, 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Brand(),
        const SizedBox(height: 38),
        for (var i = 0; i < destinations.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: _NavButton(
              icon: i == selectedIndex
                  ? destinations[i].$2
                  : destinations[i].$1,
              label: destinations[i].$3,
              selected: i == selectedIndex,
              onTap: () => onSelected(i),
            ),
          ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.canvas,
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Row(
            children: [
              CircleAvatar(
                backgroundColor: AppColors.butter,
                child: Text(
                  'Л',
                  style: TextStyle(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Лев', style: TextStyle(fontWeight: FontWeight.w700)),
                    Text(
                      'Локальный профиль',
                      style: TextStyle(fontSize: 11, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _Brand extends StatelessWidget {
  const _Brand();
  @override
  Widget build(BuildContext context) => const Row(
    children: [
      _LogoMark(),
      SizedBox(width: 10),
      Expanded(
        child: Text(
          'Кадроскоп',
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            letterSpacing: -.6,
          ),
        ),
      ),
    ],
  );
}

class _LogoMark extends StatelessWidget {
  const _LogoMark();
  @override
  Widget build(BuildContext context) => Container(
    width: 32,
    height: 32,
    decoration: BoxDecoration(
      color: AppColors.ink,
      borderRadius: BorderRadius.circular(10),
    ),
    child: const Icon(
      Icons.bubble_chart_rounded,
      color: Colors.white,
      size: 21,
    ),
  );
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: selected ? AppColors.ink : Colors.transparent,
    borderRadius: BorderRadius.circular(14),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(
              icon,
              color: selected ? Colors.white : AppColors.muted,
              size: 21,
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                color: selected
                    ? Colors.white
                    : Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _PageFrame extends StatelessWidget {
  const _PageFrame({
    required this.child,
    this.title,
    this.subtitle,
    this.trailing,
  });
  final Widget child;
  final String? title;
  final String? subtitle;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => CustomScrollView(
    slivers: [
      SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            MediaQuery.sizeOf(context).width < 600 ? 18 : 34,
            22,
            MediaQuery.sizeOf(context).width < 600 ? 18 : 34,
            0,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1500),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (MediaQuery.sizeOf(context).width < 900) ...[
                    const _Brand(),
                    const SizedBox(height: 28),
                  ],
                  if (title != null)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title!,
                                style: Theme.of(context).textTheme.displaySmall,
                              ),
                              if (subtitle != null) ...[
                                const SizedBox(height: 7),
                                Text(
                                  subtitle!,
                                  style: Theme.of(context).textTheme.bodyLarge
                                      ?.copyWith(color: AppColors.muted),
                                ),
                              ],
                            ],
                          ),
                        ),
                        ?trailing,
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
      SliverPadding(
        padding: EdgeInsets.fromLTRB(
          MediaQuery.sizeOf(context).width < 600 ? 18 : 34,
          24,
          MediaQuery.sizeOf(context).width < 600 ? 18 : 34,
          40,
        ),
        sliver: SliverToBoxAdapter(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1500),
              child: child,
            ),
          ),
        ),
      ),
    ],
  );
}

// ignore: unused_element
class _HomePage extends StatelessWidget {
  const _HomePage({
    required this.items,
    required this.onOpen,
    required this.onRecall,
    required this.onSearch,
    required this.onLibrary,
    required this.onStatistics,
  });
  final List<MediaItem> items;
  final ValueChanged<MediaItem> onOpen;
  final VoidCallback onRecall;
  final VoidCallback onSearch;
  final VoidCallback onLibrary;
  final VoidCallback onStatistics;

  @override
  Widget build(BuildContext context) => _PageFrame(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HeroBanner(
          item: items.first,
          onRecall: onRecall,
          onOpen: () => onOpen(items.first),
        ),
        const SizedBox(height: 28),
        _KindsRow(onSelected: (_) => onSearch()),
        const SizedBox(height: 34),
        _SectionHeader(
          title: 'Для вас',
          action: 'Все рекомендации',
          onAction: onSearch,
        ),
        const SizedBox(height: 16),
        _PosterGrid(items: items.take(4).toList(), onOpen: onOpen),
        const SizedBox(height: 38),
        _SectionHeader(
          title: 'Ваша коллекция',
          action: 'Открыть коллекцию',
          onAction: onLibrary,
        ),
        const SizedBox(height: 16),
        _CollectionSummary(
          items: items,
          onLibrary: onLibrary,
          onStatistics: onStatistics,
        ),
        const SizedBox(height: 38),
        _SectionHeader(
          title: 'Редкие находки',
          action: 'Искать в каталоге',
          onAction: onSearch,
        ),
        const SizedBox(height: 16),
        _PosterGrid(items: items.skip(4).toList(), onOpen: onOpen),
      ],
    ),
  );
}

class _HeroBanner extends StatelessWidget {
  const _HeroBanner({
    required this.item,
    required this.onRecall,
    required this.onOpen,
  });
  final MediaItem item;
  final VoidCallback onRecall;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 720;
      return Container(
        constraints: BoxConstraints(minHeight: compact ? 490 : 360),
        decoration: BoxDecoration(
          color: const Color(0xFF102B32),
          borderRadius: BorderRadius.circular(28),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned.fill(child: CustomPaint(painter: _HeroPainter())),
            Padding(
              padding: EdgeInsets.all(compact ? 24 : 38),
              child: compact
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _HeroCopy(onRecall: onRecall),
                        const SizedBox(height: 28),
                        Align(
                          alignment: Alignment.centerRight,
                          child: SizedBox(
                            width: 160,
                            child: PosterArtwork(item: item, height: 210),
                          ),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(flex: 5, child: _HeroCopy(onRecall: onRecall)),
                        const SizedBox(width: 30),
                        Expanded(
                          flex: 3,
                          child: GestureDetector(
                            onTap: onOpen,
                            child: Transform.rotate(
                              angle: .035,
                              child: PosterArtwork(item: item, height: 285),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      );
    },
  );
}

class _HeroCopy extends StatelessWidget {
  const _HeroCopy({required this.onRecall});
  final VoidCallback onRecall;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(30),
        ),
        child: const Text(
          'ВАША КИНОПАМЯТЬ',
          style: TextStyle(
            color: Color(0xFFBCE4DC),
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.4,
          ),
        ),
      ),
      const SizedBox(height: 18),
      Text(
        'Найди то, что\nкогда-то смотрел',
        style: Theme.of(context).textTheme.displayLarge?.copyWith(
          color: Colors.white,
          fontSize: MediaQuery.sizeOf(context).width < 600 ? 38 : 54,
        ),
      ),
      const SizedBox(height: 17),
      Text(
        'Опиши один кадр, героя или настроение —\nмы соберём ленту возможных совпадений.',
        style: Theme.of(
          context,
        ).textTheme.bodyLarge?.copyWith(color: Colors.white70),
      ),
      const SizedBox(height: 26),
      FilledButton.icon(
        onPressed: onRecall,
        style: FilledButton.styleFrom(backgroundColor: AppColors.coral),
        icon: const Icon(Icons.auto_awesome_rounded),
        label: const Text('Помоги вспомнить'),
      ),
    ],
  );
}

class _HeroPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF2F766D).withValues(alpha: .35);
    canvas.drawCircle(
      Offset(size.width * .78, size.height * .12),
      size.width * .24,
      paint,
    );
    canvas.drawCircle(
      Offset(size.width * .93, size.height * .78),
      size.width * .18,
      paint..color = const Color(0xFFF3D37A).withValues(alpha: .17),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _KindsRow extends StatelessWidget {
  const _KindsRow({required this.onSelected});
  final ValueChanged<MediaKind> onSelected;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 84,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: MediaKind.values.length,
      separatorBuilder: (_, _) => const SizedBox(width: 10),
      itemBuilder: (context, i) {
        final kind = MediaKind.values[i];
        return Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            onTap: () => onSelected(kind),
            borderRadius: BorderRadius.circular(18),
            child: Container(
              width: 150,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: i == 0 ? AppColors.ink : AppColors.canvas,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      kind.icon,
                      color: i == 0 ? Colors.white : AppColors.ink,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      kind.label,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
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

class _PosterGrid extends StatelessWidget {
  const _PosterGrid({required this.items, required this.onOpen});
  final List<MediaItem> items;
  final ValueChanged<MediaItem> onOpen;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final gap = 16.0;
      final width = constraints.maxWidth < 600
          ? (constraints.maxWidth - gap) / 2
          : 168.0;
      return Wrap(
        spacing: gap,
        runSpacing: 24,
        children: [
          for (final item in items)
            PosterCard(item: item, onTap: () => onOpen(item), width: width),
        ],
      );
    },
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
    final saved = items
        .where((item) => item.status != WatchStatus.none)
        .toList();
    final watched = saved
        .where((item) => item.status == WatchStatus.watched)
        .length;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final values = Wrap(
            spacing: 26,
            runSpacing: 14,
            children: [
              _SummaryValue(value: '${saved.length}', label: 'в коллекции'),
              _SummaryValue(value: '$watched', label: 'просмотрено'),
              _SummaryValue(
                value: '${saved.expand((item) => item.genres).toSet().length}',
                label: 'жанров',
              ),
            ],
          );
          final buttons = Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
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
          );
          return constraints.maxWidth < 700
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [values, const SizedBox(height: 20), buttons],
                )
              : Row(
                  children: [
                    Expanded(child: values),
                    buttons,
                  ],
                );
        },
      ),
    );
  }
}

class _SummaryValue extends StatelessWidget {
  const _SummaryValue({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(value, style: Theme.of(context).textTheme.headlineMedium),
      Text(label, style: const TextStyle(color: AppColors.muted)),
    ],
  );
}

class _SearchPage extends StatefulWidget {
  const _SearchPage({
    required this.repository,
    required this.initialItems,
    required this.onOpen,
  });
  final MediaRepository repository;
  final List<MediaItem> initialItems;
  final ValueChanged<MediaItem> onOpen;
  @override
  State<_SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<_SearchPage> {
  Timer? _debounce;
  List<MediaItem> results = const [];
  String query = '';
  String? error;
  bool loading = false;
  MediaKind? selectedKind;

  @override
  void initState() {
    super.initState();
    results = widget.initialItems;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    query = value;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 420), _search);
  }

  Future<void> _search() async {
    if (!mounted) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final found = await widget.repository.searchCatalog(
        query,
        kind: selectedKind,
      );
      if (mounted) setState(() => results = found);
    } catch (exception) {
      if (mounted) setState(() => error = exception.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => _PageFrame(
    title: 'Поиск',
    subtitle:
        'TMDB и AniList: фильмы, сериалы, аниме и мультфильмы с обложками',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          onChanged: _onQueryChanged,
          onSubmitted: (_) => _search(),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search_rounded),
            hintText: 'Например: «мультфильм про робота в пустыне»',
            suffixIcon: Icon(Icons.travel_explore_rounded),
          ),
        ),
        const SizedBox(height: 14),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              ChoiceChip(
                label: const Text('Всё'),
                selected: selectedKind == null,
                onSelected: (_) {
                  setState(() => selectedKind = null);
                  _search();
                },
              ),
              for (final kind in MediaKind.values) ...[
                const SizedBox(width: 8),
                ChoiceChip(
                  label: Text(kind.label),
                  selected: selectedKind == kind,
                  onSelected: (_) {
                    setState(() => selectedKind = kind);
                    _search();
                  },
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 28),
        Row(
          children: [
            Text(
              query.trim().isEmpty ? 'Локальная подборка' : 'Найдено',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const Spacer(),
            Text(
              '${results.length} совпадений',
              style: const TextStyle(color: AppColors.muted),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (loading)
          const LinearProgressIndicator(minHeight: 3, color: AppColors.accent)
        else if (error != null)
          _SearchError(message: error!, onRetry: _search)
        else if (results.isEmpty)
          const _EmptyState(
            icon: Icons.search_off_rounded,
            title: 'Ничего не нашлось',
            text: 'Попробуйте изменить формулировку или убрать часть фильтров.',
          )
        else
          _PosterGrid(items: results, onOpen: widget.onOpen),
      ],
    ),
  );
}

class _SearchError extends StatelessWidget {
  const _SearchError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(22),
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

class _RecallPage extends StatefulWidget {
  const _RecallPage({
    required this.items,
    required this.repository,
    required this.onOpen,
  });
  final List<MediaItem> items;
  final MediaRepository repository;
  final ValueChanged<MediaItem> onOpen;
  @override
  State<_RecallPage> createState() => _RecallPageState();
}

class _RecallPageState extends State<_RecallPage> {
  int cursor = 0;
  int reviewed = 0;

  void react(String event) {
    final item = widget.items[cursor % widget.items.length];
    widget.repository.recordInteraction(item, event);
    setState(() {
      cursor++;
      reviewed++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.items[cursor % widget.items.length];
    return _PageFrame(
      title: 'Возможно, это оно?',
      subtitle: 'Лента учится после каждого ответа',
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(
          '$reviewed просмотрено',
          style: Theme.of(context).textTheme.labelLarge,
        ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            children: [
              GestureDetector(
                onTap: () => widget.onOpen(item),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(
                      scale: Tween(begin: .97, end: 1.0).animate(animation),
                      child: child,
                    ),
                  ),
                  child: Container(
                    key: ValueKey(item.id),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: AppColors.border),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x120F172A),
                          blurRadius: 28,
                          offset: Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        PosterArtwork(
                          item: item,
                          height: MediaQuery.sizeOf(context).width < 600
                              ? 330
                              : 400,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          item.title,
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '${item.year} · ${item.kind.label} · ${item.genres.join(' / ')}',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: AppColors.muted),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          item.description,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 12,
                children: [
                  _ReactionButton(
                    icon: Icons.close_rounded,
                    label: 'Не смотрел',
                    color: AppColors.coral,
                    onTap: () => react('not_watched'),
                  ),
                  _ReactionButton(
                    icon: Icons.question_mark_rounded,
                    label: 'Возможно',
                    color: const Color(0xFFE5A62F),
                    onTap: () => react('maybe'),
                  ),
                  _ReactionButton(
                    icon: Icons.check_rounded,
                    label: 'Смотрел',
                    color: AppColors.accent,
                    onTap: () => react('watched'),
                  ),
                  _ReactionButton(
                    icon: Icons.schedule_rounded,
                    label: 'Позже',
                    color: AppColors.muted,
                    onTap: () => react('later'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReactionButton extends StatelessWidget {
  const _ReactionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onTap,
    icon: Icon(icon, color: color),
    label: Text(label),
    style: OutlinedButton.styleFrom(
      foregroundColor: AppColors.ink,
      backgroundColor: Colors.white,
      side: const BorderSide(color: AppColors.border),
      padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}

// ignore: unused_element
class _LibraryPage extends StatelessWidget {
  const _LibraryPage({required this.items, required this.onOpen});
  final List<MediaItem> items;
  final ValueChanged<MediaItem> onOpen;
  @override
  Widget build(BuildContext context) {
    final saved = items.where((e) => e.status != WatchStatus.none).toList();
    return _PageFrame(
      title: 'Моя коллекция',
      subtitle: 'Всё, что вы смотрите, планируете и уже нашли',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _StatPill(value: '${saved.length}', label: 'в коллекции'),
              _StatPill(
                value:
                    '${saved.where((e) => e.status == WatchStatus.watched).length}',
                label: 'просмотрено',
              ),
              _StatPill(
                value:
                    '${saved.where((e) => e.status == WatchStatus.planned).length}',
                label: 'в планах',
              ),
            ],
          ),
          const SizedBox(height: 28),
          if (saved.isEmpty)
            const _EmptyState(
              icon: Icons.bookmark_add_outlined,
              title: 'Коллекция пока пуста',
              text: 'Откройте карточку и добавьте первый тайтл в планы.',
            )
          else
            _PosterGrid(items: saved, onOpen: onOpen),
        ],
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({required this.value, required this.label});
  final String value;
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.border),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(width: 7),
        Text(label, style: const TextStyle(color: AppColors.muted)),
      ],
    ),
  );
}

class _StatisticsPage extends StatefulWidget {
  const _StatisticsPage({required this.items, required this.repository});
  final List<MediaItem> items;
  final MediaRepository repository;

  @override
  State<_StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<_StatisticsPage> {
  MediaKind? selectedKind;
  String? selectedGenre;
  bool onlyWatched = true;
  Map<String, int> activityByMonth = const {};

  @override
  void initState() {
    super.initState();
    _loadActivity();
  }

  @override
  void didUpdateWidget(covariant _StatisticsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items != widget.items) _loadActivity();
  }

  Future<void> _loadActivity() async {
    final activity = await widget.repository.loadActivityByMonth();
    if (mounted) {
      setState(() => activityByMonth = activity);
    }
  }

  @override
  Widget build(BuildContext context) {
    final genres = widget.items.expand((item) => item.genres).toSet().toList()
      ..sort();
    final filtered = widget.items.where((item) {
      final hasWatchedContent = item.isEpisodic
          ? item.watchedEpisodeCount > 0
          : item.status == WatchStatus.watched;
      return (!onlyWatched || hasWatchedContent) &&
          (selectedKind == null || item.kind == selectedKind) &&
          (selectedGenre == null || item.genres.contains(selectedGenre));
    }).toList();
    final episodes = filtered.fold<int>(0, (sum, item) {
      if (!item.isEpisodic) return sum;
      return sum + item.watchedEpisodeCount;
    });
    final minutes = filtered.fold<int>(0, (sum, item) {
      if (!item.isEpisodic) {
        return sum +
            (item.status == WatchStatus.watched ? item.runtimeMinutes : 0);
      }
      return sum + item.watchedMinutes;
    });
    final rated = filtered.where((item) => item.userRating != null).toList();
    final average = rated.isEmpty
        ? null
        : rated.fold<double>(0, (sum, item) => sum + item.userRating!) /
              rated.length;
    final films = filtered.where((item) => item.kind == MediaKind.movie).length;
    final series = filtered
        .where(
          (item) =>
              item.kind == MediaKind.series ||
              item.kind == MediaKind.animatedSeries,
        )
        .length;
    final anime = filtered.where((item) => item.kind == MediaKind.anime).length;

    return _PageFrame(
      title: 'Статистика коллекции',
      subtitle: 'Произведения, эпизоды, жанры и время — без функции просмотра',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StatisticsFilters(
            selectedKind: selectedKind,
            selectedGenre: selectedGenre,
            genres: genres,
            onlyWatched: onlyWatched,
            onKind: (value) => setState(() => selectedKind = value),
            onGenre: (value) => setState(() => selectedGenre = value),
            onOnlyWatched: (value) => setState(() => onlyWatched = value),
          ),
          const SizedBox(height: 22),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 920
                  ? 4
                  : constraints.maxWidth >= 520
                  ? 2
                  : 1;
              final width =
                  (constraints.maxWidth - 14 * (columns - 1)) / columns;
              return Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  _MetricCard(
                    width: width,
                    icon: Icons.check_circle_outline,
                    value: '${filtered.length}',
                    label: 'произведений',
                  ),
                  _MetricCard(
                    width: width,
                    icon: Icons.movie_outlined,
                    value: '$films',
                    label: 'фильмов',
                  ),
                  _MetricCard(
                    width: width,
                    icon: Icons.live_tv_outlined,
                    value: '$series',
                    label: 'сериалов',
                  ),
                  _MetricCard(
                    width: width,
                    icon: Icons.auto_awesome_outlined,
                    value: '$anime',
                    label: 'аниме',
                  ),
                  _MetricCard(
                    width: width,
                    icon: Icons.schedule_rounded,
                    value: _formatDuration(minutes),
                    label: 'общее время',
                  ),
                  _MetricCard(
                    width: width,
                    icon: Icons.view_carousel_outlined,
                    value: '$episodes',
                    label: 'эпизодов',
                  ),
                  _MetricCard(
                    width: width,
                    icon: Icons.star_outline_rounded,
                    value: average?.toStringAsFixed(1) ?? '—',
                    label: 'средняя ваша оценка',
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 28),
          LayoutBuilder(
            builder: (context, constraints) {
              final kinds = {
                for (final kind in MediaKind.values)
                  kind: filtered.where((item) => item.kind == kind).length,
              };
              final genreCounts = <String, int>{};
              final yearCounts = <String, int>{};
              for (final item in filtered) {
                for (final genre in item.genres) {
                  genreCounts.update(
                    genre,
                    (value) => value + 1,
                    ifAbsent: () => 1,
                  );
                }
                if (item.year > 0) {
                  final decade = '${item.year ~/ 10 * 10}-е';
                  yearCounts.update(
                    decade,
                    (value) => value + 1,
                    ifAbsent: () => 1,
                  );
                }
              }
              final cards = [
                _KindBars(values: kinds),
                _GenreChart(values: genreCounts),
                _SimpleBars(title: 'По годам', values: yearCounts),
                _SimpleBars(
                  title: 'Активность по месяцам',
                  values: activityByMonth,
                ),
              ];
              final columns = constraints.maxWidth < 760 ? 1 : 2;
              final width =
                  (constraints.maxWidth - 14 * (columns - 1)) / columns;
              return Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  for (final card in cards) SizedBox(width: width, child: card),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _StatisticsFilters extends StatelessWidget {
  const _StatisticsFilters({
    required this.selectedKind,
    required this.selectedGenre,
    required this.genres,
    required this.onlyWatched,
    required this.onKind,
    required this.onGenre,
    required this.onOnlyWatched,
  });
  final MediaKind? selectedKind;
  final String? selectedGenre;
  final List<String> genres;
  final bool onlyWatched;
  final ValueChanged<MediaKind?> onKind;
  final ValueChanged<String?> onGenre;
  final ValueChanged<bool> onOnlyWatched;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AppColors.border),
    ),
    child: Wrap(
      spacing: 10,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ChoiceChip(
          label: const Text('Все типы'),
          selected: selectedKind == null,
          onSelected: (_) => onKind(null),
        ),
        for (final kind in MediaKind.values)
          ChoiceChip(
            label: Text(kind.label),
            selected: selectedKind == kind,
            onSelected: (_) => onKind(kind),
          ),
        SizedBox(
          width: 190,
          child: DropdownButtonFormField<String?>(
            isExpanded: true,
            initialValue: selectedGenre,
            decoration: const InputDecoration(labelText: 'Жанр', isDense: true),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('Все жанры'),
              ),
              for (final genre in genres)
                DropdownMenuItem<String?>(
                  value: genre,
                  child: Text(genre, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: onGenre,
          ),
        ),
        FilterChip(
          label: const Text('Только просмотренное'),
          selected: onlyWatched,
          onSelected: onOnlyWatched,
        ),
      ],
    ),
  );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.width,
    required this.icon,
    required this.value,
    required this.label,
  });
  final double width;
  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.accent),
        const SizedBox(height: 16),
        Text(value, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 3),
        Text(label, style: const TextStyle(color: AppColors.muted)),
      ],
    ),
  );
}

class _KindBars extends StatelessWidget {
  const _KindBars({required this.values});
  final Map<MediaKind, int> values;

  @override
  Widget build(BuildContext context) {
    final maximum = values.values.fold<int>(
      1,
      (max, value) => value > max ? value : max,
    );
    return _ChartCard(
      title: 'По типам',
      child: Column(
        children: [
          for (final entry in values.entries) ...[
            Row(
              children: [
                Expanded(child: Text(entry.key.label)),
                Text(
                  '${entry.value}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 7),
            LinearProgressIndicator(
              value: entry.value / maximum,
              minHeight: 8,
              borderRadius: BorderRadius.circular(20),
              backgroundColor: AppColors.border,
              color: _kindColor(entry.key),
            ),
            const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }
}

class _GenreChart extends StatelessWidget {
  const _GenreChart({required this.values});
  final Map<String, int> values;

  @override
  Widget build(BuildContext context) {
    final entries = values.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = entries.take(5).toList();
    return _ChartCard(
      title: 'По жанрам',
      child: Row(
        children: [
          SizedBox(
            width: 126,
            height: 126,
            child: CustomPaint(
              painter: _DonutPainter(top.map((entry) => entry.value).toList()),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              children: [
                for (var i = 0; i < top.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 9),
                    child: Row(
                      children: [
                        Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            color: _chartColors[i % _chartColors.length],
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            top[i].key,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '${top[i].value}',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SimpleBars extends StatelessWidget {
  const _SimpleBars({required this.title, required this.values});
  final String title;
  final Map<String, int> values;

  @override
  Widget build(BuildContext context) {
    final entries = values.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final shown = entries.length > 8
        ? entries.sublist(entries.length - 8)
        : entries;
    final maximum = shown.fold<int>(
      1,
      (max, entry) => entry.value > max ? entry.value : max,
    );
    return _ChartCard(
      title: title,
      child: shown.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(
                child: Text(
                  'Пока недостаточно данных',
                  style: TextStyle(color: AppColors.muted),
                ),
              ),
            )
          : Column(
              children: [
                for (final entry in shown) ...[
                  Row(
                    children: [
                      Expanded(child: Text(entry.key)),
                      Text(
                        '${entry.value}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    value: entry.value / maximum,
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(20),
                    backgroundColor: AppColors.border,
                    color: AppColors.accent,
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 20),
        child,
      ],
    ),
  );
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.values);
  final List<int> values;

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<int>(0, (sum, value) => sum + value);
    final rect = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 22;
    if (total == 0) {
      canvas.drawArc(
        rect.deflate(13),
        0,
        6.283,
        false,
        paint..color = AppColors.border,
      );
      return;
    }
    var start = -1.5708;
    for (var i = 0; i < values.length; i++) {
      final sweep = 6.283 * values[i] / total;
      canvas.drawArc(
        rect.deflate(13),
        start,
        sweep - .035,
        false,
        paint..color = _chartColors[i % _chartColors.length],
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) =>
      oldDelegate.values != values;
}

String _formatDuration(int minutes) {
  if (minutes < 60) return '$minutes мин';
  final hours = minutes ~/ 60;
  if (hours < 24) return '$hours ч ${minutes % 60} мин';
  return '${hours ~/ 24} д ${hours % 24} ч';
}

Color _kindColor(MediaKind kind) => switch (kind) {
  MediaKind.movie => AppColors.accent,
  MediaKind.series => AppColors.coral,
  MediaKind.anime => const Color(0xFF8056A8),
  MediaKind.cartoon => const Color(0xFFE5A62F),
  MediaKind.animatedSeries => const Color(0xFF3285A8),
  MediaKind.documentary => const Color(0xFF68846C),
};

const _chartColors = [
  AppColors.accent,
  AppColors.coral,
  Color(0xFF8056A8),
  Color(0xFFE5A62F),
  Color(0xFF3285A8),
];

// ignore: unused_element
class _ProfilePage extends StatelessWidget {
  const _ProfilePage({required this.items});
  final List<MediaItem> items;
  @override
  Widget build(BuildContext context) => _PageFrame(
    title: 'Профиль вкуса',
    subtitle: 'Локально на этом устройстве',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.ink,
            borderRadius: BorderRadius.circular(24),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 620;
              final identity = const Row(
                children: [
                  CircleAvatar(
                    radius: 34,
                    backgroundColor: AppColors.butter,
                    child: Text(
                      'Л',
                      style: TextStyle(
                        fontSize: 25,
                        color: AppColors.ink,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Лев',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Исследователь кино',
                        style: TextStyle(color: Colors.white60),
                      ),
                    ],
                  ),
                ],
              );
              final stats = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _DarkStat(
                    value:
                        '${items.where((e) => e.status != WatchStatus.none).length}',
                    label: 'в коллекции',
                  ),
                  const SizedBox(width: 28),
                  const _DarkStat(value: '6', label: 'любимых жанров'),
                ],
              );
              return compact
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [identity, const SizedBox(height: 26), stats],
                    )
                  : Row(children: [identity, const Spacer(), stats]);
            },
          ),
        ),
        const SizedBox(height: 30),
        Text(
          'Ваши предпочтения',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 14),
        const Wrap(
          spacing: 9,
          runSpacing: 9,
          children: [
            _TasteTag('Фантастика', AppColors.accent),
            _TasteTag('Приключения', AppColors.coral),
            _TasteTag('Аниме 2000-х', Color(0xFF8056A8)),
            _TasteTag('Тихие драмы', Color(0xFF4A6B83)),
            _TasteTag('Космос', Color(0xFF245A9C)),
            _TasteTag('Редкие тайтлы', Color(0xFF8A6B27)),
          ],
        ),
        const SizedBox(height: 34),
        Text('Настройки', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 12),
        const _SettingsCard(),
      ],
    ),
  );
}

class _DarkStat extends StatelessWidget {
  const _DarkStat({required this.value, required this.label});
  final String value;
  final String label;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        value,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 26,
          fontWeight: FontWeight.w900,
        ),
      ),
      Text(label, style: const TextStyle(color: Colors.white60, fontSize: 12)),
    ],
  );
}

class _TasteTag extends StatelessWidget {
  const _TasteTag(this.text, this.color);
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .10),
      borderRadius: BorderRadius.circular(30),
      border: Border.all(color: color.withValues(alpha: .3)),
    ),
    child: Text(
      text,
      style: TextStyle(color: color, fontWeight: FontWeight.w700),
    ),
  );
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard();
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(
      children: [
        ListTile(
          onTap: () => _showInfo(
            context,
            'Локальная база',
            'Коллекция, отметки серий и история действий хранятся в SQLite на этом устройстве.',
          ),
          leading: const Icon(Icons.storage_outlined),
          title: const Text('Локальная база'),
          subtitle: const Text('SQLite · данные хранятся на устройстве'),
          trailing: const Icon(Icons.chevron_right_rounded),
        ),
        const Divider(height: 1, indent: 56),
        ListTile(
          onTap: () => _showInfo(
            context,
            'Профиль вкуса',
            'Предпочтения обновляются по вашим оценкам, поиску и ответам в ленте «Помоги вспомнить».',
          ),
          leading: const Icon(Icons.tune_rounded),
          title: const Text('Настроить вкус'),
          subtitle: const Text('Жанры, годы и настроение'),
          trailing: const Icon(Icons.chevron_right_rounded),
        ),
        const Divider(height: 1, indent: 56),
        ListTile(
          onTap: () => _showInfo(
            context,
            'Внешний вид',
            'Сейчас используется светлая тема Кадроскопа. Тёмная тема появится в следующем этапе.',
          ),
          leading: const Icon(Icons.palette_outlined),
          title: const Text('Внешний вид'),
          subtitle: const Text('Светлая тема'),
          trailing: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    ),
  );
}

void _showInfo(BuildContext context, String title, String text) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(text),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Понятно'),
        ),
      ],
    ),
  );
}

Future<void> _showRatingDialog(
  BuildContext context,
  double? current,
  Future<void> Function(double? rating) onRating,
) async {
  final rating = await showDialog<double?>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Ваша оценка'),
      content: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var value = 1; value <= 10; value++)
            ChoiceChip(
              label: Text('$value'),
              selected: current?.round() == value,
              onSelected: (_) => Navigator.pop(context, value.toDouble()),
            ),
        ],
      ),
      actions: [
        if (current != null)
          TextButton(
            onPressed: () => Navigator.pop(context, 0.0),
            child: const Text('Удалить оценку'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
      ],
    ),
  );
  if (rating == null) return;
  await onRating(rating == 0 ? null : rating);
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.text,
  });
  final IconData icon;
  final String title;
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(42),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(
      children: [
        Icon(icon, size: 42, color: AppColors.muted),
        const SizedBox(height: 15),
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.muted),
        ),
      ],
    ),
  );
}

class _DetailsSheet extends StatelessWidget {
  const _DetailsSheet({
    required this.item,
    required this.repository,
    required this.onStatus,
    required this.onEpisodesChanged,
    required this.onRating,
    required this.onFavorite,
    required this.onSimilar,
  });
  final MediaItem item;
  final MediaRepository repository;
  final ValueChanged<WatchStatus> onStatus;
  final Future<void> Function() onEpisodesChanged;
  final Future<void> Function(double? rating) onRating;
  final Future<void> Function(bool favorite) onFavorite;
  final VoidCallback onSimilar;

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * .92;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        constraints: BoxConstraints(maxWidth: 1040, maxHeight: height),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 36),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  tooltip: 'Закрыть',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
              if (item.backdropUrl case final backdrop?) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: SizedBox(
                    height: 150,
                    width: double.infinity,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(
                          backdrop,
                          key: const ValueKey('details-backdrop'),
                          fit: BoxFit.cover,
                          cacheWidth: 1200,
                          filterQuality: FilterQuality.low,
                          errorBuilder: (_, _, _) => const SizedBox.shrink(),
                        ),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Color(0x22000000), Color(0xCC000000)],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
              ],
              LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 640;
                  final posterWidth = compact ? 200.0 : 290.0;
                  final art = Center(
                    child: SizedBox(
                      width: posterWidth,
                      child: Hero(
                        tag: 'poster-${item.id}',
                        child: PosterArtwork(
                          key: const ValueKey('details-poster'),
                          item: item,
                          height: posterWidth * 1.5,
                          showTitle: item.posterUrl == null,
                        ),
                      ),
                    ),
                  );
                  final copy = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.accent.withValues(alpha: .1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              item.kind.label,
                              style: const TextStyle(
                                color: AppColors.accent,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        item.title,
                        style: Theme.of(context).textTheme.displaySmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${item.year} · ★ ${item.rating.toStringAsFixed(1)} · ${item.genres.join(' / ')}',
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 22),
                      if (item.totalRuntimeMinutes > 0) ...[
                        Text(
                          item.isEpisodic
                              ? '${item.seasons.isEmpty ? '${item.episodeCount} эп.' : '${item.seasonCount} сез. · ${item.episodeCount} эп.'} · примерно ${_formatDuration(item.totalRuntimeMinutes)}'
                              : 'Длительность: ${_formatDuration(item.runtimeMinutes)}',
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      Text(
                        item.description,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 26),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          FilledButton.icon(
                            onPressed: item.isEpisodic
                                ? () async {
                                    await repository.setAllEpisodesWatched(
                                      item,
                                      true,
                                    );
                                    await onEpisodesChanged();
                                  }
                                : () => onStatus(WatchStatus.watched),
                            icon: const Icon(Icons.check_rounded),
                            label: Text(
                              item.isEpisodic ? 'Смотрел всё' : 'Смотрел',
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => onStatus(WatchStatus.planned),
                            icon: const Icon(Icons.bookmark_add_outlined),
                            label: const Text('В планы'),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, 48),
                              side: const BorderSide(color: AppColors.border),
                              foregroundColor: Theme.of(
                                context,
                              ).colorScheme.onSurface,
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.surface,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                          if (item.isEpisodic)
                            OutlinedButton.icon(
                              onPressed: () => onStatus(WatchStatus.watching),
                              icon: const Icon(Icons.playlist_play_rounded),
                              label: const Text('Смотрю'),
                            ),
                          OutlinedButton.icon(
                            onPressed: () => _showRatingDialog(
                              context,
                              item.userRating,
                              onRating,
                            ),
                            icon: const Icon(Icons.star_outline_rounded),
                            label: Text(
                              item.userRating == null
                                  ? 'Оценить'
                                  : 'Моя оценка ${item.userRating!.toStringAsFixed(0)}',
                            ),
                          ),
                          _FavoriteAction(
                            initialValue: item.isFavorite,
                            onChanged: onFavorite,
                          ),
                          OutlinedButton.icon(
                            onPressed: onSimilar,
                            icon: const Icon(Icons.hub_outlined),
                            label: const Text('Похожее'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 30),
                      if (item.isEpisodic) ...[
                        _EpisodeSelector(
                          item: item,
                          repository: repository,
                          onChanged: onEpisodesChanged,
                        ),
                        const SizedBox(height: 22),
                      ],
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.auto_awesome_rounded,
                              color: AppColors.coral,
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Почему это в подборке',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  SizedBox(height: 5),
                                  Text(
                                    'Совпадает с вашими любимыми жанрами и периодом, который вы часто ищете.',
                                    style: TextStyle(
                                      color: AppColors.muted,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                  return compact
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [art, const SizedBox(height: 18), copy],
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            art,
                            const SizedBox(width: 30),
                            Expanded(child: copy),
                          ],
                        );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FavoriteAction extends StatefulWidget {
  const _FavoriteAction({required this.initialValue, required this.onChanged});

  final bool initialValue;
  final Future<void> Function(bool value) onChanged;

  @override
  State<_FavoriteAction> createState() => _FavoriteActionState();
}

class _FavoriteActionState extends State<_FavoriteAction> {
  late bool value = widget.initialValue;
  bool saving = false;

  Future<void> _toggle() async {
    if (saving) return;
    final next = !value;
    setState(() {
      value = next;
      saving = true;
    });
    try {
      await widget.onChanged(next);
    } catch (_) {
      if (mounted) {
        setState(() => value = !next);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось изменить избранное.')),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: saving ? null : _toggle,
    icon: Icon(
      value ? Icons.favorite_rounded : Icons.favorite_border_rounded,
      color: value ? Colors.redAccent : null,
    ),
    label: Text(value ? 'В избранном' : 'В избранное'),
  );
}

class _EpisodeSelector extends StatefulWidget {
  const _EpisodeSelector({
    required this.item,
    required this.repository,
    required this.onChanged,
  });
  final MediaItem item;
  final MediaRepository repository;
  final Future<void> Function() onChanged;

  @override
  State<_EpisodeSelector> createState() => _EpisodeSelectorState();
}

class _EpisodeSelectorState extends State<_EpisodeSelector> {
  final watched = <String>{};
  final rangeFrom = TextEditingController();
  final rangeTo = TextEditingController();
  final rangeExpression = TextEditingController();
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    rangeFrom.dispose();
    rangeTo.dispose();
    rangeExpression.dispose();
    super.dispose();
  }

  int get totalEpisodes => widget.item.seasons.isNotEmpty
      ? widget.item.seasons.fold(0, (sum, season) => sum + season.episodeCount)
      : widget.item.episodeCount;

  Future<void> _load() async {
    final values = await widget.repository.loadEpisodeProgress(widget.item.id);
    if (!mounted) return;
    setState(() {
      watched
        ..clear()
        ..addAll(
          values.map((value) => '${value.seasonNumber}:${value.episodeNumber}'),
        );
      loading = false;
    });
  }

  Future<void> _toggle(int season, int episode, bool value) async {
    final key = '$season:$episode';
    setState(() {
      if (value) {
        watched.add(key);
      } else {
        watched.remove(key);
      }
    });
    try {
      await widget.repository.setEpisodeWatched(
        widget.item,
        season,
        episode,
        value,
      );
      await widget.onChanged();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        if (value) {
          watched.remove(key);
        } else {
          watched.add(key);
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось сохранить эпизод: $error')),
      );
    }
  }

  Future<void> _applyRange(bool value, {bool fromStart = false}) async {
    try {
      final expression = fromStart
          ? '1-${rangeTo.text.trim()}'
          : rangeExpression.text.trim().isNotEmpty
          ? rangeExpression.text.trim()
          : '${rangeFrom.text.trim()}-${rangeTo.text.trim()}';
      final episodes = const EpisodeRangeParser().parse(
        expression,
        totalEpisodes: totalEpisodes,
      );
      final count = await widget.repository.setEpisodeRange(
        widget.item,
        episodes,
        value,
      );
      await _load();
      await widget.onChanged();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            value ? 'Отмечено $count эпизодов' : 'Снято $count отметок',
          ),
        ),
      );
    } on EpisodeRangeException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Не удалось сохранить: $error')));
    }
  }

  Future<void> _watchAll() async {
    await widget.repository.setAllEpisodesWatched(widget.item, true);
    await _load();
    await widget.onChanged();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Отмечено $totalEpisodes эпизодов')),
      );
    }
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Снять все отметки?'),
        content: const Text(
          'Все просмотренные эпизоды этого произведения будут сняты.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Снять все отметки'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.repository.setAllEpisodesWatched(widget.item, false);
    await _load();
    await widget.onChanged();
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Все отметки сняты')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final seasons = widget.item.seasons;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.view_carousel_outlined, color: AppColors.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Просмотренные серии',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text(
                widget.item.episodeCount > 0
                    ? '${watched.length}/${widget.item.episodeCount}'
                    : '${watched.length}',
                style: const TextStyle(
                  color: AppColors.muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Это отметки для коллекции, а не плеер. Нажмите на номер серии.',
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 14),
          _EpisodeRangeControls(
            from: rangeFrom,
            to: rangeTo,
            expression: rangeExpression,
            onMark: () => _applyRange(true),
            onUnmark: () => _applyRange(false),
            onMarkTo: () => _applyRange(true, fromStart: true),
            onWatchAll: _watchAll,
            onClearAll: _clearAll,
          ),
          const SizedBox(height: 16),
          if (loading)
            const LinearProgressIndicator(minHeight: 3)
          else if (seasons.isEmpty && widget.item.episodeCount > 0) ...[
            Text(
              'Эпизоды 1–${widget.item.episodeCount}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: math
                  .min(330, ((widget.item.episodeCount / 6).ceil() * 50))
                  .toDouble(),
              child: GridView.builder(
                primary: false,
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 58,
                  mainAxisExtent: 44,
                  crossAxisSpacing: 7,
                  mainAxisSpacing: 7,
                ),
                itemCount: widget.item.episodeCount,
                itemBuilder: (context, index) {
                  final episode = index + 1;
                  return FilterChip(
                    label: Text('$episode'),
                    selected: watched.contains('0:$episode'),
                    onSelected: (value) => _toggle(0, episode, value),
                  );
                },
              ),
            ),
          ] else
            for (final season in seasons)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 12),
                initiallyExpanded: season.number == 1,
                title: Text(
                  season.name?.isNotEmpty == true
                      ? season.name!
                      : 'Сезон ${season.number}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text('${season.episodeCount} серий'),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (
                          var episode = 1;
                          episode <= season.episodeCount;
                          episode++
                        )
                          FilterChip(
                            label: Text('$episode'),
                            selected: watched.contains(
                              '${season.number}:$episode',
                            ),
                            onSelected: (value) =>
                                _toggle(season.number, episode, value),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
        ],
      ),
    );
  }
}

class _EpisodeRangeControls extends StatelessWidget {
  const _EpisodeRangeControls({
    required this.from,
    required this.to,
    required this.expression,
    required this.onMark,
    required this.onUnmark,
    required this.onMarkTo,
    required this.onWatchAll,
    required this.onClearAll,
  });

  final TextEditingController from;
  final TextEditingController to;
  final TextEditingController expression;
  final VoidCallback onMark;
  final VoidCallback onUnmark;
  final VoidCallback onMarkTo;
  final VoidCallback onWatchAll;
  final VoidCallback onClearAll;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.accent.withValues(alpha: .05),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.accent.withValues(alpha: .16)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Отметить диапазон эпизодов',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 5),
        const Text(
          'Используйте поля «От/До» или запись: 1-25, 30, 35-40.',
          style: TextStyle(color: AppColors.muted, fontSize: 12),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 560;
            final bounds = Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: from,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'От'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: to,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'До'),
                  ),
                ),
              ],
            );
            final freeform = TextField(
              controller: expression,
              decoration: const InputDecoration(
                labelText: 'Несколько диапазонов',
                hintText: '1-25, 30, 35-40',
              ),
            );
            return compact
                ? Column(
                    children: [bounds, const SizedBox(height: 10), freeform],
                  )
                : Row(
                    children: [
                      SizedBox(width: 190, child: bounds),
                      const SizedBox(width: 10),
                      Expanded(child: freeform),
                    ],
                  );
          },
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: onMark,
              icon: const Icon(Icons.done_all_rounded),
              label: const Text('Отметить просмотренными'),
            ),
            OutlinedButton.icon(
              onPressed: onUnmark,
              icon: const Icon(Icons.remove_done_rounded),
              label: const Text('Снять отметки'),
            ),
            TextButton(
              onPressed: onMarkTo,
              child: const Text('Отметить до выбранного'),
            ),
            TextButton(onPressed: onWatchAll, child: const Text('Смотрел всё')),
            TextButton(
              onPressed: onClearAll,
              child: const Text('Снять все отметки'),
            ),
          ],
        ),
      ],
    ),
  );
}
