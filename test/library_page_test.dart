import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadroskop/models/media_item.dart';
import 'package:kadroskop/ui/pages/library_page.dart';

void main() {
  testWidgets('favorite tab includes favorites outside collection', (
    tester,
  ) async {
    await tester.pumpWidget(_library(items: const [planned, favoriteOnly]));

    expect(find.text('Только в планах'), findsOneWidget);
    expect(find.text('Только любимое'), findsNothing);

    await tester.tap(find.text('Избранное'));
    await tester.pumpAndSettle();

    expect(find.text('Только любимое'), findsOneWidget);
    expect(find.text('Только в планах'), findsNothing);
  });

  testWidgets('planned status asks whether to reset existing progress', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    WatchStatus? savedStatus;
    bool? savedReset;
    await tester.pumpWidget(
      _library(
        items: const [watching],
        onStatus: (item, status, {resetProgress = false}) async {
          savedStatus = status;
          savedReset = resetProgress;
        },
      ),
    );

    final menu = find.byIcon(Icons.more_horiz_rounded);
    await tester.ensureVisible(menu);
    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(find.text('В планах').last);
    await tester.pumpAndSettle();
    expect(find.text('Перенести в планы'), findsOneWidget);

    await tester.tap(find.text('Сбросить'));
    await tester.pumpAndSettle();

    expect(savedStatus, WatchStatus.planned);
    expect(savedReset, isTrue);
  });
}

Widget _library({
  required List<MediaItem> items,
  Future<void> Function(MediaItem, WatchStatus, {bool resetProgress})? onStatus,
}) => MaterialApp(
  home: Scaffold(
    body: LibraryPage(
      items: items,
      onOpen: (_) {},
      onSetStatus: onStatus ?? (item, status, {resetProgress = false}) async {},
      onRating: (_, _) async {},
      onFavorite: (_, _) {},
      onSimilar: (_) {},
    ),
  ),
);

const planned = MediaItem(
  id: 1,
  title: 'Только в планах',
  subtitle: '',
  description: 'Описание',
  year: 2024,
  kind: MediaKind.movie,
  rating: 7,
  genres: ['Драма'],
  colors: [Color(0xFF101010), Color(0xFF202020)],
  status: WatchStatus.planned,
);

const favoriteOnly = MediaItem(
  id: 2,
  title: 'Только любимое',
  subtitle: '',
  description: 'Описание',
  year: 2020,
  kind: MediaKind.anime,
  rating: 8,
  genres: ['Фэнтези'],
  colors: [Color(0xFF101010), Color(0xFF202020)],
  isFavorite: true,
);

const watching = MediaItem(
  id: 3,
  title: 'Сериал с прогрессом',
  subtitle: '',
  description: 'Описание',
  year: 2022,
  kind: MediaKind.series,
  rating: 8,
  genres: ['Драма'],
  colors: [Color(0xFF101010), Color(0xFF202020)],
  status: WatchStatus.watching,
  watchedEpisodeCount: 2,
  watchedMinutes: 90,
  episodeCount: 10,
  episodeRuntimeMinutes: 45,
);
