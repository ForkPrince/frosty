import 'package:flutter/material.dart';
import 'package:frosty/main.dart';
import 'package:frosty/screens/onboarding/device_login.dart';
import 'package:frosty/screens/onboarding/login_webview.dart';
import 'package:frosty/screens/settings/stores/auth_store.dart';
import 'package:frosty/utils/tv.dart';
import 'package:provider/provider.dart';

/// Builds the appropriate login screen for the current device.
///
/// TVs use the device code grant flow because entering credentials in a WebView
/// with a remote is impractical. Phones and tablets keep the existing WebView,
/// which also links the Twitch web session used by the native player.
Widget buildLoginScreen({
  Widget? routeAfter,
  bool upgradeModeratorScopes = false,
}) {
  if (isTv) {
    return DeviceLoginScreen(
      routeAfter: routeAfter,
      upgradeModeratorScopes: upgradeModeratorScopes,
    );
  }

  return LoginWebView(
    routeAfter: routeAfter,
    upgradeModeratorScopes: upgradeModeratorScopes,
  );
}

/// Pushes the atomic moderator-scopes upgrade flow.
void openEnableModeratorTools(AuthStore authStore, {BuildContext? context}) {
  final navContext = context ?? navigatorKey.currentContext;
  if (navContext == null) return;
  Navigator.of(navContext).push(
    MaterialPageRoute(
      builder: (context) => Provider<AuthStore>.value(
        value: authStore,
        child: buildLoginScreen(upgradeModeratorScopes: true),
      ),
    ),
  );
}
