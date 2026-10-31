import 'package:flutter_test/flutter_test.dart';
import 'package:frosty/screens/onboarding/device_login.dart';
import 'package:frosty/screens/onboarding/login_route.dart';
import 'package:frosty/screens/onboarding/login_webview.dart';
import 'package:frosty/utils/tv.dart';

void main() {
  tearDown(() => setTvForTesting(false));

  test('uses the device code flow on TV', () {
    setTvForTesting(true);

    expect(buildLoginScreen(), isA<DeviceLoginScreen>());
  });

  test('keeps the WebView login on phones and tablets', () {
    setTvForTesting(false);

    expect(buildLoginScreen(), isA<LoginWebView>());
  });

  test('uses the device code flow to upgrade moderator tools on TV', () {
    setTvForTesting(true);

    final screen = buildLoginScreen(upgradeModeratorScopes: true);
    expect(screen, isA<DeviceLoginScreen>());
    expect((screen as DeviceLoginScreen).upgradeModeratorScopes, isTrue);
  });
}
