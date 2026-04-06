import 'dart:convert';
import 'dart:typed_data';

import '../models/dx7_bank.dart';

/// Service for loading and parsing DX7 SYSEX banks
class Dx7BankLoader {
  final List<Dx7Bank> _loadedBanks = [];

  /// Load a DX7 SYSEX bank from raw bytes
  /// Returns the parsed Dx7Bank or null if the data is not a valid DX7 bank
  Dx7Bank? loadFromBytes(Uint8List bytes) {
    try {
      final bank = Dx7Bank.fromSysex(bytes);
      _loadedBanks.add(bank);
      return bank;
    } catch (e) {
      print('Error loading DX7 bank from bytes: $e');
      return null;
    }
  }

  /// Load a DX7 SYSEX bank from a file path (using Dart file I/O)
  /// This uses dart:io which requires a Flutter app with io enabled
  /// Alternative: use platform channels or file_picker package for cross-platform support
  // Future<Dx7Bank?> loadFromFile(String filePath) async {
  //   try {
  //     final fileBytes = File(filePath).readAsBytesSync();
  //     return loadFromBytes(fileBytes);
  //   } catch (e) {
  //     print('Error loading DX7 bank from file $filePath: $e');
  //     return null;
  //   }
  // }

  /// Load from base64 encoded string (useful for network/transmission scenarios)
  static Dx7Bank? loadFromBase64(String base64String) {
    try {
      final bytes = base64Decode(base64String);
      return parseFromSysex(Uint8List.fromList(bytes));
    } catch (e) {
      print('Error decoding base64: $e');
      return null;
    }
  }

  /// Parse a DX7 bank from SYSEX data
  static Dx7Bank? parseFromSysex(Uint8List sysexData) {
    try {
      final bank = Dx7Bank.fromSysex(sysexData);
      if (bank.validPatches.isEmpty) {
        print('Warning: Loaded bank has no valid patches');
      }
      return bank;
    } catch (e) {
      print('Error parsing SYSEX data: $e');
      return null;
    }
  }

  /// Get the list of loaded banks (for debugging/history)
  List<Dx7Bank> get loadedBanks => List.unmodifiable(_loadedBanks);

  /// Clear all loaded banks
  void clearLoadedBanks() {
    _loadedBanks.clear();
  }

  /// Validate that the data is a DX7 SYSEX format
  /// Supported formats:
  /// - Single voice: F0 43 00 20 00 00 00 44 02 + 128 bytes + F7
  /// - Bank dump: F0 43 00 20 00 00 00 44 00 + 5120 bytes + F7
  /// - ROM dump: F0 43 00 09 20 00 31 + 4096 bytes + F7
  static bool isValidDx7Sysex(Uint8List data) {
    if (data.isEmpty) return false;
    if (data[0] != 0xF0) return false;
    if (data.length < 9) return false;

    // Check for single voice format: F0 43 00 20 00 00 00 44 02
    if (data[1] == 0x43 &&  // Yamaha
        data[2] == 0x00 &&
        data[3] == 0x20 &&  // Data Set Code
        data[4] == 0x00 &&
        data[5] == 0x00 &&
        data[6] == 0x00 &&
        data[7] == 0x44 &&  // Model ID MSB (DX7)
        data[8] == 0x02) {  // Model ID LSB (DX7) - Single Voice
      return data.length == 145 && data[144] == 0xF7;
    }

    // Check for bank dump format: F0 43 00 20 00 00 00 44 00
    if (data[1] == 0x43 &&  // Yamaha
        data[2] == 0x00 &&
        data[3] == 0x20 &&  // Data Set Code
        data[4] == 0x00 &&
        data[5] == 0x00 &&
        data[6] == 0x00 &&
        data[7] == 0x44 &&  // Model ID MSB (DX7)
        data[8] == 0x00) {  // Model ID LSB (DX7) - Bank
      return data.length > 9 && data.last == 0xF7;
    }

    // Check for ROM dump format: F0 43 00 09 20 00 31 + 4096 bytes + F7
    if (data.length == 4104 &&
        data[1] == 0x43 &&  // Yamaha
        data[2] == 0x00 &&
        data[3] == 0x09 &&  // ROM dump command
        data[4] == 0x20 &&
        data[5] == 0x00 &&
        data[6] == 0x31 &&
        data[4103] == 0xF7) {  // F7 end marker
      return true;
    }

    return false;
  }

  /// Get the type of DX7 SYSEX format
  /// Returns: 'single-voice', 'bank-dump', 'rom-dump', or 'unknown'
  static String getSysexType(Uint8List data) {
    if (data.isEmpty || data[0] != 0xF0) return 'unknown';

    // Check for single voice format
    if (data.length >= 145 &&
        data[1] == 0x43 &&
        data[2] == 0x00 &&
        data[3] == 0x20 &&
        data[4] == 0x00 &&
        data[5] == 0x00 &&
        data[6] == 0x00 &&
        data[7] == 0x44 &&
        data[8] == 0x02 &&
        data[144] == 0xF7) {
      return 'single-voice';
    }

    // Check for bank dump format
    if (data.length > 9 &&
        data[1] == 0x43 &&
        data[2] == 0x00 &&
        data[3] == 0x20 &&
        data[4] == 0x00 &&
        data[5] == 0x00 &&
        data[6] == 0x00 &&
        data[7] == 0x44 &&
        data[8] == 0x00 &&
        data.last == 0xF7) {
      return 'bank-dump';
    }

    // Check for ROM dump format
    if (data.length == 4104 &&
        data[1] == 0x43 &&
        data[2] == 0x00 &&
        data[3] == 0x09 &&
        data[4] == 0x20 &&
        data[5] == 0x00 &&
        data[6] == 0x31 &&
        data[4103] == 0xF7) {
      return 'rom-dump';
    }

    return 'unknown';
  }

  /// Estimate the number of voices in the SYSEX data
  static int estimateVoiceCount(Uint8List data) {
    if (data.isEmpty || data[0] != 0xF0) return 0;

    // Check for ROM dump format - contains 32 patches
    if (data.length == 4104 &&
        data[1] == 0x43 &&
        data[2] == 0x00 &&
        data[3] == 0x09 &&
        data[4] == 0x20 &&
        data[5] == 0x00 &&
        data[6] == 0x31) {
      return 32;
    }

    // Check for single voice format - 1 patch
    if (data.length == 145 &&
        data[1] == 0x43 &&
        data[3] == 0x20 &&
        data[8] == 0x02) {
      return 1;
    }

    // Check for bank dump format - 128 patches
    if (data.length > 9 &&
        data[1] == 0x43 &&
        data[3] == 0x20 &&
        data[8] == 0x00) {
      return 128;
    }

    // Try to count multiple single voices
    int count = 0;
    int offset = 0;

    while (offset < data.length) {
      while (offset < data.length && data[offset] != 0xF0) {
        offset++;
      }
      if (offset >= data.length) break;

      if (_parseSingleVoice(data, offset) >= 0) {
        count++;
        if (count >= 128) break;
        offset += 145;
      } else {
        offset++;
      }
    }

    return count;
  }

  /// Parse a single voice for estimation purposes
  static int _parseSingleVoice(Uint8List data, int startOffset) {
    if (startOffset + 131 >= data.length) return -1;
    if (data[startOffset] != 0xF0) return -1;

    final f7Index = _findF7InSysex(data, startOffset);
    if (f7Index == -1) return -1;

    const int voiceDataStartOffset = 8;
    const int voiceDataLength = 128;

    if (f7Index - startOffset - voiceDataStartOffset >= voiceDataLength) {
      return f7Index;
    }

    return -1;
  }

  /// Find F7 end marker in SYSEX data
  static int _findF7InSysex(Uint8List data, int startOffset) {
    for (int candidate = startOffset + 131;
        candidate < startOffset + 135 && candidate < data.length;
        candidate++) {
      if (data[candidate] == 0xF7) {
        if (candidate >= startOffset + 137) {
          return candidate;
        }
      }
    }
    return -1;
  }
}
