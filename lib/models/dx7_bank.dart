import 'dart:typed_data';
import 'package:collection/collection.dart';

/// A single DX7 voice/patch (128 bytes of FM synthesis data)
class Dx7Patch {
  /// The patch name (6 characters, typically padded with spaces)
  final String name;
  /// The DX7 voice data (128 bytes)
  final Uint8List data;

  Dx7Patch({
    required this.name,
    required this.data,
  });

  /// Create a patch from a 128-byte SYSEX voice data block
  /// The `sysexBytes` should be 128 bytes starting after the SYSEX header
  /// 
  /// For single voice format: name is at bytes 0-5
  /// For ROM dump format: name is at bytes 117-126
  factory Dx7Patch.fromVoiceData(Uint8List sysexBytes, {bool isRomFormat = false}) {
    if (sysexBytes.length != 128) {
      throw ArgumentError(
        'DX7 voice data must be exactly 128 bytes, got ${sysexBytes.length}',
      );
    }

    String encodedName;
    if (isRomFormat) {
      // ROM format: name is at bytes 117-126 (10 bytes)
      encodedName = String.fromCharCodes(sysexBytes.sublist(117, 127));
    } else {
      // Single voice format: name is at bytes 0-5 (6 bytes)
      encodedName = String.fromCharCodes(sysexBytes.sublist(0, 6));
    }
    final trimmedName = encodedName.replaceAll(RegExp(r'\s+$'), '');

    return Dx7Patch(
      name: trimmedName.isEmpty
          ? 'Voice ${sysexBytes[79].toRadixString(16).padLeft(2, '0')}'
          : trimmedName,
      data: sysexBytes,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Dx7Patch &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          const ListEquality<int>().equals(data, other.data);

  @override
  int get hashCode => Object.hash(name, const ListEquality<int>().hash(data));

  @override
  String toString() => 'Dx7Patch(name: $name, dataLength: ${data.length})';
}

/// DX7 voice dump SYSEX format: F0 43 00 20 00 00 00 44 02 <128 byte voice> F7
/// Total: 145 bytes including header (9) + voice (128) + footer (1)
class Dx7Bank {
  /// List of patches in the bank (128 positions, may have nulls for unused slots)
  final List<Dx7Patch?> patches;

  Dx7Bank(this.patches) {
    if (patches.length != 128) {
      throw ArgumentError(
        'Dx7Bank must contain exactly 128 patches (or null placeholders), got ${patches.length}',
      );
    }
  }

  /// Get a patch by index (0-127)
  Dx7Patch? getPatch(int index) {
    if (index < 0 || index >= 128) {
      throw RangeError('Patch index out of range: $index');
    }
    return patches[index];
  }

  /// Get all non-null patches with their indices
  List<MapEntry<int, Dx7Patch>> get validPatches {
    final result = <MapEntry<int, Dx7Patch>>[];
    for (int i = 0; i < patches.length; i++) {
      final patch = patches[i];
      if (patch != null) {
        result.add(MapEntry(i, patch));
      }
    }
    return result;
  }

  /// Create a bank from a SYSEX file containing one or more DX7 voices
  factory Dx7Bank.fromSysex(Uint8List sysexBytes) {
    final patches = <Dx7Patch?>[];

    if (sysexBytes.isEmpty) {
      print('Dx7Bank.fromSysex: Empty SYSEX data');
      return Dx7Bank(List.filled(128, null));
    }

    print('Dx7Bank.fromSysex: Parsing ${sysexBytes.length} bytes');
    print('Dx7Bank.fromSysex: First 20 bytes: ${sysexBytes.sublist(0, sysexBytes.length.clamp(0, 20)).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');

    // Try to detect the format
    int offset = 0;
    
    // First, try to find and parse SYSEX messages
    while (offset < sysexBytes.length && patches.length < 128) {
      // Look for SYSEX start (F0)
      if (sysexBytes[offset] != 0xF0) {
        offset++;
        continue;
      }

      // Found F0, check if this is a DX7 ROM dump
      if (_isValidDx7RomDump(sysexBytes, offset)) {
        print('Dx7Bank.fromSysex: Found ROM dump at offset $offset');
        final romData = _parseRomDump(sysexBytes, offset);
        patches.addAll(romData);
        // ROM dump is 4104 bytes total (7 header + 4096 data + 1 F7)
        offset += 4104;
        continue;
      }

      // Found F0, check if this is a single voice dump
      if (offset + 145 <= sysexBytes.length) {
        final isValidDx7 = _isValidDx7SingleVoice(sysexBytes, offset);
        if (isValidDx7) {
          print('Dx7Bank.fromSysex: Found single voice at offset $offset');
          final voiceBytes = sysexBytes.sublist(offset + 9, offset + 9 + 128);
          patches.add(Dx7Patch.fromVoiceData(voiceBytes));
          offset += 145;
          continue;
        }
      }

      // Check if this is a bank dump (128 voices concatenated)
      if (offset + 9 <= sysexBytes.length) {
        final bankEnd = _findDx7BankEnd(sysexBytes, offset);
        if (bankEnd > 0) {
          print('Dx7Bank.fromSysex: Found bank dump at offset $offset, end at $bankEnd');
          final bankData = _parseBankDump(sysexBytes, offset, bankEnd);
          patches.addAll(bankData);
          offset = bankEnd + 1; // Move past F7
          continue;
        }
      }

      // Not a valid SYSEX message, skip
      offset++;
    }

    print('Dx7Bank.fromSysex: Parsed ${patches.where((p) => p != null).length} patches');

    // Pad to 128 if needed
    while (patches.length < 128) {
      patches.add(null);
    }

    return Dx7Bank(patches);
  }

  /// Check if the SYSEX data at [offset] contains a valid DX7 single voice dump
  static bool _isValidDx7SingleVoice(Uint8List data, int offset) {
    if (offset + 145 > data.length) return false;

    // Check F0 header start
    if (data[offset] != 0xF0) return false;

    // Check manufacturer/model signature (offset+1 to offset+8)
    // Single voice: F0 43 0n 20 00 00 00 44 02
    final validSignature =
        data[offset + 1] == 0x43 && // Yamaha
        (data[offset + 2] & 0x70) == 0x00 && // Device ID (0-7)
        data[offset + 3] == 0x20 && // Data Set Code for voice
        data[offset + 4] == 0x00 && // Data Set Number MSB
        data[offset + 5] == 0x00 &&
        data[offset + 6] == 0x00 &&
        data[offset + 7] == 0x44 && // Model ID MSB (DX7)
        data[offset + 8] == 0x02; // Model ID LSB (DX7) - Single Voice

    if (!validSignature) return false;

    // Check F7 end marker at expected position
    final f7Pos = offset + 8 + 128 + 1; // offset + 137
    if (f7Pos >= data.length || data[f7Pos] != 0xF7) return false;

    return true;
  }

  /// Find the end of a DX7 bank dump (looking for F7)
  static int _findDx7BankEnd(Uint8List data, int offset) {
    if (offset + 9 > data.length) return -1;

    // Check if this looks like a bank dump header
    // Bank dump: F0 43 0n 20 00 00 00 44 00
    if (data[offset] != 0xF0) return -1;
    if (data[offset + 1] != 0x43) return -1; // Yamaha
    if ((data[offset + 2] & 0x70) != 0x00) return -1; // Device ID
    if (data[offset + 3] != 0x20) return -1; // Data Set Code
    if (data[offset + 4] != 0x00 || data[offset + 5] != 0x00 || data[offset + 6] != 0x00) return -1;
    if (data[offset + 7] != 0x44) return -1; // Model ID MSB (DX7)
    if (data[offset + 8] != 0x00) return -1; // Model ID LSB (DX7) - Bank

    // Find F7 marker
    for (int i = offset + 9; i < data.length; i++) {
      if (data[i] == 0xF7) {
        return i;
      }
    }

    return -1; // No F7 found
  }

  /// Parse a DX7 bank dump - currently logs info for debugging
  /// Note: Full bank dump conversion requires complex voice data expansion
  static List<Dx7Patch?> _parseBankDump(Uint8List data, int offset, int end) {
    final patches = <Dx7Patch?>[];
    
    // Bank data starts after header (9 bytes)
    int dataStart = offset + 9;
    int dataLength = end - dataStart;
    
    print('Dx7Bank.fromSysex: Bank dump detected');
    print('Dx7Bank.fromSysex: Bank data length: $dataLength bytes');
    print('Dx7Bank.fromSysex: This format requires voice expansion - returning empty for now');
    
    // For now, return empty patches for bank dumps
    // TODO: Implement proper bank-to-single voice conversion
    // DX7 bank format uses 32-byte packed voices vs 128-byte single voice format
    
    return patches;
  }

  /// Check if the SYSEX data at [offset] contains a valid DX7 ROM dump
  /// ROM dump format: F0 43 00 09 20 00 31 <4096 bytes ROM data> F7
  static bool _isValidDx7RomDump(Uint8List data, int offset) {
    // ROM dump is 4104 bytes: 7 header + 4096 data + 1 F7
    if (offset + 4104 > data.length) return false;

    // Check F0 header start
    if (data[offset] != 0xF0) return false;

    // Check ROM dump signature:
    // F0 43 00 09 20 00 31 (7 bytes)
    final validSignature =
        data[offset + 1] == 0x43 && // Yamaha
        data[offset + 2] == 0x00 && // Device ID
        data[offset + 3] == 0x09 && // ROM dump command
        data[offset + 4] == 0x20 && // ROM address/type
        data[offset + 5] == 0x00 &&
        data[offset + 6] == 0x31;   // ROM type identifier

    if (!validSignature) return false;

    // Check F7 end marker at expected position (offset + 7 + 4096 = offset + 4103)
    final f7Pos = offset + 4103;
    if (f7Pos >= data.length || data[f7Pos] != 0xF7) return false;

    return true;
  }

  /// Parse a DX7 ROM dump and extract patches
  /// ROM dumps contain 32 patches of 128 bytes each (4096 bytes total)
  static List<Dx7Patch?> _parseRomDump(Uint8List data, int offset) {
    final patches = <Dx7Patch?>[];
    
    // ROM data starts after 7-byte header
    final romDataStart = offset + 7;
    final romDataLength = 4096;
    
    print('Dx7Bank.fromSysex: ROM dump data length: $romDataLength bytes');
    
    // Extract ROM data
    final romData = data.sublist(romDataStart, romDataStart + romDataLength);
    
    // DX7 internal ROM contains 32 patches, each 128 bytes
    const int patchesInRom = 32;
    const int patchSize = 128;
    
    print('Dx7Bank.fromSysex: Extracting $patchesInRom patches from ROM data');
    
    for (int i = 0; i < patchesInRom && patches.length < 128; i++) {
      final patchStart = i * patchSize;
      final patchBytes = romData.sublist(patchStart, patchStart + patchSize);
      
      try {
        // ROM format uses different name location (bytes 117-126)
        final patch = Dx7Patch.fromVoiceData(patchBytes, isRomFormat: true);
        patches.add(patch);
        print('Dx7Bank.fromSysex: Patch $i: "${patch.name}"');
      } catch (e) {
        print('Dx7Bank.fromSysex: Error parsing patch $i: $e');
        patches.add(null);
      }
    }
    
    return patches;
  }

  /// Convert bank to a string representation for debugging
  @override
  String toString() {
    final loaded = patches.where((p) => p != null).length;
    return 'Dx7Bank(patches: $loaded/128 loaded)';
  }
}

/// Assignment of a patch to a specific MIDI channel
class ChannelAssignment {
  /// MIDI channel (0-15, where 0 = MIDI channel 1)
  final int channel;
  /// Patch index in the loaded bank (0-127) or -1 if no patch assigned
  final int patchIndex;

  ChannelAssignment(this.channel, this.patchIndex) {
    if (channel < 0 || channel > 15) {
      throw ArgumentError('Channel must be 0-15, got $channel');
    }
    if (patchIndex < -1 || patchIndex > 127) {
      throw ArgumentError('Patch index must be -1 to 127, got $patchIndex');
    }
  }

  /// Whether this channel has a valid patch assigned
  bool get isAssigned => patchIndex != -1 && patchIndex < 128;

  /// Get the 1-indexed MIDI channel number (1-16)
  int get midiChannel => channel + 1;

  /// Create a default unassigned assignment for a channel
  factory ChannelAssignment.unassigned(int channel) {
    return ChannelAssignment(channel, -1);
  }

  /// Copy with a new patch index
  ChannelAssignment copyWithPatchIndex(int patchIndex) {
    return ChannelAssignment(channel, patchIndex);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChannelAssignment &&
          runtimeType == other.runtimeType &&
          channel == other.channel &&
          patchIndex == other.patchIndex;

  @override
  int get hashCode => Object.hash(channel, patchIndex);

  @override
  String toString() => 'ChannelAssignment(channel: $midiChannel, patch: $patchIndex)';
}
