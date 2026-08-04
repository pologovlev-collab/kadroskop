import 'dart:convert';

class RememberSearchRequest {
  const RememberSearchRequest({
    required this.query,
    this.type,
    this.yearFrom,
    this.yearTo,
    this.country,
    this.visualStyle,
    this.excluded = const [],
    this.similarTo,
  });

  final String query;
  final String? type;
  final int? yearFrom;
  final int? yearTo;
  final String? country;
  final String? visualStyle;
  final List<String> excluded;
  final RememberReference? similarTo;

  factory RememberSearchRequest.fromJson(
    Map<String, dynamic> json, {
    int maxInputLength = 1000,
  }) {
    const allowed = {
      'query',
      'type',
      'yearFrom',
      'yearTo',
      'country',
      'visualStyle',
      'excluded',
      'similarTo',
      'filters',
    };
    final unknown = json.keys.where((key) => !allowed.contains(key)).toList();
    if (unknown.isNotEmpty) {
      throw RememberValidationException(
        'Неизвестные поля запроса: ${unknown.join(', ')}.',
      );
    }
    final filters = switch (json['filters']) {
      final Map<String, dynamic> value => value,
      final Map value => value.cast<String, dynamic>(),
      null => const <String, dynamic>{},
      _ => throw const RememberValidationException(
        'Поле filters должно быть объектом.',
      ),
    };
    const allowedFilters = {'country', 'visualStyle'};
    final unknownFilters = filters.keys
        .where((key) => !allowedFilters.contains(key))
        .toList();
    if (unknownFilters.isNotEmpty) {
      throw RememberValidationException(
        'Неизвестные фильтры: ${unknownFilters.join(', ')}.',
      );
    }
    final query = _requiredString(json['query'], 'query');
    if (query.length < 8) {
      throw const RememberValidationException(
        'Описание должно содержать минимум 8 символов.',
      );
    }
    if (query.length > maxInputLength) {
      throw RememberValidationException(
        'Описание длиннее допустимых $maxInputLength символов.',
      );
    }
    final currentYear = DateTime.now().year;
    final yearFrom = _optionalYear(json['yearFrom'], 'yearFrom', currentYear);
    final yearTo = _optionalYear(json['yearTo'], 'yearTo', currentYear);
    if (yearFrom != null && yearTo != null && yearFrom > yearTo) {
      throw const RememberValidationException(
        'Год «от» не может быть больше года «до».',
      );
    }
    final type = _optionalEnum(json['type'], _workTypes, 'type');
    final visualStyle = _optionalEnum(
      json['visualStyle'] ?? filters['visualStyle'],
      _visualStyles,
      'visualStyle',
    );
    final excluded = _stringList(json['excluded'], max: 80, itemMax: 100);
    final similarJson = json['similarTo'];
    return RememberSearchRequest(
      query: query,
      type: type,
      yearFrom: yearFrom,
      yearTo: yearTo,
      country: _optionalString(
        json['country'] ?? filters['country'],
        'country',
        max: 80,
      ),
      visualStyle: visualStyle,
      excluded: excluded,
      similarTo: similarJson == null
          ? null
          : RememberReference.fromJson(
              (similarJson as Map).cast<String, dynamic>(),
            ),
    );
  }

  RememberSearchIntent applyTo(RememberSearchIntent intent) {
    final requestedType = type;
    return intent.copyWith(
      workTypes: requestedType == null ? null : [requestedType],
      yearFrom: yearFrom,
      yearTo: yearTo,
      countries: country == null ? null : [country!],
      visualStyle: visualStyle,
    );
  }

  String get normalizedQuery =>
      query.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  Map<String, Object?> get cacheFilters => {
    'type': type,
    'yearFrom': yearFrom,
    'yearTo': yearTo,
    'country': country,
    'visualStyle': visualStyle,
    'excluded': [...excluded]..sort(),
    'similarTo': similarTo?.toJson(),
  };
}

class RememberReference {
  const RememberReference({required this.source, required this.sourceId});
  final String source;
  final String sourceId;

  Map<String, Object?> toJson() => {'source': source, 'sourceId': sourceId};

  factory RememberReference.fromJson(Map<String, dynamic> json) {
    const allowed = {'source', 'sourceId'};
    if (json.keys.any((key) => !allowed.contains(key))) {
      throw const RememberValidationException(
        'similarTo содержит неизвестные поля.',
      );
    }
    return RememberReference(
      source: _requiredString(json['source'], 'similarTo.source'),
      sourceId: _requiredString(json['sourceId'], 'similarTo.sourceId'),
    );
  }
}

class RememberSearchIntent {
  const RememberSearchIntent({
    this.workTypes = const [],
    this.yearFrom,
    this.yearTo,
    this.genres = const [],
    this.plotKeywords = const [],
    this.titleFragments = const [],
    this.characterNames = const [],
    this.franchiseTerms = const [],
    this.locations = const [],
    this.objects = const [],
    this.searchVariants = const [],
    this.originalLanguageHints = const [],
    this.countries = const [],
    this.visualStyle,
    this.targetAudience,
    this.negativeKeywords = const [],
    this.confidence = 0,
  });

  final List<String> workTypes;
  final int? yearFrom;
  final int? yearTo;
  final List<String> genres;
  final List<String> plotKeywords;
  final List<String> titleFragments;
  final List<String> characterNames;
  final List<String> franchiseTerms;
  final List<String> locations;
  final List<String> objects;
  final List<String> searchVariants;
  final List<String> originalLanguageHints;
  final List<String> countries;
  final String? visualStyle;
  final String? targetAudience;
  final List<String> negativeKeywords;
  final double confidence;

  factory RememberSearchIntent.fromJson(Map<String, dynamic> json) {
    const allowed = {
      'workTypes',
      'yearFrom',
      'yearTo',
      'genres',
      'plotKeywords',
      'titleFragments',
      'characterNames',
      'franchiseTerms',
      'locations',
      'objects',
      'searchVariants',
      'originalLanguageHints',
      'countries',
      'visualStyle',
      'targetAudience',
      'negativeKeywords',
      'confidence',
    };
    final unknown = json.keys.where((key) => !allowed.contains(key)).toList();
    if (unknown.isNotEmpty) {
      throw RememberValidationException(
        'AI вернул неизвестные поля: ${unknown.join(', ')}.',
      );
    }
    final currentYear = DateTime.now().year;
    final yearFrom = _optionalYear(json['yearFrom'], 'yearFrom', currentYear);
    final yearTo = _optionalYear(json['yearTo'], 'yearTo', currentYear);
    if (yearFrom != null && yearTo != null && yearFrom > yearTo) {
      throw const RememberValidationException('AI вернул неверный период.');
    }
    final confidence = json['confidence'];
    if (confidence != null && confidence is! num) {
      throw const RememberValidationException(
        'AI вернул confidence неверного типа.',
      );
    }
    final confidenceValue = (confidence as num?)?.toDouble() ?? 0;
    if (confidenceValue < 0 || confidenceValue > 1) {
      throw const RememberValidationException(
        'AI вернул confidence вне диапазона.',
      );
    }
    return RememberSearchIntent(
      workTypes: _enumList(json['workTypes'], _workTypes, max: 6),
      yearFrom: yearFrom,
      yearTo: yearTo,
      genres: _stringList(json['genres'], max: 10, itemMax: 50),
      plotKeywords: _stringList(json['plotKeywords'], max: 20, itemMax: 80),
      titleFragments: _stringList(
        json['titleFragments'],
        max: 10,
        itemMax: 100,
      ),
      characterNames: _stringList(json['characterNames'], max: 15, itemMax: 80),
      franchiseTerms: _stringList(
        json['franchiseTerms'],
        max: 10,
        itemMax: 100,
      ),
      locations: _stringList(json['locations'], max: 10, itemMax: 80),
      objects: _stringList(json['objects'], max: 10, itemMax: 80),
      searchVariants: _stringList(
        json['searchVariants'],
        max: 10,
        itemMax: 100,
      ),
      originalLanguageHints: _stringList(
        json['originalLanguageHints'],
        max: 8,
        itemMax: 20,
      ),
      countries: _stringList(json['countries'], max: 8, itemMax: 50),
      visualStyle: _optionalEnum(
        json['visualStyle'],
        _visualStyles,
        'visualStyle',
      ),
      targetAudience: _optionalString(
        json['targetAudience'],
        'targetAudience',
        max: 50,
      ),
      negativeKeywords: _stringList(
        json['negativeKeywords'],
        max: 10,
        itemMax: 80,
      ),
      confidence: confidenceValue,
    );
  }

  RememberSearchIntent copyWith({
    List<String>? workTypes,
    int? yearFrom,
    int? yearTo,
    List<String>? genres,
    List<String>? plotKeywords,
    List<String>? titleFragments,
    List<String>? characterNames,
    List<String>? franchiseTerms,
    List<String>? locations,
    List<String>? objects,
    List<String>? searchVariants,
    List<String>? originalLanguageHints,
    List<String>? countries,
    String? visualStyle,
    String? targetAudience,
    List<String>? negativeKeywords,
    double? confidence,
  }) => RememberSearchIntent(
    workTypes: workTypes ?? this.workTypes,
    yearFrom: yearFrom ?? this.yearFrom,
    yearTo: yearTo ?? this.yearTo,
    genres: genres ?? this.genres,
    plotKeywords: plotKeywords ?? this.plotKeywords,
    titleFragments: titleFragments ?? this.titleFragments,
    characterNames: characterNames ?? this.characterNames,
    franchiseTerms: franchiseTerms ?? this.franchiseTerms,
    locations: locations ?? this.locations,
    objects: objects ?? this.objects,
    searchVariants: searchVariants ?? this.searchVariants,
    originalLanguageHints: originalLanguageHints ?? this.originalLanguageHints,
    countries: countries ?? this.countries,
    visualStyle: visualStyle ?? this.visualStyle,
    targetAudience: targetAudience ?? this.targetAudience,
    negativeKeywords: negativeKeywords ?? this.negativeKeywords,
    confidence: confidence ?? this.confidence,
  );

  Map<String, Object?> toJson() => {
    'workTypes': workTypes,
    'yearFrom': yearFrom,
    'yearTo': yearTo,
    'genres': genres,
    'plotKeywords': plotKeywords,
    'titleFragments': titleFragments,
    'characterNames': characterNames,
    'franchiseTerms': franchiseTerms,
    'locations': locations,
    'objects': objects,
    'searchVariants': searchVariants,
    'originalLanguageHints': originalLanguageHints,
    'countries': countries,
    'visualStyle': visualStyle,
    'targetAudience': targetAudience,
    'negativeKeywords': negativeKeywords,
    'confidence': confidence,
  };

  static RememberSearchIntent decode(String value) =>
      RememberSearchIntent.fromJson(
        (jsonDecode(value) as Map).cast<String, dynamic>(),
      );
}

class RememberValidationException implements Exception {
  const RememberValidationException(this.message);
  final String message;

  @override
  String toString() => message;
}

const _workTypes = {
  'movie',
  'series',
  'anime',
  'cartoon',
  'animated_series',
  'documentary',
};
const _visualStyles = {'2d', '3d', 'puppet', 'unknown'};

String _requiredString(Object? value, String field) {
  if (value is! String || value.trim().isEmpty) {
    throw RememberValidationException('Поле $field обязательно.');
  }
  return value.trim();
}

String? _optionalString(Object? value, String field, {required int max}) {
  if (value == null) return null;
  if (value is! String || value.trim().isEmpty || value.trim().length > max) {
    throw RememberValidationException('Поле $field имеет неверный формат.');
  }
  return value.trim();
}

String? _optionalEnum(Object? value, Set<String> values, String field) {
  if (value == null) return null;
  if (value is! String || !values.contains(value)) {
    throw RememberValidationException('Недопустимое значение поля $field.');
  }
  return value;
}

int? _optionalYear(Object? value, String field, int currentYear) {
  if (value == null) return null;
  if (value is! num) {
    throw RememberValidationException('Поле $field должно быть годом.');
  }
  final year = value.toInt();
  if (year < 1880 || year > currentYear + 5) {
    throw RememberValidationException('Поле $field вне разумного диапазона.');
  }
  return year;
}

List<String> _stringList(
  Object? value, {
  required int max,
  required int itemMax,
}) {
  if (value == null) return const [];
  if (value is! List || value.length > max) {
    throw const RememberValidationException(
      'AI вернул слишком длинный массив.',
    );
  }
  final result = <String>[];
  for (final item in value) {
    if (item is! String ||
        item.trim().isEmpty ||
        item.trim().length > itemMax) {
      throw const RememberValidationException(
        'AI вернул неверный элемент массива.',
      );
    }
    result.add(item.trim().toLowerCase());
  }
  return result.toSet().toList();
}

List<String> _enumList(Object? value, Set<String> values, {required int max}) {
  final result = _stringList(value, max: max, itemMax: 30);
  if (result.any((item) => !values.contains(item))) {
    throw const RememberValidationException(
      'AI вернул неизвестный тип произведения.',
    );
  }
  return result;
}
