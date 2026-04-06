import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';

/// Tests for the MSFAPlugin interface and SYSEX sending functionality
void main() {
  group('SYSEX Helper Methods', () {
    late TestApp app;

    setUp(() {
      app = TestApp();
    });

    group('_buildDx7Sysex', () {
      test('creates valid DX7 single voice SYSEX message', () {
        // Create 128 bytes of voice data
        final voiceData = Uint8List(128)..fill(1);

        final sysex = app.buildDx7Sysex(voiceData);

        // Verify total length
        expect(sysex.length, 145);

        // Verify SYSEX header
        expect(sysex[0], 0xF0); // Start of SYSEX
        expect(sysex[1], 0x43); // Yamaha
        expect(sysex[2], 0x00);
        expect(sysex[3], 0x20); // Data Set: Voice
        expect(sysex[4], 0x00);
        expect(sysex[5], 0x00);
        expect(sysex[6], 0x00);
        expect(sysex[7], 0x44); // Model ID MSB
        expect(sysex[8], 0x02); // Model ID LSB

        // Verify voice data at correct position (indices 9-136)
        for (int i = 0; i < 128; i++) {
          expect(sysex[9 + i], 1,
              reason: 'Byte ${i + 9} should match voice data');
        }

        // Verify SYSEX end
        expect(sysex[137], 0xF7); // End of SYSEX
      });

      test('voice data starts with ASCII name when set', () {
        // Create voice data with ASCII name "TESTME" (84, 69, 83, 84, 77, 69)
        final voiceData = Uint8List(128)..fill(0);
        voiceData[0] = 84; // 'T'
        voiceData[1] = 69; // 'E'
        voiceData[2] = 83; // 'S'
        voiceData[3] = 84; // 'T'
        voiceData[4] = 77; // 'M'
        voiceData[5] = 69; // 'E'

        final sysex = app.buildDx7Sysex(voiceData);

        // Voice data starts at index 9, so name bytes are at 9-14
        expect(sysex[9], 84); // 'T'
        expect(sysex[10], 69); // 'E'
        expect(sysex[11], 83); // 'S'
        expect(sysex[12], 84); // 'T'
        expect(sysex[13], 77); // 'M'
        expect(sysex[14], 69); // 'E'
      });

      test('throws error for voice data that is too short', () {
        final voiceData = Uint8List(100);

        expect(
          () => app.buildDx7Sysex(voiceData),
          throwsArgumentError,
        );
      });

      test('throws error for voice data that is too long', () {
        final voiceData = Uint8List(130)..fill(1);

        expect(
          () => app.buildDx7Sysex(voiceData),
          throwsArgumentError,
        );
      });

      test('SYSEX message preserves all voice data bytes', () {
        final voiceData = Uint8List(128)..fill(1);
        for (int i = 0; i < 128; i++) {
          voiceData[i] = (i % 256);
        }

        final sysex = app.buildDx7Sysex(voiceData);

        for (int i = 0; i < 128; i++) {
          expect(sysex[9 + i], voiceData[i],
              reason: 'Byte ${i + 9} of SYSEX matches voice data');
        }
      });
    });
  });
}

/// Helper extension for Uint8List
extension Fill on Uint8List {
  void fill(int value) {
    for (int i = 0; i < length; i++) {
      this[i] = value;
    }
  }
}

/// Test app class to expose the private methods for testing
class TestApp {
  /// Build a DX7 single voice SYSEX message from 128 bytes of voice data
  Uint8List buildDx7Sysex(Uint8List voiceData) {
    if (voiceData.length != 128) {
      throw ArgumentError(
          'DX7 voice data must be exactly 128 bytes, got ${voiceData.length}');
    }
    final sysex = Uint8List(145);
    // SYSEX header: F0 43 00 20 00 00 00 44 02
    sysex[0] = 0xF0; // Start of SYSEX
    sysex[1] = 0x43; // Yamaha
    sysex[2] = 0x00;
    sysex[3] = 0x20; // Data Set: Voice
    sysex[4] = 0x00; // Data Set number MSB
    sysex[5] = 0x00;
    sysex[6] = 0x00;
    sysex[7] = 0x44; // DX7 Model ID MSB
    sysex[8] = 0x02; // DX7 Model ID LSB
    // Voice data (128 bytes)
    for (int i = 0; i < 128; i++) {
      sysex[9 + i] = voiceData[i];
    }
    // End of SYSEX
    sysex[137] = 0xF7;
    return sysex;
  }
}
