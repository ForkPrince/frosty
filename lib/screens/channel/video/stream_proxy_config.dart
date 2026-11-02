/// Interpretation of the persisted stream-proxy settings.
///
/// The settings store already persists the proxy choice as a single string
/// ([SettingsStore.streamProxy]) plus a free-form custom value
/// ([SettingsStore.customStreamProxy]), with the sentinel `'custom'` meaning
/// "use the custom value". This file extends that same scheme instead of
/// adding new persisted fields (which would need regenerated MobX /
/// json_serializable output):
///
/// * `''` — no proxy.
/// * `https://...` — a TTVLOL **v1** playlist-rewriting proxy, used
///   verbatim as before.
/// * `'custom'` — a v1 proxy, with the URL in `customStreamProxy`.
/// * `'v2:<host>:<port>'` — a TTVLOL **v2** forward (HTTP CONNECT) proxy.
///   The part after `v2:` is a host and port, e.g.
///   `v2:twitch-al.nadeko.net:2023`. It is *not* a URL to fetch a playlist
///   from: pointing the player at it directly just returns a Squid 400.
///   See [TtvLolV2LocalProxy].
///
/// A v2 value that does not match a known preset is the "Custom (TTVLOLv2)"
/// choice in settings; the settings UI writes the user's host:port straight
/// into the `v2:` value, so no second custom field is needed.
enum StreamProxyType { disabled, v1, v2 }

/// A parsed stream-proxy choice. [endpoint] is a v1 base URL for [StreamProxyType.v1]
/// and a `host:port` forward-proxy address for [StreamProxyType.v2]; it is
/// empty for [StreamProxyType.disabled].
class StreamProxyConfig {
  const StreamProxyConfig._(this.type, this.endpoint);

  const StreamProxyConfig.disabled() : this._(StreamProxyType.disabled, '');

  final StreamProxyType type;
  final String endpoint;

  bool get isDisabled => type == StreamProxyType.disabled;
  bool get isV1 => type == StreamProxyType.v1;
  bool get isV2 => type == StreamProxyType.v2;

  /// Parses the persisted settings values. Never throws: unrecognised or
  /// malformed values degrade to [StreamProxyConfig.disabled] so a bad
  /// saved setting can never break playback outright (the caller falls
  /// back to the direct Usher URL).
  static StreamProxyConfig parse({
    required String streamProxy,
    required String customStreamProxy,
  }) {
    final value = streamProxy.trim();
    if (value.isEmpty) return const StreamProxyConfig.disabled();

    if (value == 'custom') {
      final endpoint = customStreamProxy.trim().replaceAll(
        RegExp(r'/+$'),
        '',
      );
      if (endpoint.isEmpty) return const StreamProxyConfig.disabled();
      return StreamProxyConfig._(StreamProxyType.v1, endpoint);
    }

    if (value.startsWith('v2:')) {
      final endpoint = value.substring('v2:'.length).trim();
      final parsed = parseV2Endpoint(endpoint);
      if (parsed == null) return const StreamProxyConfig.disabled();
      return StreamProxyConfig._(StreamProxyType.v2, parsed);
    }

    return StreamProxyConfig._(StreamProxyType.v1, value);
  }

  /// Normalises a user-supplied v2 proxy address to canonical `host:port`
  /// form, or `null` when it is not a usable forward-proxy address.
  ///
  /// Accepts a bare `host:port`, `http://host:port`, and the
  /// `httpproxy://host:port` spelling used by streamlink tooling. The proxy
  /// itself is a plain HTTP CONNECT proxy, so an `https://` scheme is also
  /// accepted and stripped — it describes how the *client* reaches the
  /// proxy host, not a TLS proxy protocol. Userinfo (credentials) and
  /// paths are rejected: no supported public v2 proxy needs them, and
  /// persisting credentials in the settings JSON would be a leak.
  static String? parseV2Endpoint(String input) {
    var value = input.trim();
    if (value.isEmpty) return null;
    // Strip a scheme, if present, and any trailing slash/path.
    final schemeIndex = value.indexOf('://');
    if (schemeIndex != -1) {
      value = value.substring(schemeIndex + 3);
    }
    value = value.split('/').first;
    if (value.isEmpty ||
        value.contains('@') ||
        value.contains(' ') ||
        value.contains('[')) {
      return null;
    }
    // The port is after the *last* colon; the host must not contain one
    // (IPv6 literals are rejected above via '[').
    final colon = value.lastIndexOf(':');
    if (colon <= 0 || colon == value.length - 1) return null;
    final host = value.substring(0, colon);
    final portText = value.substring(colon + 1);
    if (host.contains(':')) return null;
    final port = int.tryParse(portText);
    if (port == null || port < 1 || port > 65535) return null;
    return '$host:$port';
  }
}
