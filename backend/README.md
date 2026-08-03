# Kadroskop backend

API-прокси для TMDB и AniList и серверный разбор описания для функции
«Вспомнить». Все итоговые названия, ID, годы, описания и обложки приходят только
из TMDB или AniList. AI извлекает признаки запроса и не является источником
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

AniList работает без ключа. Backend слушает порт `8080`; его можно изменить
переменной `PORT`. Поиск не падает целиком при отказе одного каталога: успешный
источник возвращается вместе с `warnings`.

## AI-провайдер

По умолчанию выбран `deepseek` и модель `deepseek-v4-flash`. Для разбора всегда
отправляется максимум один запрос, `thinking` принудительно отключён, ответ
ограничен 400 токенами и валидируется по строгой схеме. Пустой, ошибочный или
недоступный AI-ответ автоматически заменяется обычным Dart-парсером.

Варианты `AI_PROVIDER`:

- `deepseek` — `DEEPSEEK_API_KEY` хранится только в `.env`;
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
- `POST /remember/search`

Поддерживаемые значения `kind`: `movie`, `series`, `anime`, `cartoon`,
`animatedSeries`, `documentary`.

Для `POST /remember/search` обязательное поле — `query`; дополнительно доступны
`type`, `yearFrom`, `yearTo`, `country`, `visualStyle`, `excluded` и `similarTo`.

Токены, `.env` и файл SQLite-кэша исключены из Git. Автоматические тесты используют
fake HTTP/AI и никогда не обращаются к платным API. При публикации backend
настройте HTTPS и ограничение частоты запросов.
