import 'package:flutter_test/flutter_test.dart';
import 'package:frosty/apis/base_api_client.dart';
import 'package:frosty/apis/twitch_api.dart';
import 'package:frosty/screens/onboarding/stores/device_login_store.dart';
import 'package:frosty/screens/settings/stores/auth_store.dart';
import 'package:frosty/utils/twitch_oauth_scopes.dart';
import 'package:mocktail/mocktail.dart';

class MockTwitchApi extends Mock implements TwitchApi {}

class MockAuthStore extends Mock implements AuthStore {}

const _deviceCode = TwitchDeviceCode(
  deviceCode: 'device-123',
  expiresIn: 1800,
  interval: 5,
  userCode: 'ABCDEFGH',
  verificationUri: 'https://www.twitch.tv/activate?device-code=ABCDEFGH',
);

const _userToken = TwitchUserToken(
  accessToken: 'access',
  refreshToken: 'refresh',
  expiresIn: 14400,
  scopes: twitchUserScopes,
);

void main() {
  late MockTwitchApi api;
  late MockAuthStore authStore;

  setUpAll(() {
    registerFallbackValue(<String>[]);
  });

  setUp(() {
    api = MockTwitchApi();
    authStore = MockAuthStore();

    when(() => authStore.shouldRequestModeratorScopes).thenReturn(false);
    when(() => authStore.isLoggedIn).thenReturn(true);
    when(
      () => authStore.login(
        token: any(named: 'token'),
        refreshToken: any(named: 'refreshToken'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => authStore.completeModeratorUpgrade(
        token: any(named: 'token'),
        refreshToken: any(named: 'refreshToken'),
        popOnSuccess: any(named: 'popOnSuccess'),
      ),
    ).thenAnswer((_) async => true);
  });

  testWidgets('requests a code and polls until authorized', (tester) async {
    when(
      () => api.requestDeviceCode(scopes: any(named: 'scopes')),
    ).thenAnswer((_) async => _deviceCode);

    var polls = 0;
    when(() => api.pollDeviceToken(deviceCode: 'device-123')).thenAnswer((
      _,
    ) async {
      polls++;
      if (polls == 1) return const TwitchDeviceTokenResult.pending();
      return const TwitchDeviceTokenResult.authorized(_userToken);
    });

    final store = DeviceLoginStore(twitchApi: api, authStore: authStore);
    await store.start();

    expect(store.status, DeviceLoginStatus.waiting);
    expect(store.userCode, 'ABCDEFGH');

    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(polls, 1);
    expect(store.status, DeviceLoginStatus.waiting);

    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(store.status, DeviceLoginStatus.authorized);
    verify(
      () => authStore.login(token: 'access', refreshToken: 'refresh'),
    ).called(1);

    store.dispose();
  });

  testWidgets('requests all scopes when upgrading moderator tools', (
    tester,
  ) async {
    when(
      () => api.requestDeviceCode(scopes: any(named: 'scopes')),
    ).thenAnswer((_) async => _deviceCode);
    when(() => api.pollDeviceToken(deviceCode: 'device-123')).thenAnswer(
      (_) async => const TwitchDeviceTokenResult.authorized(_userToken),
    );

    final store = DeviceLoginStore(
      twitchApi: api,
      authStore: authStore,
      upgradeModeratorScopes: true,
    );
    await store.start();

    verify(() => api.requestDeviceCode(scopes: twitchAllUserScopes)).called(1);

    await tester.pump(const Duration(seconds: 5));
    await tester.pump();

    expect(store.status, DeviceLoginStatus.authorized);
    verify(
      () => authStore.completeModeratorUpgrade(
        token: 'access',
        refreshToken: 'refresh',
        popOnSuccess: false,
      ),
    ).called(1);

    store.dispose();
  });

  testWidgets('surfaces denied authorization', (tester) async {
    when(
      () => api.requestDeviceCode(scopes: any(named: 'scopes')),
    ).thenAnswer((_) async => _deviceCode);
    when(
      () => api.pollDeviceToken(deviceCode: 'device-123'),
    ).thenAnswer((_) async => const TwitchDeviceTokenResult.denied());

    final store = DeviceLoginStore(twitchApi: api, authStore: authStore);
    await store.start();

    await tester.pump(const Duration(seconds: 5));
    await tester.pump();

    expect(store.status, DeviceLoginStatus.denied);
    expect(store.errorMessage, contains('denied'));
    verifyNever(
      () => authStore.login(
        token: any(named: 'token'),
        refreshToken: any(named: 'refreshToken'),
      ),
    );

    store.dispose();
  });

  testWidgets('cancel stops polling', (tester) async {
    when(
      () => api.requestDeviceCode(scopes: any(named: 'scopes')),
    ).thenAnswer((_) async => _deviceCode);

    final store = DeviceLoginStore(twitchApi: api, authStore: authStore);
    await store.start();
    expect(store.status, DeviceLoginStatus.waiting);

    store.cancel();
    await tester.pump(const Duration(seconds: 15));

    verifyNever(
      () => api.pollDeviceToken(deviceCode: any(named: 'deviceCode')),
    );
    expect(store.status, DeviceLoginStatus.idle);

    store.dispose();
  });

  testWidgets('surfaces request failures', (tester) async {
    when(
      () => api.requestDeviceCode(scopes: any(named: 'scopes')),
    ).thenThrow(const ApiException('invalid client'));

    final store = DeviceLoginStore(twitchApi: api, authStore: authStore);
    await store.start();

    expect(store.status, DeviceLoginStatus.error);
    expect(store.errorMessage, 'invalid client');

    store.dispose();
  });
}
