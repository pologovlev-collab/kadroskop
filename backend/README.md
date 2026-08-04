# Kadroskop backend

API-прокси для TMDB, AniList, Jikan и TVmaze и серверный разбор описания для функции
«Вспомнить». Все итоговые названия, ID, годы, описания и обложки приходят только
из каталожных API. AI извлекает признаки запроса и не является источником
произведений.

## Настройка

Получите TMDB API Read Access Token, скопируйте `.env.example` в `.env`, вставьте
токен и запустите сервер:

```powershell
cd backend
dart pub get
Copy-Item .env.example .env
# Откройте .env и замените значение TMDB_ACCESS_TOKEN
dart run bin/server.dart
```

AniList, Jikan и TVmaze работают без ключа. TVmaze используется только для
сериалов и эпизодов, Jikan — для аниме; полный каталог локально не скачивается.
Backend слушает порт `8080`; его можно изменить
переменной `PORT`. Поиск не падает целиком при отказе одного каталога: успешный
источник возвращается вместе с `warnings`.

## AI-провайдер

По умолчанию выбран `gemini` и модель `gemini-3.5-flash-lite` с уровнем thinking
`minimal`. Для разбора выполняется один логический AI-запрос (возможен один
повтор после `429`), ответ ограничен 500 токенами и валидируется по строгой
JSON-схеме. Пустой, ошибочный или
недоступный AI-ответ автоматически заменяется обычным Dart-парсером.

Варианты `AI_PROVIDER`:

- `deepseek` — `DEEPSEEK_API_KEY` хранится только в `.env`;
- `gemini` — `GEMINI_API_KEY` хранится только в `.env`;
- `yandex` — нужны `YANDEXGPT_API_KEY` и `YANDEXGPT_FOLDER_ID`, сервисному
  аккаунту достаточно роли `ai.languageModels.user` и scope
  `yc.ai.languageModels.execute`;
- `none` — полностью локальный fallback без нейросети.

Одинаковые нормализованные запросы и фильтры кэшируются на 24 часа в локальном
`data/kadroskop_backend.db`. В кэш не попадают профиль, коллекция или ключи.

## Маршруты

- `GET /v1/health`
- `GET /v1/popular?page=1&kind=movie`
- `GET /v1/search?q=название&page=1&kind=movie`
- `GET /v1/media/{source}/{externalId}`
- `GET /v1/media/{source}/{externalId}/similar?mode=overall&page=1`
- `GET /v1/recommendations/for-you?seeds=source:id:weight&kind=all&page=1`
- `POST /remember/search`

Персональные данные и коллекция не отправляются на backend: Flutter передаёт
только идентификаторы каталога и рассчитанные локально веса сигналов. Избранное
имеет наибольший положительный вес; просмотренные, брошенные и низко оценённые
произведения исключаются из выдачи. Результаты берутся из официальных
recommendation/similar endpoints, дедуплицируются, получают понятные причины и
кэшируются на срок `RECOMMENDATIONS_CACHE_HOURS`.

Режимы похожести: `overall`, `plot`, `genres`, `atmosphere`, `characters`.
Backend объединяет официальные recommendations/similar/relations, а затем
локально учитывает жанры, теги, сюжетные слова, описания, студию, персонажей,
страну, язык, формат и год. AI в этом процессе не вызывается.

Поддерживаемые значения `kind`: `movie`, `series`, `anime`, `cartoon`,
`animatedSeries`, `documentary`.

Для `POST /remember/search` обязательное поле — `query`; дополнительно доступны
`type`, `yearFrom`, `yearTo`, `country`, `visualStyle`, `excluded` и `similarTo`.

Токены, `.env` и файл SQLite-кэша исключены из Git. Автоматические тесты используют
fake HTTP/AI и никогда не обращаются к платным API. При публикации backend
настройте HTTPS и ограничение частоты запросов.
