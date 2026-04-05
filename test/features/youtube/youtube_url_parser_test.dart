import 'package:flutter_test/flutter_test.dart';
import 'package:frank_karaoke/features/youtube/youtube_url_parser.dart';

void main() {
  group('extractVideoId', () {
    test('extracts from standard watch URL', () {
      expect(
        extractVideoId('https://www.youtube.com/watch?v=dQw4w9WgXcQ'),
        'dQw4w9WgXcQ',
      );
    });

    test('extracts from watch URL with extra params', () {
      expect(
        extractVideoId('https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=42s&list=PLx'),
        'dQw4w9WgXcQ',
      );
    });

    test('extracts from mobile watch URL', () {
      expect(
        extractVideoId('https://m.youtube.com/watch?v=dQw4w9WgXcQ'),
        'dQw4w9WgXcQ',
      );
    });

    test('extracts from short youtu.be URL', () {
      expect(
        extractVideoId('https://youtu.be/dQw4w9WgXcQ'),
        'dQw4w9WgXcQ',
      );
    });

    test('extracts from youtu.be with params', () {
      expect(
        extractVideoId('https://youtu.be/dQw4w9WgXcQ?t=120'),
        'dQw4w9WgXcQ',
      );
    });

    test('extracts from embed URL', () {
      expect(
        extractVideoId('https://www.youtube.com/embed/dQw4w9WgXcQ'),
        'dQw4w9WgXcQ',
      );
    });

    test('extracts from shorts URL', () {
      expect(
        extractVideoId('https://www.youtube.com/shorts/dQw4w9WgXcQ'),
        'dQw4w9WgXcQ',
      );
    });

    test('returns null for youtube homepage', () {
      expect(extractVideoId('https://www.youtube.com'), isNull);
    });

    test('returns null for youtube search', () {
      expect(
        extractVideoId('https://www.youtube.com/results?search_query=karaoke'),
        isNull,
      );
    });

    test('returns null for empty string', () {
      expect(extractVideoId(''), isNull);
    });

    test('returns null for garbage input', () {
      expect(extractVideoId('not a url at all'), isNull);
    });

    test('extracts v param even from non-youtube URL', () {
      // extractVideoId only parses URL structure, not domain
      expect(extractVideoId('https://example.com/watch?v=abc'), 'abc');
    });

    test('URL without scheme still extracts v param', () {
      // Uri.parse handles query params even without a scheme
      expect(extractVideoId('www.youtube.com/watch?v=abc123'), 'abc123');
    });
  });
}
