import 'package:flutter_test/flutter_test.dart';
import 'package:comunikte/core/audio/gain_controller.dart';

void main() {
  group('GainController Unit Tests (Software Gain PCM)', () {
    late GainController controller;

    setUp(() {
      controller = GainController();
    });

    test('Initial software gain is 1.0 (100%)', () {
      expect(controller.softwareGain, 1.0);
      expect(controller.gainPercentage, 100);
      expect(controller.isMuted, isFalse);
    });

    test('Clamps gain within 0.0 to 2.0 range', () {
      controller.setGain(2.5);
      expect(controller.softwareGain, 2.0);
      expect(controller.gainPercentage, 200);

      controller.setGain(-0.5);
      expect(controller.softwareGain, 0.0);
      expect(controller.gainPercentage, 0);
      expect(controller.isMuted, isTrue);
    });

    test('Mute and unmute restores previous gain value', () {
      controller.setGain(1.75);
      expect(controller.softwareGain, 1.75);

      controller.toggleMute();
      expect(controller.isMuted, isTrue);
      expect(controller.softwareGain, 0.0);

      controller.toggleMute();
      expect(controller.isMuted, isFalse);
      expect(controller.softwareGain, 1.75);
    });

    test('Preset buttons set expected values for motorcycle environments', () {
      controller.setPresetHighway();
      expect(controller.softwareGain, 1.5);
      expect(controller.gainPercentage, 150);

      controller.setPresetMaxBoost();
      expect(controller.softwareGain, 2.0);
      expect(controller.gainPercentage, 200);

      controller.setPresetCity();
      expect(controller.softwareGain, 1.0);
      expect(controller.gainPercentage, 100);

      controller.setPresetQuiet();
      expect(controller.softwareGain, 0.0);
      expect(controller.isMuted, isTrue);
    });
  });
}
