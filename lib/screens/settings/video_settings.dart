import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:frosty/screens/settings/stores/settings_store.dart';
import 'package:frosty/screens/settings/widgets/settings_list_switch.dart';
import 'package:frosty/utils.dart';
import 'package:frosty/widgets/section_header.dart';
import 'package:frosty/widgets/settings_page_layout.dart';

/// Preset ad-blocking proxy servers (ported from Twire).
///
/// The `https://...` entries are TTVLOL **v1** playlist proxies: Frosty
/// rewrites the stream URL to `<proxy>/playlist/<channel>.m3u8`.
///
/// The `v2:...` entries are TTVLOL **v2** forward proxies, a different
/// protocol: `host:port` of a plain HTTP CONNECT proxy (see
/// `StreamProxyConfig`). Do not put a v2 address in the v1 Custom field
/// (or vice versa) — a v2 host returns a Squid 400 for playlist URLs, and
/// a v1 URL is not a valid forward-proxy address.
const _streamProxies = <String, String>{
  'Disabled': '',
  'EU': 'https://lb-eu.cdn-perfprod.com',
  'EU 2': 'https://lb-eu2.cdn-perfprod.com',
  'EU 3': 'https://lb-eu3.cdn-perfprod.com',
  'EU 4': 'https://lb-eu4.cdn-perfprod.com',
  'EU 5': 'https://lb-eu5.cdn-perfprod.com',
  'NA': 'https://lb-na.cdn-perfprod.com',
  'Asia': 'https://lb-as.cdn-perfprod.com',
  'South America': 'https://lb-sa.cdn-perfprod.com',
  'EU (Luminous)': 'https://eu.luminous.dev',
  'EU 2 (Luminous)': 'https://eu2.luminous.dev',
  'Asia (Luminous)': 'https://as.luminous.dev',
  'Custom': 'custom',
  'Nadeko (TTVLOLv2)': 'v2:twitch-al.nadeko.net:2023',
  'Custom (TTVLOLv2)': 'v2:',
};

/// Ad-blocking scripts for the WebView player (ported from Samtch, which
/// bundles pixeltris' TwitchAdSolutions).
const _webViewAdBlockScripts = <String, String>{
  'Disabled': '',
  'vaft': 'vaft',
  'video-swap': 'videoSwap',
};

class VideoSettings extends StatelessWidget {
  final SettingsStore settingsStore;

  const VideoSettings({super.key, required this.settingsStore});

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (context) => SettingsPageLayout(
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
              ListTile(
                title: const Text('Stream proxy'),
                subtitle: const Text(
                  'Routes streams through a proxy to block ads. Only works with the native player. '
                  'TTVLOLv2 entries are forward proxies (host:port); only playlist requests go through them.',
                ),
                trailing: DropdownButton<String>(
                  value: _getSelectedProxyLabel(settingsStore.streamProxy),
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
                    settingsStore.streamProxy = _streamProxies[label]!;
                  },
                ),
              ),
              if (settingsStore.streamProxy == 'custom')
                _CustomProxyField(settingsStore: settingsStore),
              if (_isCustomV2Proxy(settingsStore.streamProxy))
                _CustomV2ProxyField(settingsStore: settingsStore),
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
      ),
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

/// True for a v2 value that is not a known preset, i.e. the
/// "Custom (TTVLOLv2)" choice (including the empty `v2:` value the
/// dropdown writes before the user has typed anything).
bool _isCustomV2Proxy(String proxyValue) {
  if (!proxyValue.startsWith('v2:')) return false;
  return !_streamProxies.values.contains(proxyValue);
}

class _CustomV2ProxyField extends StatefulWidget {
  final SettingsStore settingsStore;

  const _CustomV2ProxyField({required this.settingsStore});

  @override
  State<_CustomV2ProxyField> createState() => _CustomV2ProxyFieldState();
}

class _CustomV2ProxyFieldState extends State<_CustomV2ProxyField> {
  late final _controller = TextEditingController(
    text: widget.settingsStore.streamProxy.substring('v2:'.length),
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
            onChanged: (value) =>
                widget.settingsStore.streamProxy = 'v2:${value.trim()}',
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

String _getSelectedProxyLabel(String proxyValue) {
  if (proxyValue.isEmpty) return 'Disabled';
  if (proxyValue == 'custom') return 'Custom';
  for (final entry in _streamProxies.entries) {
    if (entry.value == proxyValue) return entry.key;
  }
  if (proxyValue.startsWith('v2:')) return 'Custom (TTVLOLv2)';
  return 'Custom';
}

String _getSelectedScriptLabel(String scriptValue) {
  for (final entry in _webViewAdBlockScripts.entries) {
    if (entry.value == scriptValue) return entry.key;
  }
  return 'Disabled';
}
