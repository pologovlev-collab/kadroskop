class AppProfile {
  const AppProfile({
    required this.name,
    required this.email,
    required this.isGuest,
    required this.favoriteGenres,
    required this.darkTheme,
  });

  final String name;
  final String email;
  final bool isGuest;
  final List<String> favoriteGenres;
  final bool darkTheme;

  factory AppProfile.fromMap(Map<String, Object?> map) => AppProfile(
    name: (map['name'] as String?) ?? 'Гость',
    email: (map['email'] as String?) ?? '',
    isGuest: ((map['is_guest'] as int?) ?? 1) == 1,
    favoriteGenres: ((map['favorite_genres'] as String?) ?? '')
        .split(',')
        .where((value) => value.isNotEmpty)
        .toList(),
    darkTheme: ((map['dark_theme'] as int?) ?? 0) == 1,
  );

  AppProfile copyWith({
    String? name,
    String? email,
    bool? isGuest,
    List<String>? favoriteGenres,
    bool? darkTheme,
  }) => AppProfile(
    name: name ?? this.name,
    email: email ?? this.email,
    isGuest: isGuest ?? this.isGuest,
    favoriteGenres: favoriteGenres ?? this.favoriteGenres,
    darkTheme: darkTheme ?? this.darkTheme,
  );
}
