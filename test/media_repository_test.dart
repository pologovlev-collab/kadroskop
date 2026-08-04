import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadroskop/data/media_repository.dart';
import 'package:kadroskop/data/local_database.dart';
import 'package:kadroskop/models/media_item.dart';
import 'package:kadroskop/models/similar_media.dart';

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

  test(
    'similar modes return only other items with shared catalog data',
    () async {
      final repository = MemoryMediaRepository([series, similarSeries]);

      final result = await repository.loadSimilar(
        series,
        mode: SimilarMode.genres,
      );

      expect(result.items.single.media.id, similarSeries.id);
    },
  );

  test('API media cleans markup and preserves portrait/backdrop URLs', () {
    final item = MediaItem.fromApi({
      'id': 99,
      'source': 'tmdb_movie',
      'externalId': '99',
      'title': 'Clean title',
      'description': '<b>Plot</b> with [link](https://example.test).',
      'kind': 'movie',
      'posterUrl': 'https://img.test/poster.jpg',
      'backdropUrl': 'https://img.test/backdrop.jpg',
    });

    expect(item.description, 'Plot with link.');
    expect(item.posterUrl, endsWith('poster.jpg'));
    expect(item.backdropUrl, endsWith('backdrop.jpg'));
  });

  test(
    'flat 220-episode anime keeps progress, time and dropped invariant',
    () async {
      final database = await LocalDatabase.openInMemoryForTesting();
      addTearDown(database.database.close);
      final repository = LocalMediaRepository(database);

      for (final episode in [1, 2, 3]) {
        await repository.setEpisodeWatched(naruto, 0, episode, true);
      }
      var saved = (await repository.loadMedia()).single;
      expect(saved.watchedEpisodeCount, 3);
      expect(saved.watchedMinutes, 72);
      expect(saved.status, WatchStatus.watching);
      expect(
        (await repository.loadEpisodeProgress(
          naruto.id,
        )).every((episode) => episode.seasonNumber == 0),
        isTrue,
      );

      await repository.setAllEpisodesWatched(saved, true);
      saved = (await repository.loadMedia()).single;
      expect(saved.watchedEpisodeCount, 220);
      expect(saved.status, WatchStatus.watched);

      await repository.setEpisodeWatched(saved, 0, 220, false);
      saved = (await repository.loadMedia()).single;
      expect(saved.watchedEpisodeCount, 219);
      expect(saved.status, WatchStatus.watching);

      await repository.setStatus(saved, WatchStatus.dropped);
      saved = (await repository.loadMedia()).single;
      expect(saved.status, WatchStatus.dropped);
      expect(saved.watchedEpisodeCount, 219);
      expect(await repository.loadEpisodeProgress(saved.id), hasLength(219));
    },
  );

  test(
    'episode update rolls back completely when progress summary fails',
    () async {
      final database = await LocalDatabase.openInMemoryForTesting();
      addTearDown(database.database.close);
      final repository = LocalMediaRepository(database);
      await repository.setStatus(naruto, WatchStatus.planned);
      await database.database.execute('''
      CREATE TRIGGER reject_progress_update
      BEFORE UPDATE OF watched_episode_count ON user_media
      WHEN NEW.watched_episode_count > 0
      BEGIN
        SELECT RAISE(ABORT, 'test rollback');
      END
    ''');

      await expectLater(
        repository.setEpisodeWatched(naruto, 0, 1, true),
        throwsA(anything),
      );

      expect(await repository.loadEpisodeProgress(naruto.id), isEmpty);
      final saved = (await repository.loadMedia()).single;
      expect(saved.watchedEpisodeCount, 0);
      expect(saved.status, WatchStatus.planned);
    },
  );

  test('episode range maps ordinals across real seasons', () async {
    final repository = MemoryMediaRepository([series]);

    expect(await repository.setEpisodeRange(series, [1, 2, 3], true), 3);
    var progress = await repository.loadEpisodeProgress(series.id);
    expect(
      progress
          .map((episode) => (episode.seasonNumber, episode.episodeNumber))
          .toSet(),
      {(1, 1), (1, 2), (2, 1)},
    );
    var saved = (await repository.loadMedia()).single;
    expect(saved.watchedEpisodeCount, 3);
    expect(saved.watchedMinutes, 135);
    expect(saved.status, WatchStatus.watching);

    expect(await repository.setEpisodeRange(saved, [2, 3], false), 2);
    progress = await repository.loadEpisodeProgress(series.id);
    expect(progress, hasLength(1));
    saved = (await repository.loadMedia()).single;
    expect(saved.watchedEpisodeCount, 1);
    expect(saved.watchedMinutes, 45);
  });

  test('episode range rolls back rows and summary together', () async {
    final database = await LocalDatabase.openInMemoryForTesting();
    addTearDown(database.database.close);
    final repository = LocalMediaRepository(database);
    await repository.setStatus(series, WatchStatus.planned);
    await database.database.execute('''
      CREATE TRIGGER reject_range_progress_update
      BEFORE UPDATE OF watched_episode_count ON user_media
      WHEN NEW.watched_episode_count > 0
      BEGIN
        SELECT RAISE(ABORT, 'test rollback');
      END
    ''');

    await expectLater(
      repository.setEpisodeRange(series, [1, 2, 3], true),
      throwsA(anything),
    );

    expect(await repository.loadEpisodeProgress(series.id), isEmpty);
    final saved = (await repository.loadMedia()).single;
    expect(saved.watchedEpisodeCount, 0);
    expect(saved.status, WatchStatus.planned);
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

const similarSeries = MediaItem(
  id: 43,
  title: 'Другой архив',
  subtitle: 'Сериал',
  description: 'Другое описание',
  year: 2024,
  kind: MediaKind.series,
  rating: 7.9,
  genres: ['Детектив'],
  colors: [Color(0xFF101A2C), Color(0xFF8B3D56)],
);

const naruto = MediaItem(
  id: 3000000020,
  source: 'anilist',
  externalId: '20',
  title: 'Naruto',
  subtitle: 'NARUTO',
  description: 'История юного ниндзя.',
  year: 2002,
  kind: MediaKind.anime,
  rating: 8,
  genres: ['Action'],
  colors: [Color(0xFF101A2C), Color(0xFF8B3D56)],
  episodeCount: 220,
  episodeRuntimeMinutes: 24,
);
