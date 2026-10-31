import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:frosty/apis/base_api_client.dart';
import 'package:frosty/apis/twitch_api.dart';
import 'package:frosty/screens/settings/stores/auth_store.dart';
import 'package:frosty/utils/twitch_oauth_scopes.dart';
import 'package:mobx/mobx.dart';

part 'device_login_store.g.dart';

/// The stages of the device code grant flow shown by the login screen.
enum DeviceLoginStatus {
  idle,
  requesting,
  waiting,
  authorized,
  denied,
  expired,
  error,
}

class DeviceLoginStore = DeviceLoginBase with _$DeviceLoginStore;

abstract class DeviceLoginBase with Store {
  final TwitchApi twitchApi;
  final AuthStore authStore;

  /// When true, request moderator scopes and atomically upgrade the session.
  final bool upgradeModeratorScopes;

  DeviceLoginBase({
    required this.twitchApi,
    required this.authStore,
    this.upgradeModeratorScopes = false,
  });

  @readonly
  DeviceLoginStatus _status = DeviceLoginStatus.idle;

  /// Code the user enters at [verificationUri].
  @readonly
  String? _userCode;

  /// Twitch's device activation URL, including the code as a query param.
  @readonly
  String? _verificationUri;

  @readonly
  String? _errorMessage;

  Timer? _pollTimer;
  String? _deviceCode;
  int _intervalSeconds = 5;
  int _generation = 0;

  bool get isBusy =>
      _status == DeviceLoginStatus.requesting ||
      _status == DeviceLoginStatus.waiting;

  /// Requests a device code and starts polling until the user authorizes it on
  /// another device (or the code expires).
  @action
  Future<void> start() async {
    cancel();
    final generation = ++_generation;

    _status = DeviceLoginStatus.requesting;
    _userCode = null;
    _verificationUri = null;
    _errorMessage = null;
    _deviceCode = null;

    try {
      final scopes =
          upgradeModeratorScopes || authStore.shouldRequestModeratorScopes
          ? twitchAllUserScopes
          : twitchUserScopes;
      final deviceCode = await twitchApi.requestDeviceCode(scopes: scopes);
      if (generation != _generation) return;

      _deviceCode = deviceCode.deviceCode;
      _userCode = deviceCode.userCode;
      _verificationUri = deviceCode.verificationUri;
      _intervalSeconds = deviceCode.interval > 0 ? deviceCode.interval : 5;
      _status = DeviceLoginStatus.waiting;

      _schedulePoll(generation);
    } on ApiException catch (e) {
      if (generation != _generation) return;
      _status = DeviceLoginStatus.error;
      _errorMessage = e.message;
    } catch (e) {
      if (generation != _generation) return;
      debugPrint('Device login failed: $e');
      _status = DeviceLoginStatus.error;
      _errorMessage = 'Could not start device login. Please try again.';
    }
  }

  void _schedulePoll(int generation) {
    _pollTimer?.cancel();
    _pollTimer = Timer(
      Duration(seconds: _intervalSeconds),
      () => _poll(generation),
    );
  }

  Future<void> _poll(int generation) async {
    if (generation != _generation) return;
    final deviceCode = _deviceCode;
    if (deviceCode == null) return;

    try {
      final result = await twitchApi.pollDeviceToken(deviceCode: deviceCode);
      if (generation != _generation) return;

      switch (result.status) {
        case TwitchDeviceTokenStatus.authorized:
          await _complete(result.token!);
        case TwitchDeviceTokenStatus.pending:
          _schedulePoll(generation);
        case TwitchDeviceTokenStatus.slowDown:
          _intervalSeconds += 5;
          _schedulePoll(generation);
        case TwitchDeviceTokenStatus.denied:
          _status = DeviceLoginStatus.denied;
          _errorMessage =
              'Authorization was denied on the other device. Try again.';
        case TwitchDeviceTokenStatus.expired:
          _status = DeviceLoginStatus.expired;
          _errorMessage = 'This code expired. Try again to get a new one.';
      }
    } on ApiException catch (e) {
      if (generation != _generation) return;
      _status = DeviceLoginStatus.error;
      _errorMessage = e.message;
    } catch (e) {
      if (generation != _generation) return;
      debugPrint('Device login polling failed: $e');
      _status = DeviceLoginStatus.error;
      _errorMessage = 'Something went wrong. Please try again.';
    }
  }

  Future<void> _complete(TwitchUserToken token) async {
    try {
      if (upgradeModeratorScopes) {
        final upgraded = await authStore.completeModeratorUpgrade(
          token: token.accessToken,
          refreshToken: token.refreshToken,
          popOnSuccess: false,
        );
        if (!upgraded) {
          _status = DeviceLoginStatus.error;
          _errorMessage = 'Could not enable moderator tools. Try again.';
          return;
        }
      } else {
        await authStore.login(
          token: token.accessToken,
          refreshToken: token.refreshToken,
        );
        if (!authStore.isLoggedIn) {
          _status = DeviceLoginStatus.error;
          _errorMessage =
              'Logged in, but could not load your Twitch profile. Try again.';
          return;
        }
      }

      _status = DeviceLoginStatus.authorized;
    } catch (e) {
      debugPrint('Device login completion failed: $e');
      _status = DeviceLoginStatus.error;
      _errorMessage = 'Could not finish logging in. Please try again.';
    }
  }

  /// Stops polling and forgets the current code.
  @action
  void cancel() {
    _generation++;
    _pollTimer?.cancel();
    _pollTimer = null;
    _deviceCode = null;
    if (_status == DeviceLoginStatus.requesting ||
        _status == DeviceLoginStatus.waiting) {
      _status = DeviceLoginStatus.idle;
    }
  }

  /// Permanently stops polling. Called when the screen is disposed.
  void dispose() {
    _generation++;
    _pollTimer?.cancel();
    _pollTimer = null;
    _deviceCode = null;
  }
}
