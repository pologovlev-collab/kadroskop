class EpisodeRangeException implements Exception {
  const EpisodeRangeException(this.message);
  final String message;

  @override
  String toString() => message;
}

class EpisodeRangeParser {
  const EpisodeRangeParser();

  List<int> parse(String input, {required int totalEpisodes}) {
    final value = input.trim();
    if (totalEpisodes < 1) {
      throw const EpisodeRangeException(
        'Каталог не сообщил количество эпизодов.',
      );
    }
    if (value.isEmpty) {
      throw const EpisodeRangeException('Введите номер или диапазон эпизодов.');
    }
    if (value.length > 1000) {
      throw const EpisodeRangeException('Диапазон слишком длинный.');
    }
    final segments = value.split(RegExp(r'[,;]'));
    if (segments.length > 200) {
      throw const EpisodeRangeException('Слишком много отдельных диапазонов.');
    }
    final result = <int>{};
    for (final raw in segments) {
      final segment = raw.trim();
      final match = RegExp(r'^(\d+)(?:\s*-\s*(\d+))?$').firstMatch(segment);
      if (match == null) {
        throw EpisodeRangeException('Некорректный фрагмент: «$segment».');
      }
      final from = int.parse(match.group(1)!);
      final to = int.parse(match.group(2) ?? match.group(1)!);
      if (from < 1 || to < 1) {
        throw const EpisodeRangeException(
          'Номер эпизода должен быть больше 0.',
        );
      }
      if (from > to) {
        throw EpisodeRangeException(
          'Обратный диапазон $from-$to недопустим: начало больше конца.',
        );
      }
      if (to > totalEpisodes) {
        throw EpisodeRangeException(
          'Эпизод $to превышает доступный диапазон 1–$totalEpisodes.',
        );
      }
      for (var episode = from; episode <= to; episode++) {
        result.add(episode);
      }
    }
    final sorted = result.toList()..sort();
    return sorted;
  }
}
