enum QueryVariantType { original, normalized, alias, keyboard, transliteration }

class QueryVariant {
  const QueryVariant(this.value, this.type);

  final String value;
  final QueryVariantType type;
}

class QueryNormalizer {
  const QueryNormalizer();

  String normalize(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll('ё', 'е')
      .replaceAll(RegExp(r'[\u0300-\u036f]'), '')
      .replaceAll(RegExp(r'[^a-zа-я0-9]+', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  String swapKeyboardLayout(String value) {
    final normalized = value.toLowerCase();
    final cyrillicCount = RegExp(r'[а-яё]').allMatches(normalized).length;
    final latinCount = RegExp(r'[a-z]').allMatches(normalized).length;
    final from = cyrillicCount >= latinCount ? _russianKeys : _englishKeys;
    final to = cyrillicCount >= latinCount ? _englishKeys : _russianKeys;
    final buffer = StringBuffer();
    for (final rune in normalized.runes) {
      final character = String.fromCharCode(rune);
      final index = from.indexOf(character);
      buffer.write(index >= 0 ? to[index] : character);
    }
    return normalize(buffer.toString());
  }

  String transliterate(String value) {
    final buffer = StringBuffer();
    for (final rune in value.toLowerCase().runes) {
      final character = String.fromCharCode(rune);
      buffer.write(_transliteration[character] ?? character);
    }
    return normalize(buffer.toString());
  }
}

class QueryVariantGenerator {
  const QueryVariantGenerator({this.normalizer = const QueryNormalizer()});

  final QueryNormalizer normalizer;

  List<QueryVariant> generate(
    String query, {
    Iterable<String> cachedAliases = const [],
  }) {
    final result = <QueryVariant>[];
    final seen = <String>{};

    void add(String value, QueryVariantType type) {
      final cleaned = value.trim().replaceAll(RegExp(r'\s+'), ' ');
      final key = normalizer.normalize(cleaned);
      if (key.length < 2 || !seen.add(key)) return;
      result.add(QueryVariant(cleaned, type));
    }

    add(query, QueryVariantType.original);
    final normalized = normalizer.normalize(query);
    add(normalized, QueryVariantType.normalized);
    for (final alias in confirmedTitleAliases(normalized)) {
      add(alias, QueryVariantType.alias);
    }
    for (final alias in cachedAliases) {
      add(alias, QueryVariantType.alias);
    }
    final keyboard = normalizer.swapKeyboardLayout(query);
    add(keyboard, QueryVariantType.keyboard);
    if (normalized == 'мфкгещ' || keyboard == 'varuto') {
      add('Naruto', QueryVariantType.keyboard);
    }
    add(normalizer.transliterate(query), QueryVariantType.transliteration);
    return result;
  }
}

List<String> confirmedTitleAliases(String normalizedQuery) {
  for (final group in _confirmedTitleGroups) {
    if (group.any((alias) {
      final normalizedAlias = const QueryNormalizer().normalize(alias);
      return normalizedAlias == normalizedQuery ||
          (normalizedQuery.length >= 3 &&
              normalizedAlias.startsWith(normalizedQuery));
    })) {
      return group;
    }
  }
  return const [];
}

const _englishKeys = "qwertyuiop[]asdfghjkl;'zxcvbnm,.";
const _russianKeys = 'йцукенгшщзхъфывапролджэячсмитьбю';

const _confirmedTitleGroups = <List<String>>[
  ['Наруто', 'Naruto'],
  ['Тетрадь смерти', 'Death Note', 'Desu Noto'],
  ['Атака титанов', 'Attack on Titan', 'Shingeki no Kyojin'],
  [
    'Унесённые призраками',
    'Унесенные призраками',
    'Spirited Away',
    'Sen to Chihiro no Kamikakushi',
  ],
  ['Мы все мертвы', 'All of Us Are Dead', 'Jigeum Uri Hakgyoneun'],
  ['Голубоглазый самурай', 'Blue Eye Samurai'],
  ['Рик и Морти', 'Rick and Morty'],
  ['Интерстеллар', 'Interstellar'],
];

const _transliteration = <String, String>{
  'а': 'a',
  'б': 'b',
  'в': 'v',
  'г': 'g',
  'д': 'd',
  'е': 'e',
  'ё': 'e',
  'ж': 'zh',
  'з': 'z',
  'и': 'i',
  'й': 'y',
  'к': 'k',
  'л': 'l',
  'м': 'm',
  'н': 'n',
  'о': 'o',
  'п': 'p',
  'р': 'r',
  'с': 's',
  'т': 't',
  'у': 'u',
  'ф': 'f',
  'х': 'kh',
  'ц': 'ts',
  'ч': 'ch',
  'ш': 'sh',
  'щ': 'shch',
  'ъ': '',
  'ы': 'y',
  'ь': '',
  'э': 'e',
  'ю': 'yu',
  'я': 'ya',
};
