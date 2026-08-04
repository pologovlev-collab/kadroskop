import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadroskop/data/media_repository.dart';
import 'package:kadroskop/models/media_item.dart';
import 'package:kadroskop/ui/kadroskop_app.dart';

void main() {
  testWidgets('shows adaptive home and opens text-first remember flow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      KadroskopApp(repository: MemoryMediaRepository(_items)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Кадроскоп'), findsOneWidget);
    expect(find.text('Для вас'), findsOneWidget);
    expect(find.text('Помоги вспомнить'), findsOneWidget);

    await tester.tap(find.text('Помоги вспомнить'));
    await tester.pumpAndSettle();
    expect(find.text('Вспомнить'), findsWidgets);
    expect(find.text('Опишите всё, что помните'), findsOneWidget);
    expect(find.text('Найти произведение'), findsOneWidget);
  });

  testWidgets('category button filters For You without leaving home', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      KadroskopApp(repository: MemoryMediaRepository(_items)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Аниме').first);
    await tester.pumpAndSettle();

    expect(find.text('Помоги вспомнить'), findsOneWidget);
    expect(find.text('Аниме для вас'), findsOneWidget);
    final chip = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, 'Аниме'),
    );
    expect(chip.selected, isTrue);
    expect(find.text('Лунный страж'), findsOneWidget);
    expect(find.text('Интерстеллар'), findsNothing);
  });
}

const _items = [
  MediaItem(
    id: 1,
    title: 'Полярная звезда',
    subtitle: 'Тихий космос помнит всё',
    description: 'История о далёком сигнале и забытом маршруте.',
    year: 2024,
    kind: MediaKind.movie,
    rating: 8.7,
    genres: ['Фантастика'],
    colors: [Color(0xFF071A31), Color(0xFF147FA3)],
  ),
  MediaItem(
    id: 2,
    title: 'Интерстеллар',
    subtitle: 'Человечеству пора оставить колыбель',
    description: 'Космическое путешествие.',
    year: 2014,
    kind: MediaKind.movie,
    rating: 8.7,
    genres: ['Фантастика'],
    colors: [Color(0xFF243843), Color(0xFFC59D73)],
    runtimeMinutes: 169,
    status: WatchStatus.watched,
  ),
  MediaItem(
    id: 3,
    title: 'Лунный страж',
    subtitle: 'Ночь выбрала героя',
    description: 'Юный хранитель снов.',
    year: 2008,
    kind: MediaKind.anime,
    rating: 7.8,
    genres: ['Фэнтези'],
    colors: [Color(0xFF111B38), Color(0xFF82559B)],
  ),
  MediaItem(
    id: 4,
    title: 'Пустынный маршрут',
    subtitle: 'Ты точно видел это по телевизору',
    description: 'Мальчик и механический зверь.',
    year: 2006,
    kind: MediaKind.cartoon,
    rating: 7.5,
    genres: ['Приключения'],
    colors: [Color(0xFF553526), Color(0xFFE2A553)],
  ),
  MediaItem(
    id: 5,
    title: 'Сад на орбите',
    subtitle: 'Даже в пустоте растут цветы',
    description: 'Космическая оранжерея.',
    year: 2022,
    kind: MediaKind.anime,
    rating: 8,
    genres: ['Фантастика'],
    colors: [Color(0xFF183B3A), Color(0xFF68A46F)],
  ),
];
