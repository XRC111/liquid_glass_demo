import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_demo/glass/glass.dart';

void main() {
  group('GlassQuality.fromDevice', () {
    test('API 29+ -> full', () {
      expect(GlassQuality.fromDevice(sdkInt: 29, lowRamDevice: false), GlassQuality.full);
      expect(GlassQuality.fromDevice(sdkInt: 33, lowRamDevice: false), GlassQuality.full);
      expect(GlassQuality.fromDevice(sdkInt: 35, lowRamDevice: false), GlassQuality.full);
    });
    test('API 26-28 -> medium', () {
      expect(GlassQuality.fromDevice(sdkInt: 26, lowRamDevice: false), GlassQuality.medium);
      expect(GlassQuality.fromDevice(sdkInt: 28, lowRamDevice: false), GlassQuality.medium);
    });
    test('API 24-25 -> minimal', () {
      expect(GlassQuality.fromDevice(sdkInt: 24, lowRamDevice: false), GlassQuality.minimal);
      expect(GlassQuality.fromDevice(sdkInt: 25, lowRamDevice: false), GlassQuality.minimal);
    });
    test('low memory device -> minimal regardless of API', () {
      expect(GlassQuality.fromDevice(sdkInt: 35, lowRamDevice: true), GlassQuality.minimal);
    });
  });

  group('quality tier budgets', () {
    test('minimal skips blur & dispersion', () {
      expect(GlassQuality.minimal.usesBlur, isFalse);
      expect(GlassQuality.minimal.usesDispersion, isFalse);
      expect(GlassQuality.minimal.refractionScale, lessThan(1.0));
    });
    test('capture scale shrinks for lower tiers', () {
      expect(
        GlassQuality.full.captureScale,
        greaterThan(GlassQuality.medium.captureScale),
      );
      expect(
        GlassQuality.medium.captureScale,
        greaterThan(GlassQuality.minimal.captureScale),
      );
    });
  });
}
