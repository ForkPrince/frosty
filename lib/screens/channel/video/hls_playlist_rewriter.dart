import 'dart:convert';

/// Rewrites an HLS playlist fetched through the TTVLOLv2 local proxy.
///
/// The native player (ExoPlayer / AVPlayer) is given a loopback URL, so it
/// resolves every *relative* URL in a playlist against that loopback URL.
/// That would send video segments — which must go direct to Twitch, see
/// `TtvLolV2LocalProxy` — back to the local server, and would send nested
/// playlists direct to Twitch, defeating the proxy. So before a playlist is
/// handed to the player:
///
/// * every `.m3u8` URL (master variants, nested/media playlists, and
///   `URI="..."` attributes such as `EXT-X-I-FRAME-STREAM-INF`) is rewritten
///   through [toLocalPlaylistUrl], so the player fetches it from the loopback
///   server, which re-fetches it via the v2 proxy;
/// * every other URL (segments, `EXT-X-MAP` init segments, `EXT-X-KEY` URIs,
///   and `EXT-X-TWITCH-PREFETCH` values, which the player's low-latency
///   parser promotes to segments) is absolutised against the playlist's
///   upstream URL and left to load direct from Twitch.
///
/// The function is pure (no I/O) and operates line by line, which is all HLS
/// needs: a playlist is a sequence of `#tag` lines and URI lines.
String rewriteHlsPlaylist({
  required String playlist,
  required Uri upstreamUrl,
  required Uri Function(Uri upstreamPlaylistUrl) toLocalPlaylistUrl,
}) {
  // LineSplitter handles \n, \r\n, and \r and drops the trailing terminator,
  // so re-add one (normalised to \n) when the input had one.
  final lines = const LineSplitter().convert(playlist);
  final rewritten = [
    for (final line in lines)
      _rewriteLine(line, upstreamUrl, toLocalPlaylistUrl),
  ].join('\n');
  return playlist.endsWith('\n') || playlist.endsWith('\r')
      ? '$rewritten\n'
      : rewritten;
}

String _rewriteLine(
  String line,
  Uri upstreamUrl,
  Uri Function(Uri) toLocalPlaylistUrl,
) {
  if (line.isEmpty) return line;
  if (line.startsWith('#')) {
    return _rewriteTagLine(line, upstreamUrl, toLocalPlaylistUrl);
  }
  return _rewriteUriLine(line, upstreamUrl, toLocalPlaylistUrl);
}

String _rewriteUriLine(
  String line,
  Uri upstreamUrl,
  Uri Function(Uri) toLocalPlaylistUrl,
) {
  final resolved = _resolve(upstreamUrl, line.trim());
  if (resolved == null) return line;
  if (_isPlaylistUrl(resolved)) return toLocalPlaylistUrl(resolved).toString();
  // Absolutise relative segment/key/map URLs so they still point at
  // Twitch once the playlist itself is served from loopback.
  return resolved.toString();
}

/// Rewrites a `URI="..."` attribute or a prefetch value inside a tag line.
String _rewriteTagLine(
  String line,
  Uri upstreamUrl,
  Uri Function(Uri) toLocalPlaylistUrl,
) {
  // #EXT-X-TWITCH-PREFETCH:<url> carries its URL as the tag value, not as a
  // URI line or URI attribute. It is a segment, so it must stay direct.
  if (line.startsWith(_prefetchPrefix)) {
    final resolved = _resolve(
      upstreamUrl,
      line.substring(_prefetchPrefix.length).trim(),
    );
    if (resolved == null) return line;
    return '$_prefetchPrefix$resolved';
  }

  final match = _uriAttribute.firstMatch(line);
  if (match == null) return line;
  final resolved = _resolve(upstreamUrl, match.group(1)!);
  if (resolved == null) return line;
  final replacement = _isPlaylistUrl(resolved)
      ? toLocalPlaylistUrl(resolved).toString()
      : resolved.toString();
  return line.replaceRange(match.start, match.end, 'URI="$replacement"');
}

const _prefetchPrefix = '#EXT-X-TWITCH-PREFETCH:';

final _uriAttribute = RegExp(r'URI="([^"]*)"');

bool _isPlaylistUrl(Uri url) => url.path.toLowerCase().endsWith('.m3u8');

Uri? _resolve(Uri base, String raw) {
  if (raw.isEmpty) return null;
  try {
    return base.resolve(raw);
  } catch (_) {
    return null;
  }
}
