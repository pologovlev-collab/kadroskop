import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadroskop/data/media_repository.dart';
import 'package:kadroskop/models/media_item.dart';

void main() {
  test('tracks individual episodes and whole series', () async {
    final repository = MemoryMediaRepository([series]);

    await repository.setEpisodeWatched(series, 1, 1, true);
    var progress = await repository.loadEpisodeProgress(series.id);
    expect(progress, hasLength(1));

    await repository.setAllEpisodesWatched(series, true);
    progress = await repository.loadEpisodeProgress(series.id);
    expect(progress, hasLength(4));
    expect((await repository.loadMedia()).single.status, WatchStatus.watched);

    await repository.setAllEpisodesWatched(series, false);
    expect(await repository.loadEpisodeProgress(series.id), isEmpty);
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
