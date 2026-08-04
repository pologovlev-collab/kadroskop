import 'package:flutter_test/flutter_test.dart';
import 'package:kadroskop/data/episode_range_parser.dart';

void main() {
  const parser = EpisodeRangeParser();

  test('parses one inclusive episode range', () {
    expect(parser.parse('1-10', totalEpisodes: 25), [
      1,
      2,
      3,
      4,
      5,
      6,
      7,
      8,
      9,
      10,
    ]);
  });

  test('parses mixed ranges, singles and removes duplicates', () {
    expect(parser.parse('1-3, 3, 8; 10-12', totalEpisodes: 12), [
      1,
      2,
      3,
      8,
      10,
      11,
      12,
    ]);
  });

  test('rejects malformed and out-of-bounds ranges', () {
    for (final value in ['', '0', '-1', '26', '10-1', '1,']) {
      expect(
        () => parser.parse(value, totalEpisodes: 25),
        throwsA(isA<EpisodeRangeException>()),
        reason: value,
      );
    }
  });

  test('bounds input size and number of segments', () {
    expect(
      () => parser.parse(List.filled(1001, '1').join(), totalEpisodes: 25),
      throwsA(isA<EpisodeRangeException>()),
    );
    expect(
      () => parser.parse(List.filled(201, '1').join(','), totalEpisodes: 25),
      throwsA(isA<EpisodeRangeException>()),
    );
  });
}
