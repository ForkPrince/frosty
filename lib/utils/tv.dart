import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

/// System features that identify an Android TV, Google TV, or Fire TV device.
///
/// Leanback is the Android TV framework feature; the other entries cover
/// devices that report a television form factor without advertising Leanback.
const tvSystemFeatures = {
  'android.software.leanback',
  'android.hardware.type.television',
  'amazon.hardware.fire_tv',
};

var _isTv = false;

/// Whether the app is running on a TV (Android TV, Google TV, or Fire TV).
///
/// This is populated once during startup by [detectTvDevice] and stays false
/// on phones, tablets, and iOS. TV UI is additive, so a false negative only
/// falls back to the touch-first layout.
bool get isTv => _isTv;

/// Sets the TV flag for tests without touching platform channels.
@visibleForTesting
void setTvForTesting(bool value) {
  _isTv = value;
}

/// Whether any of the given Android system features identify a TV device.
bool hasTvSystemFeature(Iterable<String> features) {
  return features.any(tvSystemFeatures.contains);
}

/// Detects whether this process is running on an Android TV device.
///
/// Detection is best-effort: plugins can be missing on unsupported platforms
/// or throw while the platform channel starts up, which should never prevent
/// the app from launching.
Future<void> detectTvDevice() async {
  if (!Platform.isAndroid) return;

  try {
    final info = await DeviceInfoPlugin().androidInfo;
    _isTv = hasTvSystemFeature(info.systemFeatures);
  } catch (error) {
    debugPrint('TV detection failed: $error');
  }
}
