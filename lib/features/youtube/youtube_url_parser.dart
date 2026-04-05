/// Extracts YouTube video ID from various URL formats.
/// Returns null if the URL doesn't contain a valid video ID.
String? extractVideoId(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return null;

  // Standard: youtube.com/watch?v=VIDEO_ID
  final v = uri.queryParameters['v'];
  if (v != null && v.isNotEmpty) return v;

  // Short: youtu.be/VIDEO_ID
  if (uri.host.contains('youtu.be') && uri.pathSegments.isNotEmpty) {
    final id = uri.pathSegments.first;
    if (id.isNotEmpty) return id;
  }

  // Embed: youtube.com/embed/VIDEO_ID
  if (uri.pathSegments.length >= 2 && uri.pathSegments[0] == 'embed') {
    return uri.pathSegments[1];
  }

  // Shorts: youtube.com/shorts/VIDEO_ID
  if (uri.pathSegments.length >= 2 && uri.pathSegments[0] == 'shorts') {
    return uri.pathSegments[1];
  }

  return null;
}
