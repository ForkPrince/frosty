import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frosty/apis/base_api_client.dart';
import 'package:frosty/apis/twitch_api.dart';
import 'package:frosty/models/user.dart';
import 'package:frosty/screens/settings/stores/auth_store.dart';
import 'package:frosty/utils/twitch_oauth_scopes.dart';
import 'package:mocktail/mocktail.dart';

class MockTwitchApi extends Mock implements TwitchApi {}

const _user = UserTwitch(
  '12345',
  'testuser',
  'TestUser',
  'https://cdn/profile.png',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockTwitchApi api;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    api = MockTwitchApi();

    when(() => api.getUserInfo()).thenAnswer((_) async => _user);
    when(
      () => api.getUserBlockedList(id: any(named: 'id')),
    ).thenAnswer((_) async => <UserBlockedTwitch>[]);
    when(
      () => api.getModeratedChannels(id: any(named: 'id')),
    ).thenAnswer((_) async => <String>[]);
    when(() => api.getDefaultToken()).thenAnswer((_) async => 'anonymous');
  });

  test('init refreshes an expired device-flow token', () async {
    FlutterSecureStorage.setMockInitialValues({
      'user_token': 'expired',
      'refresh_token': 'refresh-1',
    });

    when(
      () => api.validateToken(token: 'expired'),
    ).thenAnswer((_) async => null);
    when(() => api.refreshUserToken(refreshToken: 'refresh-1')).thenAnswer(
      (_) async => const TwitchUserToken(
        accessToken: 'fresh',
        refreshToken: 'refresh-2',
        expiresIn: 14400,
        scopes: twitchUserScopes,
      ),
    );
    when(() => api.validateToken(token: 'fresh')).thenAnswer(
      (_) async =>
          const TwitchTokenInfo(scopes: twitchUserScopes, userId: '12345'),
    );

    final store = AuthStore(twitchApi: api);
    await store.init();

    expect(store.isLoggedIn, isTrue);
    expect(store.token, 'fresh');

    const storage = FlutterSecureStorage();
    expect(await storage.read(key: 'user_token'), 'fresh');
    expect(await storage.read(key: 'refresh_token'), 'refresh-2');
  });

  test('init logs out when the refresh token is rejected', () async {
    FlutterSecureStorage.setMockInitialValues({
      'user_token': 'expired',
      'refresh_token': 'rejected',
    });

    when(
      () => api.validateToken(token: 'expired'),
    ).thenAnswer((_) async => null);
    when(
      () => api.refreshUserToken(refreshToken: 'rejected'),
    ).thenThrow(const ApiException('Invalid refresh token'));

    final store = AuthStore(twitchApi: api);
    await store.init();

    expect(store.isLoggedIn, isFalse);
    expect(store.token, 'anonymous');

    const storage = FlutterSecureStorage();
    expect(await storage.read(key: 'refresh_token'), isNull);
  });

  test('login stores a refresh token and a WebView login clears it', () async {
    when(() => api.validateToken(token: 'device-access')).thenAnswer(
      (_) async =>
          const TwitchTokenInfo(scopes: twitchUserScopes, userId: '12345'),
    );
    when(() => api.validateToken(token: 'web-access')).thenAnswer(
      (_) async =>
          const TwitchTokenInfo(scopes: twitchUserScopes, userId: '12345'),
    );

    const storage = FlutterSecureStorage();
    final store = AuthStore(twitchApi: api);

    await store.login(token: 'device-access', refreshToken: 'refresh');
    expect(store.isLoggedIn, isTrue);
    expect(await storage.read(key: 'refresh_token'), 'refresh');

    await store.login(token: 'web-access');
    expect(await storage.read(key: 'refresh_token'), isNull);
  });

  test('logout deletes the refresh token', () async {
    when(() => api.validateToken(token: 'device-access')).thenAnswer(
      (_) async =>
          const TwitchTokenInfo(scopes: twitchUserScopes, userId: '12345'),
    );

    const storage = FlutterSecureStorage();
    final store = AuthStore(twitchApi: api);
    await store.login(token: 'device-access', refreshToken: 'refresh');

    await store.logout();

    expect(store.isLoggedIn, isFalse);
    expect(await storage.read(key: 'refresh_token'), isNull);
  });
}
