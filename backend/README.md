# Kadroskop backend

Небольшой API-прокси для TMDB и AniList. Он не хранит секретный токен в
Flutter-приложении, нормализует ответы двух каталогов и кэширует только недавние
запросы в памяти на 10 минут.

## Настройка

Получите TMDB API Read Access Token и запустите сервер:

```powershell
cd backend
dart pub get
$env:TMDB_ACCESS_TOKEN='ваш_токен'
dart run bin/server.dart
```

AniList работает без ключа. Backend слушает порт `8080`; его можно изменить
переменной `PORT`.

## Маршруты

- `GET /v1/health`
- `GET /v1/search?q=название&kind=movie`
- `GET /v1/media/{source}/{externalId}`

Поддерживаемые значения `kind`: `movie`, `series`, `anime`, `cartoon`,
`animatedSeries`, `documentary`.

Токены и `.env` исключены из Git. При публикации backend настройте HTTPS,
ограничение частоты запросов и постоянный Redis-кэш.
