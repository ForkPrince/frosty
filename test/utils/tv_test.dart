import 'package:flutter_test/flutter_test.dart';
import 'package:frosty/utils/tv.dart';

void main() {
  group('hasTvSystemFeature', () {
    test('detects Android TV leanback devices', () {
      expect(
        hasTvSystemFeature([
          'android.hardware.touchscreen',
          'android.software.leanback',
        ]),
        isTrue,
      );
    });

    test('detects Fire TV devices', () {
      expect(hasTvSystemFeature(['amazon.hardware.fire_tv']), isTrue);
    });

    test('detects the television hardware form factor', () {
      expect(hasTvSystemFeature(['android.hardware.type.television']), isTrue);
    });

    test('returns false for phones and tablets', () {
      expect(
        hasTvSystemFeature([
          'android.hardware.touchscreen',
          'android.hardware.camera',
          'android.software.leanback_only_phone_marker',
        ]),
        isFalse,
      );
    });
  });

  group('isTv', () {
    tearDown(() => setTvForTesting(false));

    test('reflects the detected device', () {
      expect(isTv, isFalse);

      setTvForTesting(true);

      expect(isTv, isTrue);
    });
  });
}
