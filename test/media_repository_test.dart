import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadroskop/data/media_repository.dart';
import 'package:kadroskop/data/local_database.dart';
import 'package:kadroskop/models/media_item.dart';

void main() {
  test('tracks individual episodes and whole series', () async {
    final repository = MemoryMediaRepository([series]);

    await repository.setEpisodeWatched(series, 1, 1, true);
    var progress = await repository.loadEpisodeProgress(series.id);
    expect(progress, hasLength(1));
    expect((await repository.loadMedia()).single.status, WatchStatus.watching);

    await repository.setAllEpisodesWatched(series, true);
    progress = await repository.loadEpisodeProgress(series.id);
    expect(progress, hasLength(4));
    expect((await repository.loadMedia()).single.status, WatchStatus.watched);

    await repository.setAllEpisodesWatched(series, false);
    expect(await repository.loadEpisodeProgress(series.id), isEmpty);
    expect((await repository.loadMedia()).single.status, WatchStatus.planned);
  });

  test('stores a personal rating independently from catalog rating', () async {
    final repository = MemoryMediaRepository([series]);

    await repository.setRating(series, 9);

    final saved = (await repository.loadMedia()).single;
    expect(saved.userRating, 9);
    expect(saved.rating, 8.2);
  });

  test('favorite is independent from collection status', () async {
    final repository = MemoryMediaRepository([series]);

    await repository.setFavorite(series, true);
    var saved = (await repository.loadMedia()).single;
    expect(saved.isFavorite, isTrue);
    expect(saved.status, WatchStatus.none);

    await repository.setFavorite(saved, false);
    saved = (await repository.loadMedia()).single;
    expect(saved.isFavorite, isFalse);
    expect(saved.status, WatchStatus.none);
  });

  test('favorite persists in SQLite without adding a watch status', () async {
    final database = await LocalDatabase.openInMemoryForTesting();
    addTearDown(database.database.close);
    final repository = LocalMediaRepository(database);

    await repository.setFavorite(series, true);
    final saved = (await repository.loadMedia()).single;

    expect(saved.isFavorite, isTrue);
    expect(saved.favoriteUpdatedAt, isNotNull);
    expect(saved.status, WatchStatus.none);
  });

  test('filters catalog by title and kind', () async {
    final repository = MemoryMediaRepository([series]);
    expect(
      await repository.searchCatalog('архив', kind: MediaKind.series),
      hasLength(1),
    );
    expect(
      await repository.searchCatalog('архив', kind: MediaKind.movie),
      isEmpty,
    );
  });
}

const series = MediaItem(
  id: 42,
  title: 'Архив памяти',
  subtitle: 'Сериал',
  description: 'Описание',
  year: 2025,
  kind: MediaKind.series,
  rating: 8.2,
  genres: ['Детектив'],
  colors: [Color(0xFF101A2C), Color(0xFF8B3D56)],
  seasonCount: 2,
  episodeCount: 4,
  episodeRuntimeMinutes: 45,
  seasons: [
    SeasonInfo(number: 1, episodeCount: 2),
    SeasonInfo(number: 2, episodeCount: 2),
  ],
);
