import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:frosty/apis/twitch_api.dart';
import 'package:frosty/screens/onboarding/stores/device_login_store.dart';
import 'package:frosty/screens/settings/stores/auth_store.dart';
import 'package:frosty/widgets/frosty_app_bar.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// Login screen for TVs and other devices where using the Twitch WebView is
/// impractical. Shows a short code and polls until the user authorizes it on a
/// phone or computer.
class DeviceLoginScreen extends StatefulWidget {
  /// Optional widget to navigate to after a successful login.
  final Widget? routeAfter;

  /// When true, requests moderator scopes and upgrades the current session
  /// instead of logging in from scratch.
  final bool upgradeModeratorScopes;

  const DeviceLoginScreen({
    super.key,
    this.routeAfter,
    this.upgradeModeratorScopes = false,
  });

  @override
  State<DeviceLoginScreen> createState() => _DeviceLoginScreenState();
}

class _DeviceLoginScreenState extends State<DeviceLoginScreen> {
  late final DeviceLoginStore _store;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _store = DeviceLoginStore(
      twitchApi: context.read<TwitchApi>(),
      authStore: context.read<AuthStore>(),
      upgradeModeratorScopes: widget.upgradeModeratorScopes,
    );
    _store.start();
  }

  @override
  void dispose() {
    _store.dispose();
    super.dispose();
  }

  void _handleAuthorized() {
    if (_navigated) return;
    _navigated = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.routeAfter != null) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => widget.routeAfter!),
        );
      } else {
        Navigator.of(context).pop();
      }
    });
  }

  Future<void> _openVerificationUri() async {
    final uri = _store.verificationUri;
    if (uri == null) return;
    try {
      await launchUrl(Uri.parse(uri), mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Could not open activation page: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: FrostyAppBar(
        title: Text(
          widget.upgradeModeratorScopes
              ? 'Enable moderator tools'
              : 'Log in on another device',
        ),
      ),
      body: Observer(
        builder: (context) {
          if (_store.status == DeviceLoginStatus.authorized) {
            _handleAuthorized();
          }

          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.devices_rounded,
                      size: 56,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      widget.upgradeModeratorScopes
                          ? 'Authorize moderator tools on another device'
                          : 'Go to Twitch on your phone or computer',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Enter the code below to authorize this TV.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 24),
                    _buildBody(context),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final theme = Theme.of(context);

    switch (_store.status) {
      case DeviceLoginStatus.idle:
      case DeviceLoginStatus.requesting:
        return Column(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            const Text('Getting a code from Twitch...'),
            const SizedBox(height: 8),
            TextButton(onPressed: _store.start, child: const Text('Try again')),
          ],
        );

      case DeviceLoginStatus.waiting:
        return Column(
          children: [
            Text(
              'Enter this code',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: SelectableText(
                _store.userCode ?? '',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 6,
                ),
              ),
            ),
            const SizedBox(height: 16),
            SelectableText(
              'twitch.tv/activate',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: _openVerificationUri,
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('Open activation page'),
            ),
            const SizedBox(height: 24),
            const LinearProgressIndicator(),
            const SizedBox(height: 12),
            Text(
              'Waiting for you to authorize on another device...',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        );

      case DeviceLoginStatus.expired:
      case DeviceLoginStatus.denied:
      case DeviceLoginStatus.error:
        return Column(
          children: [
            Text(
              _store.errorMessage ?? 'Something went wrong.',
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.colorScheme.error),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _store.start,
              child: const Text('Try again'),
            ),
          ],
        );

      case DeviceLoginStatus.authorized:
        return Column(
          children: [
            Icon(Icons.check_circle_rounded, size: 48, color: Colors.green),
            const SizedBox(height: 12),
            const Text('Logged in!'),
          ],
        );
    }
  }
}
