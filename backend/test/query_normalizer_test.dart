import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kadroskop_backend/kadroskop_server.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  const normalizer = QueryNormalizer();
  const generator = QueryVariantGenerator();

  test('normalizes Russian Unicode, punctuation and whitespace', () {
    expect(
      normalizer.normalize('  Унесённые,   ПРИЗРАКАМИ! '),
      'унесенные призраками',
    );
    expect(normalizer.normalize('Blue   Eye-Samurai'), 'blue eye samurai');
  });

  test('repairs keyboard layout and the common Naruto typo', () {
    expect(normalizer.swapKeyboardLayout('тфкгещ'), 'naruto');
    expect(normalizer.swapKeyboardLayout('Naruto'), 'тфкгещ');
    expect(
      generator.generate('Мфкгещ').map((variant) => variant.value),
      contains('Naruto'),
    );
  });

  test('generates confirmed original titles for Russian partial queries', () {
    final variants = generator
        .generate('тетрадь см')
        .map((variant) => variant.value)
        .toList();

    expect(variants, contains('Death Note'));
    expect(variants, contains('Desu Noto'));
  });

  test('SQLite media_aliases stores aliases only for observed media', () async {
    final database = sqlite3.openInMemory();
    addTearDown(database.close);
    final store = SqliteMediaAliasStore(path: ':memory:', database: database);
    final media = CatalogMedia(
      id: 1,
      source: 'anilist',
      externalId: '1535',
      externalIds: const {'anilist': '1535'},
      title: 'Death Note',
      originalTitle: 'Death Note',
      nativeTitle: 'デスノート',
      synonyms: const ['Тетрадь смерти'],
      kind: 'anime',
      year: 2006,
    );

    expect(await store.aliasesForQuery('тетрадь'), isEmpty);
    await store.record([media]);
    final aliases = await store.aliasesForQuery('тетрадь');

    expect(aliases, containsAll(['Death Note', 'Тетрадь смерти']));
    final columns = database
        .select('PRAGMA table_info(media_aliases)')
        .map((row) => row['name'])
        .toSet();
    expect(
      columns,
      containsAll({
        'id',
        'normalized_alias',
        'display_alias',
        'language',
        'source',
        'external_id',
        'alias_type',
        'created_at',
        'updated_at',
      }),
    );
  });

  test('exact title outranks a more popular unrelated result', () async {
    final gateway = CatalogGateway(
      MockClient((request) async {
        expect(request.url.host, 'graphql.anilist.co');
        return _utf8JsonResponse(_rankingResponse);
      }),
      settings: const CatalogSettings(
        tmdbEnabled: false,
        jikanEnabled: false,
        tvMazeEnabled: false,
      ),
    );

    final page = await gateway.search('Naruto', kind: 'anime');

    expect(page.results.first['title'], 'Naruto');
    expect(
      page.results.first['searchScore'] as num,
      greaterThan(page.results.last['searchScore'] as num),
    );
  });
}

http.Response _utf8JsonResponse(Object value) => http.Response.bytes(
  utf8.encode(jsonEncode(value)),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

final _rankingResponse = {
  'data': {
    'Page': {
      'media': [
        {
          'id': 999,
          'title': {
            'romaji': 'One Piece',
            'english': 'One Piece',
            'native': 'ワンピース',
          },
          'description': 'Pirates',
          'startDate': {'year': 1999},
          'countryOfOrigin': 'JP',
          'format': 'TV',
          'episodes': 1000,
          'duration': 24,
          'averageScore': 90,
          'popularity': 9999999,
          'genres': ['Adventure'],
          'tags': const [],
          'coverImage': {'large': 'https://img.test/one-piece.jpg'},
        },
        {
          'id': 20,
          'idMal': 20,
          'title': {'romaji': 'Naruto', 'english': 'Naruto', 'native': 'ナルト'},
          'synonyms': ['Наруто'],
          'description': 'Ninja adventure',
          'startDate': {'year': 2002},
          'countryOfOrigin': 'JP',
          'format': 'TV',
          'episodes': 220,
          'duration': 23,
          'averageScore': 80,
          'popularity': 100,
          'genres': ['Action'],
          'tags': const [],
          'coverImage': {'large': 'https://img.test/naruto.jpg'},
        },
      ],
    },
  },
};
