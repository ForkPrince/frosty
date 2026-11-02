import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frosty/screens/settings/stores/settings_store.dart';
import 'package:frosty/screens/settings/video_settings.dart';

/// Regression tests for the stream-proxy settings UI.
///
/// The Custom (TTVLOLv2) field was once hidden exactly when Custom was
/// first selected: the "is this a custom v2 value?" check matched the
/// Custom entry's own `v2:` value against the preset list. These tests
/// pump the real settings page, so that trap cannot return silently.
void main() {
  Future<void> pumpSettings(
    WidgetTester tester,
    SettingsStore store,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: VideoSettings(settingsStore: store)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Custom (TTVLOLv2) shows the host:port text field', (
    tester,
  ) async {
    final store = SettingsStore()..streamProxy = 'v2:';
    await pumpSettings(tester, store);

    expect(find.text('Stream proxy'), findsOneWidget);
    // The hint text of the custom v2 field.
    expect(find.text('twitch-al.nadeko.net:2023'), findsOneWidget);
  });

  testWidgets('Nadeko (TTVLOLv2) preset does not show the custom field', (
    tester,
  ) async {
    final store = SettingsStore()
      ..streamProxy = 'v2:twitch-al.nadeko.net:2023';
    await pumpSettings(tester, store);

    expect(find.text('Stream proxy'), findsOneWidget);
    expect(find.text('twitch-al.nadeko.net:2023'), findsNothing);
  });

  testWidgets('stream proxy dropdown offers Nadeko (TTVLOLv1)', (
    tester,
  ) async {
    final store = SettingsStore();
    await pumpSettings(tester, store);

    await tester.tap(find.byType(DropdownButton<String>).first);
    await tester.pumpAndSettle();

    expect(find.text('Nadeko (TTVLOLv1)'), findsOneWidget);
    expect(find.text('Nadeko (TTVLOLv2)'), findsOneWidget);
    expect(find.text('Custom (TTVLOLv2)'), findsOneWidget);
  });
}
