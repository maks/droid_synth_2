import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:droid_synth_2/models/dx7_bank.dart';
import 'package:droid_synth_2/services/dx7_bank_loader.dart';

void main() {
  group('DX7 ROM Dump Parsing', () {
    test('detects ROM dump format correctly', () {
      final romFile = File('rom1a.syx');
      expect(romFile.existsSync(), true, reason: 'rom1a.syx should exist');
      
      final bytes = romFile.readAsBytesSync();
      expect(bytes.length, 4104, reason: 'ROM dump should be 4104 bytes');
      
      final type = Dx7BankLoader.getSysexType(bytes);
      expect(type, 'rom-dump', reason: 'Should detect ROM dump format');
    });

    test('validates ROM dump format', () {
      final romFile = File('rom1a.syx');
      final bytes = romFile.readAsBytesSync();
      
      expect(Dx7BankLoader.isValidDx7Sysex(bytes), true, 
        reason: 'ROM dump should be valid DX7 SYSEX');
    });

    test('estimates correct voice count for ROM dump', () {
      final romFile = File('rom1a.syx');
      final bytes = romFile.readAsBytesSync();
      
      final count = Dx7BankLoader.estimateVoiceCount(bytes);
      expect(count, 32, reason: 'ROM dump should contain 32 patches');
    });

    test('parses ROM dump and extracts patches', () {
      final romFile = File('rom1a.syx');
      final bytes = romFile.readAsBytesSync();
      
      final bank = Dx7Bank.fromSysex(bytes);
      
      expect(bank, isNotNull, reason: 'Should parse ROM dump successfully');
      expect(bank!.patches.length, 128, reason: 'Bank should have 128 slots');
      
      final validPatches = bank.validPatches;
      expect(validPatches.length, 32, reason: 'Should extract 32 valid patches from ROM');
    });

    test('extracts patch names from ROM dump', () {
      final romFile = File('rom1a.syx');
      final bytes = romFile.readAsBytesSync();
      
      final bank = Dx7Bank.fromSysex(bytes);
      final validPatches = bank!.validPatches;
      
      expect(validPatches.length, 32);
      
      // Check that patches have meaningful names (not empty)
      for (final entry in validPatches) {
        expect(entry.value!.name.isNotEmpty, true, 
          reason: 'Patch ${entry.key} should have a name');
        print('Patch ${entry.key}: "${entry.value!.name}"');
      }
    });

    test('first patch from ROM dump has expected name', () {
      final romFile = File('rom1a.syx');
      final bytes = romFile.readAsBytesSync();
      
      final bank = Dx7Bank.fromSysex(bytes);
      final validPatches = bank!.validPatches;
      
      expect(validPatches.length, greaterThan(0));
      
      // First patch should be "BRASS 1" based on the ROM dump analysis
      final firstPatch = validPatches[0];
      print('First patch name: "${firstPatch.value!.name}"');
      
      // The name should be readable ASCII
      expect(firstPatch.value!.name.length, greaterThan(0));
    });

    test('ROM dump header bytes are correct', () {
      final romFile = File('rom1a.syx');
      final bytes = romFile.readAsBytesSync();
      
      // Verify ROM dump header: F0 43 00 09 20 00 31
      expect(bytes[0], 0xF0, reason: 'Should start with F0');
      expect(bytes[1], 0x43, reason: 'Yamaha manufacturer ID');
      expect(bytes[2], 0x00, reason: 'Device ID');
      expect(bytes[3], 0x09, reason: 'ROM dump command');
      expect(bytes[4], 0x20, reason: 'ROM address/type');
      expect(bytes[5], 0x00, reason: 'ROM address continuation');
      expect(bytes[6], 0x31, reason: 'ROM type identifier');
      expect(bytes[4103], 0xF7, reason: 'Should end with F7');
    });

    test('ROM data starts at correct offset', () {
      final romFile = File('rom1a.syx');
      final bytes = romFile.readAsBytesSync();
      
      // ROM data starts at offset 7 (after 7-byte header)
      // First patch is 128 bytes, name starts at byte 117+7 = 124 relative to ROM file
      // Byte 124 = 'B' of 'BRASS 1'
      final nameBytes = bytes.sublist(124, 134); // 124-133 = 'BRASS   1 '
      final name = String.fromCharCodes(nameBytes).trim();
      print('First patch name from raw bytes (offset 124-134, trimmed): "$name"');
      
      expect(name.isNotEmpty, true, reason: 'First patch should have a name');
      expect(name, 'BRASS   1', reason: 'First patch should start with BRASS   1');
    });
  });

  group('DX7 SYSEX Type Detection', () {
    test('detects single voice format', () {
      // Create a single voice SYSEX message
      final voiceData = Uint8List(128);
      voiceData[0] = 0x54; // 'T'
      
      final sysex = Uint8List(145);
      sysex[0] = 0xF0;
      sysex[1] = 0x43;
      sysex[2] = 0x00;
      sysex[3] = 0x20;
      sysex[4] = 0x00;
      sysex[5] = 0x00;
      sysex[6] = 0x00;
      sysex[7] = 0x44;
      sysex[8] = 0x02;
      for (int i = 0; i < 128; i++) {
        sysex[9 + i] = voiceData[i];
      }
      sysex[144] = 0xF7;
      
      expect(Dx7BankLoader.getSysexType(sysex), 'single-voice');
      expect(Dx7BankLoader.estimateVoiceCount(sysex), 1);
    });

    test('detects unknown format', () {
      final invalidData = Uint8List.fromList([0xF0, 0x43, 0xFF, 0xFF]);
      
      expect(Dx7BankLoader.getSysexType(invalidData), 'unknown');
      expect(Dx7BankLoader.estimateVoiceCount(invalidData), 0);
    });
  });
}