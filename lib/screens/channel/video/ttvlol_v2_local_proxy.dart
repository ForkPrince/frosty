import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:frosty/apis/twitch_gql_api.dart';
import 'package:frosty/screens/channel/video/hls_playlist_rewriter.dart';

/// TTVLOLv2 support that keeps the current native players untouched.
///
/// Why this exists: a v2 proxy (e.g. `twitch-al.nadeko.net:2023`) is a plain
/// HTTP forward proxy, not a playlist URL service like v1. The ad-blocking
/// works by making Twitch *itself* serve an ad-free playlist: the Usher
/// (master) playlist request and the video-weaver (media) playlist requests
/// must originate from the proxy's IP, in a region where Twitch serves no
/// ads. The player cannot be told to use a proxy — `loadUrl` only takes a
/// URL, headers, and DRM config — so instead this class runs a tiny
/// loopback HTTP server inside the app:
///
/// ```
/// ExoPlayer/AVPlayer ──► http://127.0.0.1:<port>/p/<upstream>
///                        (master + media playlists only)
///   local server ──CONNECT──► v2 proxy ──► usher.ttvnw.net / video-weaver.*
///   player ──direct──► Twitch CDN (video segments, keys, init segments)
/// ```
///
/// Segments stay direct on purpose: the public v2 proxies do not forward
/// segment hosts (a direct probe of nadeko's Squid gets a connection
/// refusal for video-weaver segment hosts), and they do not need to be
/// proxied — once the playlist is ad-free, its segments are the clean
/// stream. Routing segments through Dart would also double-copy every
/// video byte through the app for no benefit.
///
/// Security notes:
/// * The server binds loopback only and uses an ephemeral port, so it is
///   not reachable from other devices on the network.
/// * Upstream fetches use HTTPS through the proxy via CONNECT, so the
///   proxy sees only the destination host, not the playlist URL, token, or
///   headers — the same exposure as the TTV LOL PRO browser extension.
/// * The upstream URL (which contains the playback token) is base64url
///   encoded into the loopback path. It never leaves the device, but it is
///   deliberately never logged.
///
/// Failure behaviour: if the v2 fetch fails (proxy down, rate-limited,
/// non-2xx), the server latches to direct fetching for the rest of its
/// lifetime and returns the direct playlist. A dead proxy therefore
/// degrades to "stream with ads" instead of "no stream", and the next
/// stream load (which creates a fresh server) retries the proxy. A
/// genuinely broken upstream (e.g. expired token) is not masked: the
/// direct retry fails too and the player sees the upstream status, so
/// the existing 4xx auto-refresh still fires.
class TtvLolV2LocalProxy {
  /// [v2Endpoint] must be a canonical `host:port` address (see
  /// [StreamProxyConfig.parseV2Endpoint]); all call sites parse first, so
  /// a malformed value here can only degrade to a failed proxy fetch,
  /// which the direct fallback then covers.
  TtvLolV2LocalProxy({required this.v2Endpoint});

  /// Canonical `host:port` of the v2 forward proxy.
  final String v2Endpoint;

  HttpServer? _server;
  HttpClient? _client;
  Future<void>? _startFuture;

  /// True once a v2 fetch has failed and later fetches go direct.
  bool _directFallbackLatched = false;

  /// HTTP status of the most recent upstream response for the playlist
  /// currently being fetched (null when the fetch failed before any
  /// response arrived). Used so a 4xx from Twitch is forwarded to the
  /// player instead of being masked as a 502: the player's error
  /// handling auto-refreshes on 4xx (fresh token), which a 502 would not
  /// trigger.
  int? _lastUpstreamStatus;

  bool get isRunning => _server != null;

  /// The loopback base URL the player is pointed at, e.g.
  /// `http://127.0.0.1:54321`. Starts the server on first call.
  Future<Uri> get baseUrl async {
    await _ensureStarted();
    final server = _server;
    if (server == null) {
      throw StateError('TTVLOLv2 local proxy failed to start');
    }
    return Uri.parse('http://127.0.0.1:${server.port}');
  }

  /// Maps an absolute upstream playlist URL to the loopback URL the
  /// player should load. The player then polls that URL for live
  /// playlist updates, and every poll re-enters [_handleRequest].
  Future<Uri> urlFor(String upstreamPlaylistUrl) async {
    final base = await baseUrl;
    return base.replace(path: '/p/${_encodeUpstream(upstreamPlaylistUrl)}');
  }

  Future<void> _ensureStarted() async {
    if (_server != null) return;
    final existing = _startFuture;
    if (existing != null) return existing;
    final future = _start();
    _startFuture = future;
    try {
      await future;
    } finally {
      // A failed start must be retryable on the next load, not latched.
      if (_server == null) _startFuture = null;
    }
  }

  Future<void> _start() async {
    _client ??= HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      // All upstream requests from this client are playlists, and they
      // must either go through the v2 proxy or (after a failure latch)
      // direct. Never fall back to a system-wide proxy: that could route
      // Twitch traffic somewhere the user did not choose.
      ..findProxy = (Uri uri) =>
          _directFallbackLatched ? 'DIRECT' : 'PROXY $v2Endpoint';
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    // Don't await the listen loop; requests are handled as they arrive.
    unawaited(_serve(server));
    debugPrint('TTVLOLv2: local proxy listening on 127.0.0.1:${server.port}');
  }

  Future<void> _serve(HttpServer server) async {
    await for (final request in server) {
      // Fire-and-forget per request; a slow playlist fetch must not block
      // the next poll. Errors are answered inside [_handleRequest].
      unawaited(_handleRequest(request));
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      if (request.method != 'GET') {
        _respond(request, HttpStatus.methodNotAllowed, 'Method not allowed');
        return;
      }
      final upstream = _upstreamFromRequest(request.uri);
      if (upstream == null) {
        _respond(request, HttpStatus.badRequest, 'Bad request');
        return;
      }
      final playlist = await _fetchPlaylist(upstream);
      if (playlist == null) {
        _respond(
          request,
          _lastUpstreamStatus ?? HttpStatus.badGateway,
          'TTVLOLv2 proxy unavailable and direct fetch failed',
        );
        return;
      }
      final rewritten = rewriteHlsPlaylist(
        playlist: playlist.body,
        upstreamUrl: upstream,
        toLocalPlaylistUrl: (Uri upstreamPlaylistUrl) =>
            _localUrlFor(upstreamPlaylistUrl),
      );
      request.response
        ..statusCode = playlist.statusCode
        ..headers.contentType = ContentType(
          'application',
          'vnd.apple.mpegurl',
          charset: 'utf-8',
        )
        ..headers.set(HttpHeaders.cacheControlHeader, 'no-cache')
        ..write(rewritten);
      await request.response.close();
    } catch (e) {
      debugPrint('TTVLOLv2: local proxy request failed: $e');
      try {
        _respond(request, HttpStatus.badGateway, 'Proxy error');
      } catch (_) {
        // The client went away; nothing left to do.
      }
    }
  }

  /// Decodes the upstream playlist URL from a `/p/<base64url>` path.
  /// Returns null for anything else (probes, favicons, stale URLs).
  Uri? _upstreamFromRequest(Uri uri) {
    final segments = uri.pathSegments;
    if (segments.length != 2 || segments[0] != 'p') return null;
    try {
      final decoded = utf8.decode(
        base64Url.decode(_addBase64Padding(segments[1])),
      );
      final parsed = Uri.parse(decoded);
      if (!parsed.isAbsolute || parsed.scheme != 'https') return null;
      return parsed;
    } catch (_) {
      return null;
    }
  }

  /// The loopback URL for an upstream playlist, without starting the
  /// server (the server is already running when a playlist is rewritten).
  Uri _localUrlFor(Uri upstreamPlaylistUrl) {
    final server = _server;
    if (server == null) return upstreamPlaylistUrl;
    return Uri.parse(
      'http://127.0.0.1:${server.port}/p/${_encodeUpstream(upstreamPlaylistUrl.toString())}',
    );
  }

  /// Fetches [upstream] through the v2 proxy, falling back to a direct
  /// fetch (latched) on failure. Returns null only when both fail.
  Future<_Playlist?> _fetchPlaylist(Uri upstream) async {
    _lastUpstreamStatus = null;
    final viaProxy = await _fetchOnce(upstream);
    if (viaProxy != null) return viaProxy;

    if (!_directFallbackLatched) {
      _directFallbackLatched = true;
      debugPrint(
        'TTVLOLv2: proxy $v2Endpoint failed, falling back to direct '
        'for this stream',
      );
    }
    return _fetchOnce(upstream);
  }

  /// One upstream fetch. Returns null on any transport error or non-2xx
  /// status (the caller decides whether to retry direct).
  Future<_Playlist?> _fetchOnce(Uri upstream) async {
    final client = _client;
    if (client == null) return null;
    HttpClientRequest httpRequest;
    try {
      httpRequest = await client.getUrl(upstream);
    } catch (_) {
      return null;
    }
    for (final entry in TwitchGqlApi.playbackHttpHeaders.entries) {
      httpRequest.headers.set(entry.key, entry.value);
    }
    HttpClientResponse response;
    try {
      response = await httpRequest
          .close()
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      return null;
    }
    _lastUpstreamStatus = response.statusCode;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      // Drain so the connection can be reused, then report failure.
      try {
        await response.drain<void>();
      } catch (_) {
        // The connection is already gone; failure is reported below.
      }
      return null;
    }
    try {
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 15));
      return (body: body, statusCode: response.statusCode);
    } catch (_) {
      return null;
    }
  }

  void _respond(HttpRequest request, int statusCode, String body) {
    request.response
      ..statusCode = statusCode
      ..headers.contentType = ContentType.text
      ..write(body);
    unawaited(request.response.close());
  }

  /// Stops the server and closes the upstream client. Safe to call
  /// repeatedly and after a failed start.
  Future<void> stop() async {
    final server = _server;
    _server = null;
    _startFuture = null;
    _directFallbackLatched = false;
    await server?.close(force: true);
    _client?.close(force: true);
    _client = null;
  }
}

typedef _Playlist = ({String body, int statusCode});

/// Base64url-encodes an upstream URL for the loopback path, with padding
/// stripped: `=` at the end of a path segment is legal but some players
/// re-encode it, which would break decoding on the server side.
String _encodeUpstream(String url) =>
    base64Url.encode(utf8.encode(url)).replaceAll('=', '');

String _addBase64Padding(String input) {
  final remainder = input.length % 4;
  if (remainder == 0) return input;
  return input + ('=' * (4 - remainder));
}
