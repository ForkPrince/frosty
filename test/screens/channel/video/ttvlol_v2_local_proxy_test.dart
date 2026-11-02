import 'package:flutter_test/flutter_test.dart';
import 'package:frosty/screens/channel/video/ttvlol_v2_local_proxy.dart';

/// Regression test for the reason v2 playback failed outright: the
/// native player's `isHlsUrl` treats a URL as HLS only when it contains
/// `.m3u8` (or `/hls/`). A loopback URL without that suffix was loaded
/// as a progressive source and never played. These tests only start the
/// loopback server and inspect the URL it hands out — no upstream fetch
/// is performed, so they do not touch the network.
void main() {
  group('TtvLolV2LocalProxy.urlFor', () {
    test('loopback URL contains .m3u8 so the player treats it as HLS', () async {
      final proxy = TtvLolV2LocalProxy(
        v2Endpoint: 'proxy.example.com:2023',
      );
      try {
        final url = await proxy.urlFor(
          'https://usher.ttvnw.net/api/v2/channel/hls/xqc.m3u8?sig=s&token=t',
        );
        expect(url.scheme, 'http');
        expect(url.host, '127.0.0.1');
        expect(url.toString(), contains('.m3u8'));
        expect(url.path, endsWith('.m3u8'));
        expect(url.pathSegments.first, 'p');
      } finally {
        await proxy.stop();
      }
    });

    test('different upstream URLs give different loopback URLs', () async {
      final proxy = TtvLolV2LocalProxy(
        v2Endpoint: 'proxy.example.com:2023',
      );
      try {
        final first = await proxy.urlFor(
          'https://usher.ttvnw.net/api/v2/channel/hls/xqc.m3u8?token=one',
        );
        final second = await proxy.urlFor(
          'https://usher.ttvnw.net/api/v2/channel/hls/xqc.m3u8?token=two',
        );
        expect(first, isNot(equals(second)));
        // Same server (and port) is reused across loads.
        expect(first.port, second.port);
      } finally {
        await proxy.stop();
      }
    });
  });
}
