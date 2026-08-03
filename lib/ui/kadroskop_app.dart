import 'package:flutter/material.dart';

import '../data/media_repository.dart';
import '../models/media_item.dart';
import 'app_theme.dart';
import 'widgets/poster_card.dart';

class KadroskopApp extends StatelessWidget {
  const KadroskopApp({super.key, required this.repository});

  final MediaRepository repository;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Кадроскоп',
    debugShowCheckedModeBanner: false,
    theme: buildTheme(),
    home: KadroskopShell(repository: repository),
  );
}

class KadroskopShell extends StatefulWidget {
  const KadroskopShell({super.key, required this.repository});

  final MediaRepository repository;

  @override
  State<KadroskopShell> createState() => _KadroskopShellState();
}

class _KadroskopShellState extends State<KadroskopShell> {
  int _index = 0;
  bool _loading = true;
  List<MediaItem> _items = const [];

  static const _destinations = [
    (Icons.home_outlined, Icons.home_rounded, 'Главная'),
    (Icons.search_outlined, Icons.search_rounded, 'Поиск'),
    (Icons.bubble_chart_outlined, Icons.bubble_chart_rounded, 'Вспомнить'),
    (Icons.bookmarks_outlined, Icons.bookmarks_rounded, 'Коллекция'),
    (Icons.person_outline_rounded, Icons.person_rounded, 'Профиль'),
  ];

  @override
  void initState() {
    super.initState();
    _reload();
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

  Future<void> _setStatus(MediaItem item, WatchStatus status) async {
    await widget.repository.setStatus(item.id, status);
    await _reload();
  }

  void _openDetails(MediaItem item) {
    widget.repository.recordInteraction(item.id, 'opened');
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _DetailsSheet(
        item: item,
        onStatus: (status) {
          Navigator.pop(context);
          _setStatus(item, status);
        },
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
          0 => _HomePage(
            items: _items,
            onOpen: _openDetails,
            onRecall: () => setState(() => _index = 2),
          ),
          1 => _SearchPage(items: _items, onOpen: _openDetails),
          2 => _RecallPage(
            items: _items,
            repository: widget.repository,
            onOpen: _openDetails,
          ),
          3 => _LibraryPage(items: _items, onOpen: _openDetails),
          _ => _ProfilePage(items: _items),
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
                  backgroundColor: Colors.white,
                  indicatorColor: AppColors.accent.withValues(alpha: .12),
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
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(right: BorderSide(color: AppColors.border)),
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
                color: selected ? Colors.white : AppColors.ink,
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
      SliverPadding(
        padding: EdgeInsets.fromLTRB(
          MediaQuery.sizeOf(context).width < 600 ? 18 : 34,
          24,
          MediaQuery.sizeOf(context).width < 600 ? 18 : 34,
          40,
        ),
        sliver: SliverToBoxAdapter(child: child),
      ),
    ],
  );
}

class _HomePage extends StatelessWidget {
  const _HomePage({
    required this.items,
    required this.onOpen,
    required this.onRecall,
  });
  final List<MediaItem> items;
  final ValueChanged<MediaItem> onOpen;
  final VoidCallback onRecall;

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
        _KindsRow(),
        const SizedBox(height: 34),
        _SectionHeader(title: 'Для вас', action: 'Все рекомендации'),
        const SizedBox(height: 16),
        _PosterGrid(items: items.take(4).toList(), onOpen: onOpen),
        const SizedBox(height: 38),
        _SectionHeader(title: 'Продолжить просмотр', action: 'Моя коллекция'),
        const SizedBox(height: 16),
        _ContinueCard(
          item: items.firstWhere((e) => e.progress > 0),
          onOpen: () => onOpen(items.firstWhere((e) => e.progress > 0)),
        ),
        const SizedBox(height: 38),
        const _SectionHeader(
          title: 'Редкие находки',
          action: 'Обновить подборку',
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
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 84,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: MediaKind.values.length,
      separatorBuilder: (_, _) => const SizedBox(width: 10),
      itemBuilder: (context, i) {
        final kind = MediaKind.values[i];
        return Container(
          width: 150,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white,
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
        );
      },
    ),
  );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.action});
  final String title;
  final String action;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(title, style: Theme.of(context).textTheme.headlineMedium),
      ),
      TextButton(onPressed: () {}, child: Text(action)),
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
      final columns = constraints.maxWidth >= 1100
          ? 4
          : constraints.maxWidth >= 680
          ? 3
          : 2;
      final gap = 16.0;
      final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
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

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.item, required this.onOpen});
  final MediaItem item;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onOpen,
    borderRadius: BorderRadius.circular(22),
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 150,
            child: PosterArtwork(item: item, height: 96, showTitle: false),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 5),
                Text(
                  'Продолжить с 01:42:16',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
                ),
                const SizedBox(height: 14),
                LinearProgressIndicator(
                  value: item.progress,
                  minHeight: 5,
                  borderRadius: BorderRadius.circular(8),
                  backgroundColor: AppColors.border,
                  color: AppColors.coral,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const CircleAvatar(
            backgroundColor: AppColors.ink,
            foregroundColor: Colors.white,
            child: Icon(Icons.play_arrow_rounded),
          ),
        ],
      ),
    ),
  );
}

class _SearchPage extends StatefulWidget {
  const _SearchPage({required this.items, required this.onOpen});
  final List<MediaItem> items;
  final ValueChanged<MediaItem> onOpen;
  @override
  State<_SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<_SearchPage> {
  String query = '';
  MediaKind? selectedKind;

  @override
  Widget build(BuildContext context) {
    final normalized = query.trim().toLowerCase();
    final found = widget.items.where((item) {
      final matchesText =
          normalized.isEmpty ||
          item.title.toLowerCase().contains(normalized) ||
          item.description.toLowerCase().contains(normalized) ||
          item.genres.any((g) => g.toLowerCase().contains(normalized));
      return matchesText && (selectedKind == null || item.kind == selectedKind);
    }).toList();
    return _PageFrame(
      title: 'Поиск',
      subtitle: 'По названию, жанру или детали, которую вы помните',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            onChanged: (value) => setState(() => query = value),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search_rounded),
              hintText: 'Например: «мультфильм про робота в пустыне»',
              suffixIcon: Icon(Icons.tune_rounded),
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
                  onSelected: (_) => setState(() => selectedKind = null),
                ),
                for (final kind in MediaKind.values) ...[
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: Text(kind.label),
                    selected: selectedKind == kind,
                    onSelected: (_) => setState(() => selectedKind = kind),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 28),
          Row(
            children: [
              Text(
                normalized.isEmpty ? 'Популярные запросы' : 'Найдено',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const Spacer(),
              Text(
                '${found.length} совпадений',
                style: const TextStyle(color: AppColors.muted),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (found.isEmpty)
            const _EmptyState(
              icon: Icons.search_off_rounded,
              title: 'Ничего не нашлось',
              text:
                  'Попробуйте изменить формулировку или убрать часть фильтров.',
            )
          else
            _PosterGrid(items: found, onOpen: widget.onOpen),
        ],
      ),
    );
  }
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
    widget.repository.recordInteraction(item.id, event);
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
                    '${saved.where((e) => e.status == WatchStatus.watching).length}',
                label: 'смотрю',
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
      color: Colors.white,
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
    child: const Column(
      children: [
        ListTile(
          leading: Icon(Icons.storage_outlined),
          title: Text('Локальная база'),
          subtitle: Text('SQLite · данные хранятся на устройстве'),
          trailing: Icon(Icons.chevron_right_rounded),
        ),
        Divider(height: 1, indent: 56),
        ListTile(
          leading: Icon(Icons.tune_rounded),
          title: Text('Настроить вкус'),
          subtitle: Text('Жанры, годы и настроение'),
          trailing: Icon(Icons.chevron_right_rounded),
        ),
        Divider(height: 1, indent: 56),
        ListTile(
          leading: Icon(Icons.palette_outlined),
          title: Text('Внешний вид'),
          subtitle: Text('Системная тема'),
          trailing: Icon(Icons.chevron_right_rounded),
        ),
      ],
    ),
  );
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
  const _DetailsSheet({required this.item, required this.onStatus});
  final MediaItem item;
  final ValueChanged<WatchStatus> onStatus;

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * .92;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        constraints: BoxConstraints(maxWidth: 920, maxHeight: height),
        decoration: const BoxDecoration(
          color: AppColors.canvas,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
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
              const SizedBox(height: 18),
              LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 640;
                  final art = SizedBox(
                    width: compact ? double.infinity : 270,
                    child: Hero(
                      tag: 'poster-${item.id}',
                      child: PosterArtwork(
                        item: item,
                        height: compact ? 300 : 390,
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
                          const Spacer(),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close_rounded),
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
                            onPressed: () => onStatus(WatchStatus.watched),
                            icon: const Icon(Icons.check_rounded),
                            label: const Text('Смотрел'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => onStatus(WatchStatus.planned),
                            icon: const Icon(Icons.bookmark_add_outlined),
                            label: const Text('В планы'),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, 48),
                              side: const BorderSide(color: AppColors.border),
                              foregroundColor: AppColors.ink,
                              backgroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 30),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
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
