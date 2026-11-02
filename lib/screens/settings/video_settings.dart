import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:frosty/screens/channel/video/stream_proxy_config.dart';
import 'package:frosty/screens/settings/stores/settings_store.dart';
import 'package:frosty/screens/settings/widgets/settings_list_select.dart';
import 'package:frosty/screens/settings/widgets/settings_list_switch.dart';
import 'package:frosty/utils.dart';
import 'package:frosty/widgets/section_header.dart';
import 'package:frosty/widgets/settings_page_layout.dart';

/// Sentinel stored for the custom v2 choice: the user's `host:port` is typed
/// directly after this prefix (see `StreamProxyConfig`).
const _customV2ProxyValue = 'v2:';

/// TTVLOL v1 preset playlist proxies (ported from Twire). Frosty rewrites
/// the stream URL to `<proxy>/playlist/<channel>.m3u8`.
///
/// Only entries verified alive on 2026-11-02 are listed; the PerfProd
/// `lb-eu*`/`lb-na`/`lb-sa` and `as.luminous.dev` proxies were removed after
/// they stopped responding (timeouts / Cloudflare 403 / 503).
const _v1StreamProxies = <String, String>{
  'Disabled': '',
  'Asia (PerfProd)': 'https://lb-as.cdn-perfprod.com',
  'EU (Luminous)': 'https://eu.luminous.dev',
  'EU 2 (Luminous)': 'https://eu2.luminous.dev',
  // No trailing slash: buildHlsUrl appends '/playlist/...' itself.
  'Albania (Nadeko)': 'https://twitch-al.nadeko.net',
  'Custom': 'custom',
};

/// TTVLOL v2 preset forward proxies: `host:port` of a plain HTTP CONNECT
/// proxy, not a playlist URL (see `StreamProxyConfig`). All entries verified
/// alive on 2026-11-02; the legacy `chrome.api.cdn-perfprod.com:4023` no
/// longer resolves and was dropped.
const _v2StreamProxies = <String, String>{
  'Disabled': '',
  'Chromium (PerfProd)': 'v2:chromium.api.cdn-perfprod.com:2023',
  'Firefox (PerfProd)': 'v2:firefox.api.cdn-perfprod.com:2023',
  'Albania (Nadeko)': 'v2:twitch-al.nadeko.net:2023',
  'Custom': _customV2ProxyValue,
};

/// Ad-blocking scripts for the WebView player (ported from Samtch, which
/// bundles pixeltris' TwitchAdSolutions).
const _webViewAdBlockScripts = <String, String>{
  'Disabled': '',
  'vaft': 'vaft',
  'video-swap': 'videoSwap',
};

enum _ProxyVersion { v1, v2 }

class VideoSettings extends StatefulWidget {
  final SettingsStore settingsStore;

  const VideoSettings({super.key, required this.settingsStore});

  @override
  State<VideoSettings> createState() => _VideoSettingsState();
}

class _VideoSettingsState extends State<VideoSettings> {
  late _ProxyVersion _proxyVersion;

  /// Last value picked for each version, so toggling back and forth keeps
  /// both selections. Only the active one is written to the settings store.
  late String _v1Proxy;
  late String _v2Proxy;

  @override
  void initState() {
    super.initState();
    final stored = widget.settingsStore.streamProxy;
    final config = StreamProxyConfig.parse(
      streamProxy: stored,
      customStreamProxy: widget.settingsStore.customStreamProxy,
    );
    _proxyVersion = config.isV2 ? _ProxyVersion.v2 : _ProxyVersion.v1;
    _v1Proxy = config.isV2 ? '' : stored;
    _v2Proxy = config.isV2 ? stored : '';
  }

  bool get _isV2 => _proxyVersion == _ProxyVersion.v2;

  Map<String, String> get _streamProxies =>
      _isV2 ? _v2StreamProxies : _v1StreamProxies;

  void _selectVersion(_ProxyVersion version) {
    if (version == _proxyVersion) return;
    HapticFeedback.selectionClick();
    setState(() {
      // Remember what was selected (or typed) before leaving this version.
      if (_isV2) {
        _v2Proxy = widget.settingsStore.streamProxy;
      } else {
        _v1Proxy = widget.settingsStore.streamProxy;
      }
      _proxyVersion = version;
      widget.settingsStore.streamProxy = version == _ProxyVersion.v2
          ? _v2Proxy
          : _v1Proxy;
    });
  }

  void _selectProxy(String label) {
    widget.settingsStore.streamProxy = _streamProxies[label]!;
  }

  @override
  Widget build(BuildContext context) {
    final settingsStore = widget.settingsStore;
    return Observer(
      builder: (context) {
        final proxyLabel = _getSelectedProxyLabel(
          _streamProxies,
          settingsStore.streamProxy,
          isV2: _isV2,
        );
        return SettingsPageLayout(
          children: [
            const SectionHeader('Player', isFirst: true),
            SettingsListSwitch(
              title: 'Show video player',
              value: settingsStore.showVideo,
              onChanged: (newValue) => settingsStore.showVideo = newValue,
            ),
            if (settingsStore.showVideo)
              SettingsListSwitch(
                title: 'Native player',
                subtitle: const Text(
                  'Picture-in-Picture, quality selection, and lower latency. Turn off to use the legacy WebView player.',
                ),
                value: settingsStore.useNativePlayer,
                onChanged: (newValue) =>
                    settingsStore.useNativePlayer = newValue,
              ),
            if (!Platform.isIOS || isIPad())
              SettingsListSwitch(
                title: 'Default to highest quality',
                value: settingsStore.defaultToHighestQuality,
                onChanged: (newValue) =>
                    settingsStore.defaultToHighestQuality = newValue,
              ),
            if (Platform.isAndroid)
              SettingsListSwitch(
                title: 'Use fast video rendering',
                subtitle: const Text(
                  'Uses a faster WebView rendering method. Disable if you experience crashes while watching streams.',
                ),
                value: settingsStore.useTextureRendering,
                onChanged: (newValue) =>
                    settingsStore.useTextureRendering = newValue,
              ),
            if (settingsStore.showVideo) ...[
              const SectionHeader('Ad Blocking'),
              if (settingsStore.useNativePlayer) ...[
                SettingsListSelect(
                  title: 'Proxy version',
                  subtitle:
                      'v1 rewrites the playlist URL; v2 is a forward proxy '
                      '(host:port) used for playlist requests only.',
                  selectedOption: _isV2 ? 'v2' : 'v1',
                  options: const ['v1', 'v2'],
                  onChanged: (value) => _selectVersion(
                    value == 'v2' ? _ProxyVersion.v2 : _ProxyVersion.v1,
                  ),
                ),
                ListTile(
                  title: const Text('Stream proxy'),
                  subtitle: const Text(
                    'Routes streams through a proxy to block ads. Only works with the native player.',
                  ),
                  trailing: DropdownButton<String>(
                    value: proxyLabel,
                    underline: const SizedBox.shrink(),
                    items: _streamProxies.keys
                        .map((label) => DropdownMenuItem(
                              value: label,
                              child: Text(label),
                            ))
                        .toList(),
                    onChanged: (label) {
                      if (label == null) return;
                      HapticFeedback.selectionClick();
                      _selectProxy(label);
                    },
                  ),
                ),
                if (proxyLabel == 'Custom')
                  _isV2
                      ? _CustomV2ProxyField(settingsStore: settingsStore)
                      : _CustomProxyField(settingsStore: settingsStore),
              ] else
                ListTile(
                  title: const Text('Ad-blocking script'),
                  subtitle: const Text(
                    'Injects a TwitchAdSolutions script into the WebView player to block ads.',
                  ),
                  trailing: DropdownButton<String>(
                    value: _getSelectedScriptLabel(
                      settingsStore.webViewAdBlockScript,
                    ),
                    underline: const SizedBox.shrink(),
                    items: _webViewAdBlockScripts.keys
                        .map((label) => DropdownMenuItem(
                              value: label,
                              child: Text(label),
                            ))
                        .toList(),
                    onChanged: (label) {
                      if (label == null) return;
                      HapticFeedback.selectionClick();
                      settingsStore.webViewAdBlockScript =
                          _webViewAdBlockScripts[label]!;
                    },
                  ),
                ),
            ],
            const SectionHeader('Overlay'),
            SettingsListSwitch(
              title: 'Use custom video overlay',
              subtitle: const Text(
                'Replaces Twitch\'s default web overlay with a mobile-friendly version.',
              ),
              value: settingsStore.showOverlay,
              onChanged: (newValue) => settingsStore.showOverlay = newValue,
            ),
            SettingsListSwitch(
              title: 'Toggle overlay on long-press',
              subtitle: const Text(
                'Switch between Twitch\'s overlay and the custom overlay.',
              ),
              value: settingsStore.toggleableOverlay,
              onChanged: (newValue) =>
                  settingsStore.toggleableOverlay = newValue,
            ),
            SettingsListSwitch(
              title: 'Show latency',
              subtitle: const Text(
                'Displays the stream latency in the video overlay.',
              ),
              value: settingsStore.showLatency,
              onChanged: (newValue) => settingsStore.showLatency = newValue,
            ),
          ],
        );
      },
    );
  }
}

class _CustomProxyField extends StatefulWidget {
  final SettingsStore settingsStore;

  const _CustomProxyField({required this.settingsStore});

  @override
  State<_CustomProxyField> createState() => _CustomProxyFieldState();
}

class _CustomProxyFieldState extends State<_CustomProxyField> {
  late final _controller = TextEditingController(
    text: widget.settingsStore.customStreamProxy,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TextField(
        controller: _controller,
        autocorrect: false,
        enableSuggestions: false,
        keyboardType: TextInputType.url,
        decoration: const InputDecoration(
          hintText: 'https://your-proxy.example.com',
          border: OutlineInputBorder(),
          isDense: true,
        ),
        onChanged: (value) =>
            widget.settingsStore.customStreamProxy = value.trim(),
      ),
    );
  }
}

class _CustomV2ProxyField extends StatefulWidget {
  final SettingsStore settingsStore;

  const _CustomV2ProxyField({required this.settingsStore});

  @override
  State<_CustomV2ProxyField> createState() => _CustomV2ProxyFieldState();
}

class _CustomV2ProxyFieldState extends State<_CustomV2ProxyField> {
  late final _controller = TextEditingController(
    text: widget.settingsStore.streamProxy.substring(
      _customV2ProxyValue.length,
    ),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              hintText: 'twitch-al.nadeko.net:2023',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            // The host:port is stored straight in the `v2:` value, so
            // no second custom field is needed (see StreamProxyConfig).
            onChanged: (value) => widget.settingsStore.streamProxy =
                '$_customV2ProxyValue${value.trim()}',
          ),
          const SizedBox(height: 4),
          const Text(
            'A forward proxy host and port — not a playlist URL. '
            'Only playlist requests go through it; video loads direct.',
          ),
        ],
      ),
    );
  }
}

String _getSelectedProxyLabel(
  Map<String, String> streamProxies,
  String proxyValue, {
  required bool isV2,
}) {
  for (final entry in streamProxies.entries) {
    if (entry.value == proxyValue) return entry.key;
  }
  // A custom v2 host:port is stored in the `v2:` value itself.
  return isV2 && proxyValue.startsWith(_customV2ProxyValue)
      ? 'Custom'
      : 'Disabled';
}

String _getSelectedScriptLabel(String scriptValue) {
  for (final entry in _webViewAdBlockScripts.entries) {
    if (entry.value == scriptValue) return entry.key;
  }
  return 'Disabled';
}
