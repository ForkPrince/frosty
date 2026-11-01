import 'package:flutter_test/flutter_test.dart';
import 'package:frosty/screens/channel/video/stream_proxy_config.dart';

void main() {
  group('StreamProxyConfig.parse', () {
    test('empty value is disabled', () {
      final config = StreamProxyConfig.parse(
        streamProxy: '',
        customStreamProxy: '',
      );
      expect(config.isDisabled, isTrue);
      expect(config.endpoint, isEmpty);
    });

    test('v1 preset URL is kept verbatim', () {
      final config = StreamProxyConfig.parse(
        streamProxy: 'https://lb-eu.cdn-perfprod.com',
        customStreamProxy: '',
      );
      expect(config.isV1, isTrue);
      expect(config.endpoint, 'https://lb-eu.cdn-perfprod.com');
    });

    test('custom sentinel uses the custom v1 URL', () {
      final config = StreamProxyConfig.parse(
        streamProxy: 'custom',
        customStreamProxy: 'https://my-proxy.example.com/',
      );
      expect(config.isV1, isTrue);
      expect(config.endpoint, 'https://my-proxy.example.com');
    });

    test('custom sentinel with an empty custom value is disabled', () {
      final config = StreamProxyConfig.parse(
        streamProxy: 'custom',
        customStreamProxy: '   ',
      );
      expect(config.isDisabled, isTrue);
    });

    test('v2 preset is a forward proxy, not a URL', () {
      final config = StreamProxyConfig.parse(
        streamProxy: 'v2:twitch-al.nadeko.net:2023',
        customStreamProxy: '',
      );
      expect(config.isV2, isTrue);
      expect(config.endpoint, 'twitch-al.nadeko.net:2023');
    });

    test('v2 custom value is parsed from the v2: value itself', () {
      final config = StreamProxyConfig.parse(
        streamProxy: 'v2:my-proxy.example.com:4023',
        customStreamProxy: 'https://lb-eu.cdn-perfprod.com',
      );
      // The v1 custom field must not leak into a v2 choice.
      expect(config.isV2, isTrue);
      expect(config.endpoint, 'my-proxy.example.com:4023');
    });

    test('malformed v2 values degrade to disabled, never crash', () {
      for (final bad in [
        'v2:',
        'v2:twitch-al.nadeko.net',
        'v2:twitch-al.nadeko.net:notaport',
        'v2:twitch-al.nadeko.net:0',
        'v2:twitch-al.nadeko.net:65536',
        'v2:user@twitch-al.nadeko.net:2023',
      ]) {
        final config = StreamProxyConfig.parse(
          streamProxy: bad,
          customStreamProxy: '',
        );
        expect(
          config.isDisabled,
          isTrue,
          reason: 'Expected $bad to degrade to disabled',
        );
      }
    });
  });

  group('StreamProxyConfig.parseV2Endpoint', () {
    test('accepts bare host:port and strips schemes and paths', () {
      expect(
        StreamProxyConfig.parseV2Endpoint('twitch-al.nadeko.net:2023'),
        'twitch-al.nadeko.net:2023',
      );
      expect(
        StreamProxyConfig.parseV2Endpoint('http://twitch-al.nadeko.net:2023'),
        'twitch-al.nadeko.net:2023',
      );
      expect(
        StreamProxyConfig.parseV2Endpoint(
          'httpproxy://twitch-al.nadeko.net:2023',
        ),
        'twitch-al.nadeko.net:2023',
      );
      expect(
        StreamProxyConfig.parseV2Endpoint(
          'https://twitch-al.nadeko.net:2023/',
        ),
        'twitch-al.nadeko.net:2023',
      );
    });

    test('rejects missing ports, bad ports, and credentials', () {
      expect(StreamProxyConfig.parseV2Endpoint(''), isNull);
      expect(StreamProxyConfig.parseV2Endpoint('example.com'), isNull);
      expect(StreamProxyConfig.parseV2Endpoint('example.com:'), isNull);
      expect(StreamProxyConfig.parseV2Endpoint('example.com:abc'), isNull);
      expect(StreamProxyConfig.parseV2Endpoint('user@example.com:2023'), isNull);
      expect(
        StreamProxyConfig.parseV2Endpoint('[::1]:2023'),
        isNull,
        reason: 'IPv6 literals are not a supported v2 address form',
      );
    });
  });

  group('StreamProxyConfig.splitV2Endpoint', () {
    test('splits a canonical endpoint', () {
      expect(
        StreamProxyConfig.splitV2Endpoint('twitch-al.nadeko.net:2023'),
        (host: 'twitch-al.nadeko.net', port: 2023),
      );
    });

    test('returns null for anything unparseable', () {
      expect(StreamProxyConfig.splitV2Endpoint('example.com'), isNull);
      expect(StreamProxyConfig.splitV2Endpoint(''), isNull);
    });
  });
}
