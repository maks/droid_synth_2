import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:droid_synth_2/models/dx7_bank.dart';
import 'package:droid_synth_2/services/dx7_bank_loader.dart';

void main() {
  group('Dx7Patch', () {
    test('creates patch with name and data', () {
      final mockData = Uint8List(128)..fill(0);
      // Set ASCII characters for name in first 6 bytes: T, U, V, W, X, Y (84-89)
      for (int i = 0; i < 6; i++) {
        mockData[i] = 84 + i;
      }

      final patch = Dx7Patch.fromVoiceData(mockData);

      expect(patch.name, 'TUVWXY');
      expect(patch.data.length, 128);
    });

    test('throws error for invalid size', () {
      expect(
        () => Dx7Patch.fromVoiceData(Uint8List(100)),
        throwsArgumentError,
      );
    });

    test('generates default name when empty', () {
      final mockData = Uint8List(128)..fill(0);
      final patch = Dx7Patch.fromVoiceData(mockData);

      expect(patch.name, isNotEmpty);
    });

    test('equality checks work correctly', () {
      final data1 = Uint8List(128)..fill(1);
      final data2 = Uint8List(128)..fill(1);
      
      final patch1 = Dx7Patch.fromVoiceData(data1);
      final patch2 = Dx7Patch.fromVoiceData(data2);
      final patch3 = Dx7Patch.fromVoiceData(data1);

      expect(patch1, equals(patch1));
      expect(patch1, equals(patch2));
      expect(patch1, equals(patch3));
      expect(patch1.hashCode, equals(patch2.hashCode));
    });
  });

  group('Dx7Bank', () {
    test('creates bank from valid sysex with proper voice parsing', () {
      // DX7 single voice dump format:
      // F0 43 00 20 00 00 00 44 02 <128 bytes voice data> F7
      // Byte indices: 0,1,2,3,4 ,5 ,6 ,7 ,8, 9-136,       137
      final voiceData = Uint8List(128)..fill(0);
      // ASCII: M, N, O, P, Q, R (77-82)
      for (int i = 0; i < 6; i++) {
        voiceData[i] = 77 + i;
      }

      final sysexData = Uint8List(145);
      // Set header bytes
      sysexData[0] = 0xF0; // SYSEX start
      sysexData[1] = 0x43; // Yamaha
      sysexData[2] = 0x00;
      sysexData[3] = 0x20; // Data Set Code
      sysexData[4] = 0x00;
      sysexData[5] = 0x00;
      sysexData[6] = 0x00;
      sysexData[7] = 0x44; // Model ID MSB
      sysexData[8] = 0x02; // Model ID LSB
      // Copy voice data (128 bytes at indices 9-136)
      for (int i = 0; i < 128; i++) {
        sysexData[9 + i] = voiceData[i];
      }
      // Set F7 end byte at index 137
      sysexData[137] = 0xF7;

      final bank = Dx7Bank.fromSysex(sysexData);

      expect(bank, isA<Dx7Bank>());
      expect(bank.patches[0], isNotNull);
      expect(bank.patches[0]!.name, 'MNOPQR');
      expect(bank.patches[1], isNull); // Only 1 voice loaded
    });

    test('handles empty SYSEX data', () {
      final bank = Dx7Bank.fromSysex(Uint8List(0));
      expect(bank, isA<Dx7Bank>());
      expect(bank.patches.length, 128);
      expect(bank.patches.every((p) => p == null), isTrue);
    });

    test('pads to 128 patches', () {
      final bank = Dx7Bank.fromSysex(Uint8List(50));
      expect(bank.patches.length, 128);
      expect(bank, isA<Dx7Bank>());
    });

    test('getPatch returns correct patch at index', () {
      // Create 6-byte name: A, B, C, D, E, F (65-70)
      final voiceData = Uint8List(128)..fill(0);
      for (int i = 0; i < 6; i++) {
        voiceData[i] = 65 + i; // 'ABCDEF'
      }

      final sysexData = Uint8List(145);
      // Header bytes
      sysexData[0] = 0xF0;
      sysexData[1] = 0x43;
      sysexData[2] = 0x00;
      sysexData[3] = 0x20;
      sysexData[4] = 0x00;
      sysexData[5] = 0x00;
      sysexData[6] = 0x00;
      sysexData[7] = 0x44;
      sysexData[8] = 0x02;
      // Voice data at indices 9-136
      for (int i = 0; i < 128; i++) {
        sysexData[9 + i] = voiceData[i];
      }
      sysexData[137] = 0xF7;

      final bank = Dx7Bank.fromSysex(sysexData);

      final patch = bank.getPatch(0);
      expect(patch, isNotNull);
      expect(patch!.name, 'ABCDEF');

      expect(() => bank.getPatch(128), throwsRangeError);
    });

    test('validPatches returns only non-null entries', () {
      final bank = Dx7Bank.fromSysex(Uint8List(0));
      expect(bank.validPatches.isEmpty, isTrue);
    });
  });

  group('ChannelAssignment', () {
    test('creates unassigned assignment', () {
      final assignment = ChannelAssignment.unassigned(0);

      expect(assignment.channel, 0);
      expect(assignment.patchIndex, -1);
      expect(assignment.isAssigned, isFalse);
      expect(assignment.midiChannel, 1);
    });

    test('creates assigned assignment', () {
      final assignment = ChannelAssignment(5, 42);

      expect(assignment.channel, 5);
      expect(assignment.patchIndex, 42);
      expect(assignment.isAssigned, isTrue);
      expect(assignment.midiChannel, 6);
    });

    test('throws error for invalid channel', () {
      expect(
        () => ChannelAssignment(16, 0),
        throwsArgumentError,
      );
    });

    test('throws error for invalid patch index', () {
      expect(
        () => ChannelAssignment(0, 128),
        throwsArgumentError,
      );
    });

    test('copyWithPatchIndex creates new instance', () {
      final original = ChannelAssignment(1, 10);
      final updated = original.copyWithPatchIndex(50);

      expect(updated.channel, 1);
      expect(updated.patchIndex, 50);
      expect(updated, isNot(equals(original)));
    });

    test('equality checks work correctly', () {
      final a1 = ChannelAssignment(0, 10);
      final a2 = ChannelAssignment(0, 10);
      final a3 = ChannelAssignment(1, 10);

      expect(a1, equals(a1));
      expect(a1, equals(a2));
      expect(a1, isNot(equals(a3)));
      expect(a1.hashCode, equals(a2.hashCode));
    });
  });

  group('Dx7BankLoader', () {
    test('parseFromSysex returns valid bank', () {
      final voiceData = Uint8List(128)..fill(1);
      for (int i = 0; i < 6; i++) {
        voiceData[i] = 65 + i; // 'ABCDE'
      }

      final sysexData = Uint8List(145);
      // Set header bytes correctly
      sysexData[0] = 0xF0; // Start
      sysexData[1] = 0x43; // Yamaha
      sysexData[2] = 0x00;
      sysexData[3] = 0x20; // Data Set Code
      sysexData[4] = 0x00;
      sysexData[5] = 0x00;
      sysexData[6] = 0x00;
      sysexData[7] = 0x44; // Model ID MSB
      sysexData[8] = 0x02; // Model ID LSB
      // Copy voice data
      for (int i = 0; i < 128; i++) {
        sysexData[9 + i] = voiceData[i];
      }
      // Set F7 end byte
      sysexData[137] = 0xF7;

      final bank = Dx7BankLoader.parseFromSysex(sysexData);

      expect(bank, isNotNull);
      expect(bank!.patches[0], isNotNull);
      expect(bank.patches[0]!.name, 'ABCDEF');
    });

    test('isValidDx7Sysex returns true for valid data', () {
      final sysexData = Uint8List(145)..fill(0);
      // Set header bytes
      sysexData[0] = 0xF0;
      sysexData[1] = 0x43;
      sysexData[2] = 0x00;
      sysexData[3] = 0x20;
      sysexData[4] = 0x00;
      sysexData[5] = 0x00;
      sysexData[6] = 0x00;
      sysexData[7] = 0x44; // Model ID MSB
      sysexData[8] = 0x02; // Model ID LSB
      sysexData[144] = 0xF7; // End of SYSEX

      expect(Dx7BankLoader.isValidDx7Sysex(sysexData), isTrue);
    });

    test('isValidDx7Sysex returns false for invalid data', () {
      expect(Dx7BankLoader.isValidDx7Sysex(Uint8List(5)), isFalse);
      expect(Dx7BankLoader.isValidDx7Sysex(Uint8List(0)), isFalse);

      final wrongHeader = [0xF0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00];
      expect(Dx7BankLoader.isValidDx7Sysex(Uint8List.fromList(wrongHeader)), isFalse);
    });
  });
}

extension Fill on Uint8List {
  void fill(int value) {
    for (int i = 0; i < length; i++) {
      this[i] = value;
    }
  }
}
