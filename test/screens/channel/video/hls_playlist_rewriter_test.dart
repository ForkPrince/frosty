import 'package:flutter_test/flutter_test.dart';
import 'package:frosty/screens/channel/video/hls_playlist_rewriter.dart';

/// Stand-in for the loopback proxy: maps an upstream playlist URL to a
/// predictable local URL so the rewrite can be asserted exactly.
Uri _toLocal(Uri upstream) => Uri.parse(
  'http://127.0.0.1:54321/p/${upstream.host}',
);

void main() {
  group('rewriteHlsPlaylist master playlist', () {
    test('rewrites absolute and relative variant playlists to local', () {
      const master = '#EXTM3U\n'
          '#EXT-X-STREAM-INF:BANDWIDTH=8000000,RESOLUTION=1920x1080\n'
          'https://video-weaver.fra02.hls.ttvnw.net/v1/playlist/abc/chunked/index.m3u8?token=xyz\n'
          '#EXT-X-STREAM-INF:BANDWIDTH=3000000,RESOLUTION=1280x720\n'
          'chunked/index-720.m3u8\n';

      final rewritten = rewriteHlsPlaylist(
        playlist: master,
        upstreamUrl: Uri.parse(
          'https://usher.ttvnw.net/api/v2/channel/hls/xqc.m3u8?sig=s&token=t',
        ),
        toLocalPlaylistUrl: _toLocal,
      );

      expect(
        rewritten,
        '#EXTM3U\n'
        '#EXT-X-STREAM-INF:BANDWIDTH=8000000,RESOLUTION=1920x1080\n'
        'http://127.0.0.1:54321/p/video-weaver.fra02.hls.ttvnw.net\n'
        '#EXT-X-STREAM-INF:BANDWIDTH=3000000,RESOLUTION=1280x720\n'
        'http://127.0.0.1:54321/p/usher.ttvnw.net\n',
      );
    });

    test('rewrites URI attributes on iframe stream-inf tags', () {
      const master = '#EXTM3U\n'
          '#EXT-X-I-FRAME-STREAM-INF:BANDWIDTH=100000,URI="iframes.m3u8"\n';

      final rewritten = rewriteHlsPlaylist(
        playlist: master,
        upstreamUrl: Uri.parse('https://usher.ttvnw.net/api/x.m3u8'),
        toLocalPlaylistUrl: _toLocal,
      );

      expect(
        rewritten,
        '#EXTM3U\n'
        '#EXT-X-I-FRAME-STREAM-INF:BANDWIDTH=100000,URI="http://127.0.0.1:54321/p/usher.ttvnw.net"\n',
      );
    });
  });

  group('rewriteHlsPlaylist media playlist', () {
    test('absolutises segments and keys, leaves them direct', () {
      const media = '#EXTM3U\n'
          '#EXT-X-TARGETDURATION:2\n'
          '#EXT-X-MAP:URI="init.mp4"\n'
          '#EXTINF:2.0,\n'
          'segment-1.ts\n'
          '#EXTINF:2.0,\n'
          'https://video-edge-abc.ttvnw.net/segment-2.ts?token=x\n';

      final rewritten = rewriteHlsPlaylist(
        playlist: media,
        upstreamUrl: Uri.parse(
          'https://video-weaver.fra02.hls.ttvnw.net/v1/playlist/abc/chunked/index.m3u8',
        ),
        toLocalPlaylistUrl: _toLocal,
      );

      // Segments must NOT go through the local proxy: v2 proxies do not
      // forward segment hosts, and routing them through Dart would
      // double-copy every video byte. Relative ones are absolutised so
      // they still resolve to Twitch once served from loopback.
      expect(
        rewritten,
        '#EXTM3U\n'
        '#EXT-X-TARGETDURATION:2\n'
        '#EXT-X-MAP:URI="https://video-weaver.fra02.hls.ttvnw.net/v1/playlist/abc/chunked/init.mp4"\n'
        '#EXTINF:2.0,\n'
        'https://video-weaver.fra02.hls.ttvnw.net/v1/playlist/abc/chunked/segment-1.ts\n'
        '#EXTINF:2.0,\n'
        'https://video-edge-abc.ttvnw.net/segment-2.ts?token=x\n',
      );
    });

    test('a nested playlist inside a media playlist goes local', () {
      const media = '#EXTM3U\n'
          '#EXTINF:2.0,\n'
          'next.m3u8?seq=42\n';

      final rewritten = rewriteHlsPlaylist(
        playlist: media,
        upstreamUrl: Uri.parse(
          'https://video-weaver.fra02.hls.ttvnw.net/v1/playlist/abc/index.m3u8',
        ),
        toLocalPlaylistUrl: _toLocal,
      );

      expect(
        rewritten,
        '#EXTM3U\n#EXTINF:2.0,\nhttp://127.0.0.1:54321/p/video-weaver.fra02.hls.ttvnw.net\n',
      );
    });
  });

  group('rewriteHlsPlaylist prefetch', () {
    test('absolutises a relative prefetch URL so it stays direct', () {
      const media = '#EXTM3U\n'
          '#EXTINF:2.0,\n'
          'segment-1.ts\n'
          '#EXT-X-TWITCH-PREFETCH:segment-2.ts\n';

      final rewritten = rewriteHlsPlaylist(
        playlist: media,
        upstreamUrl: Uri.parse(
          'https://video-weaver.fra02.hls.ttvnw.net/v1/playlist/abc/chunked/index.m3u8',
        ),
        toLocalPlaylistUrl: _toLocal,
      );

      // The native low-latency parser promotes prefetch lines to
      // segments. A relative value left untouched would resolve against
      // the loopback playlist URL and 400 on the local server.
      expect(
        rewritten,
        '#EXTM3U\n'
        '#EXTINF:2.0,\n'
        'https://video-weaver.fra02.hls.ttvnw.net/v1/playlist/abc/chunked/segment-1.ts\n'
        '#EXT-X-TWITCH-PREFETCH:https://video-weaver.fra02.hls.ttvnw.net/v1/playlist/abc/chunked/segment-2.ts\n',
      );
    });

    test('leaves an absolute prefetch URL untouched', () {
      const media = '#EXTM3U\n'
          '#EXT-X-TWITCH-PREFETCH:https://video-edge-abc.ttvnw.net/segment-9.ts\n';

      final rewritten = rewriteHlsPlaylist(
        playlist: media,
        upstreamUrl: Uri.parse(
          'https://video-weaver.fra02.hls.ttvnw.net/v1/playlist/abc/index.m3u8',
        ),
        toLocalPlaylistUrl: _toLocal,
      );

      expect(
        rewritten,
        '#EXTM3U\n'
        '#EXT-X-TWITCH-PREFETCH:https://video-edge-abc.ttvnw.net/segment-9.ts\n',
      );
    });
  });

  test('preserves a missing trailing newline', () {
    const playlist = '#EXTM3U\nsegment.ts';
    final rewritten = rewriteHlsPlaylist(
      playlist: playlist,
      upstreamUrl: Uri.parse('https://example.com/dir/index.m3u8'),
      toLocalPlaylistUrl: _toLocal,
    );
    expect(rewritten, '#EXTM3U\nhttps://example.com/dir/segment.ts');
    expect(rewritten.endsWith('\n'), isFalse);
  });
}
