/// Rewrites an HLS playlist fetched through the TTVLOLv2 local proxy.
///
/// The native player (ExoPlayer / AVPlayer) is given a loopback URL, so it
/// resolves every *relative* URL in a playlist against that loopback URL.
/// That would send video segments — which must go direct to Twitch, see
/// [TtvLolV2LocalProxy] — back to the local server, and would send nested
/// playlists direct to Twitch, defeating the proxy. So before a playlist is
/// handed to the player:
///
/// * every `.m3u8` URL (master variants, nested/media playlists, and
///   `URI="..."` attributes such as `EXT-X-I-FRAME-STREAM-INF`) is
///   rewritten through [toLocalPlaylistUrl], so the player fetches it from
///   the loopback server, which re-fetches it via the v2 proxy;
/// * every other URL (segments, `EXT-X-MAP` init segments, `EXT-X-KEY`
///   URIs) is absolutised against the playlist's upstream URL and left
///   untouched otherwise, so the player fetches it direct from Twitch.
///
/// The function is pure (no I/O) and operates line by line, which is all
/// HLS needs: a playlist is a sequence of `#tag` lines and URI lines.

/// Rewrites [playlist] (fetched from [upstreamUrl]) as described above.
/// [toLocalPlaylistUrl] maps an absolute upstream playlist URL to the
/// loopback URL the player should fetch instead.
String rewriteHlsPlaylist({
  required String playlist,
  required Uri upstreamUrl,
  required Uri Function(Uri upstreamPlaylistUrl) toLocalPlaylistUrl,
}) {
  final buffer = StringBuffer();
  // Split on \n and keep the original line endings out of the output;
  // HLS parsers accept \n, and the upstream playlists use it already.
  final lines = playlist.split('\n');
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i];
    // Tolerate \r\n input without leaking \r into rewritten URLs.
    if (line.endsWith('\r')) line = line.substring(0, line.length - 1);
    buffer.writeln(_rewriteLine(line, upstreamUrl, toLocalPlaylistUrl));
  }
  var result = buffer.toString();
  // Preserve the input's trailing-newline shape: split/join above always
  // appends one, so drop it when the input did not end with a newline.
  if (!playlist.endsWith('\n') && result.endsWith('\n')) {
    result = result.substring(0, result.length - 1);
  }
  return result;
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

/// Rewrites a `URI="..."` attribute inside a tag line, if present.
String _rewriteTagLine(
  String line,
  Uri upstreamUrl,
  Uri Function(Uri) toLocalPlaylistUrl,
) {
  final match = _uriAttribute.firstMatch(line);
  if (match == null) return line;
  final raw = match.group(1)!;
  final resolved = _resolve(upstreamUrl, raw);
  if (resolved == null) return line;
  final replacement = _isPlaylistUrl(resolved)
      ? toLocalPlaylistUrl(resolved).toString()
      : resolved.toString();
  return line.replaceRange(match.start + 5, match.end - 1, replacement);
}

/// Matches `URI="..."` — the `5`/`-1` offsets in [_rewriteTagLine] are the
/// length of `URI="` and the closing quote.
final _uriAttribute = RegExp(r'URI="([^"]*)"');

bool _isPlaylistUrl(Uri url) =>
    url.path.toLowerCase().endsWith('.m3u8');

Uri? _resolve(Uri base, String raw) {
  if (raw.isEmpty) return null;
  try {
    return base.resolve(raw);
  } catch (_) {
    return null;
  }
}
