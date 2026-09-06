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
          if (settingsStore.showVideo && settingsStore.useNativePlayer) ...[
            const SectionHeader('Ad Blocking'),
            ListTile(
              title: const Text('Stream proxy'),
              subtitle: const Text(
                'Routes streams through a proxy to block ads. Only works with the native player.',
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
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'https://your-proxy.example.com',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  controller: TextEditingController(
                    text: settingsStore.customStreamProxy,
                  ),
                  onChanged: (value) =>
                      settingsStore.customStreamProxy = value.trim(),
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

String _getSelectedProxyLabel(String proxyValue) {
  if (proxyValue.isEmpty) return 'Disabled';
  if (proxyValue == 'custom') return 'Custom';
  for (final entry in _streamProxies.entries) {
    if (entry.value == proxyValue) return entry.key;
  }
  return 'Custom';
}
