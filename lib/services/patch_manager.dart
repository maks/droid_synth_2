import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/dx7_bank.dart';
import 'dx7_bank_loader.dart';

/// Service class that manages the loaded DX7 bank and channel assignments
/// Notifies listeners when the bank or assignments change
class PatchManager extends ChangeNotifier {
  /// Callback for when a channel assignment changes
  /// Called after assignPatch() with the channel and new patch index
  void Function(int channel, int patchIndex)? onAssignmentChanged;
  final Dx7BankLoader _loader = Dx7BankLoader();

  /// Currently loaded bank
  Dx7Bank? _bank;

  /// Channel assignments for all 16 MIDI channels (0-15)
  final List<ChannelAssignment> _assignments = [];

  /// Path/identifier of the loaded bank file (for persistence)
  String? _bankIdentifier;

  /// Constructor
  PatchManager() {
    // Initialize default unassigned channels
    for (int i = 0; i < 16; i++) {
      _assignments.add(ChannelAssignment.unassigned(i));
    }
  }

  /// Currently loaded bank
  Dx7Bank? get bank => _bank;

  /// Bank identifier (file path or name)
  String? get bankIdentifier => _bankIdentifier;

  /// Channel assignments (copy to prevent external modification)
  List<ChannelAssignment> get assignments => List.unmodifiable(_assignments);

  /// Whether a bank is currently loaded
  bool get isBankLoaded => _bank != null;

  /// Get patch index assigned to a specific MIDI channel
  int getPatchIndexForChannel(int channel) {
    if (channel < 0 || channel > 15) {
      throw RangeError('Channel must be 0-15, got $channel');
    }
    return _assignments[channel].patchIndex;
  }

  /// Get patch data for a specific MIDI channel (if assigned)
  Uint8List? getPatchDataForChannel(int channel) {
    final patchIndex = getPatchIndexForChannel(channel);
    if (patchIndex == -1 || _bank == null) return null;
    return _bank!.getPatch(patchIndex)?.data;
  }

  /// Set the bank identifier (e.g., file path)
  void setBankIdentifier(String identifier) {
    _bankIdentifier = identifier;
    notifyListeners();
  }

  /// Load a DX7 SYSEX bank from raw bytes
  Future<bool> loadBank(Uint8List bytes, {String? identifier}) async {
    try {
      print('PatchManager.loadBank: Received ${bytes.length} bytes');
      print('PatchManager.loadBank: First 20 bytes: ${bytes.sublist(0, bytes.length.clamp(0, 20)).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
      
      // Parse the bank
      final bank = Dx7Bank.fromSysex(bytes);

      print('PatchManager.loadBank: Parsed bank has ${bank.patches.where((p) => p != null).length} non-null patches');
      print('PatchManager.loadBank: Valid patches: ${bank.validPatches.length}');
      
      if (bank.validPatches.isEmpty) {
        print('Warning: Loaded bank has no valid patches');
        print('PatchManager.loadBank: This could mean:');
        print('  1. The file is in DX7 bank dump format (not single voice format)');
        print('  2. The SYSEX header is different than expected');
        print('  3. The file is corrupted or not a DX7 file');
        return false;
      }

      // Swap to a new bank without notifying changes
      _swapBank(bank, identifier: identifier);
      notifyListeners();

      print('Loaded bank with ${bank.validPatches.length} patches');
      if (bank.validPatches.length <= 5) {
        for (var patch in bank.validPatches) {
          print('  Patch ${patch.key}: ${patch.value.name}');
        }
      }
      return true;
    } catch (e, stackTrace) {
      print('Error loading bank: $e');
      print('Stack trace: $stackTrace');
      return false;
    }
  }

  /// Load a bank from a base64 encoded string
  Future<bool> loadBankFromBase64(String base64String, {String? identifier}) async {
    final bytes = base64Decode(base64String);
    return loadBank(Uint8List.fromList(bytes), identifier: identifier);
  }

  /// Swap to a new bank
  void _swapBank(Dx7Bank bank, {String? identifier}) {
    _bank = bank;
    if (identifier != null) {
      _bankIdentifier = identifier;
    }
  }

  /// Clear the current bank
  void clearBank() {
    _bank = null;
    _bankIdentifier = null;
    notifyListeners();
  }

  /// Assign a patch to a specific MIDI channel
  void assignPatch(int channel, int patchIndex) {
    if (channel < 0 || channel > 15) {
      throw RangeError('Channel must be 0-15, got $channel');
    }
    if (patchIndex < -1 || patchIndex > 127) {
      throw RangeError('Patch index must be 0-127 or -1, got $patchIndex');
    }

    _assignments[channel] = _assignments[channel].copyWithPatchIndex(patchIndex);
    notifyListeners();
    
    // Notify assignment change callback if set
    onAssignmentChanged?.call(channel, patchIndex);
  }

  /// Assign a patch to a range of channels (useful for grouping)
  void assignPatchToChannels(int startChannel, int endChannel, int patchIndex) {
    for (int i = startChannel; i <= endChannel; i++) {
      assignPatch(i, patchIndex);
    }
  }

  /// Set all channels to a specific patch
  void setAllChannelsToPatch(int patchIndex) {
    for (int i = 0; i < 16; i++) {
      assignPatch(i, patchIndex);
    }
  }

  /// Set a channel to unassigned (no patch, muted)
  void unassignPatch(int channel) {
    assignPatch(channel, -1);
  }

  /// Get assignment for a specific channel
  ChannelAssignment getAssignment(int channel) {
    if (channel < 0 || channel > 15) {
      throw RangeError('Channel must be 0-15, got $channel');
    }
    return _assignments[channel];
  }

  /// Check if all channels are unassigned
  bool get allChannelsUnassigned => _assignments.every((a) => !a.isAssigned);

  /// Get channel assignments for debugging
  Map<int, int> getAllAssignments() {
    final map = <int, int>{};
    for (int i = 0; i < 16; i++) {
      map[i] = _assignments[i].patchIndex;
    }
    return map;
  }

  /// Load a bank from an identifier (used with bank loader service)
  Future<bool> loadBankFromLoader(Dx7BankLoader loader, int bankIndex) async {
    final loadedBank = bankIndex >= 0 && bankIndex < loader.loadedBanks.length
        ? loader.loadedBanks[bankIndex]
        : null;

    if (loadedBank != null) {
      _swapBank(loadedBank);
      notifyListeners();
      return true;
    }

    return false;
  }

  /// Override to allow direct swap (for testing/migration)
  void swapToBank(Dx7Bank bank) {
    _bank = bank;
    notifyListeners();
  }

  /// Load an existing bank (if already loaded by loader)
  Future<bool> loadExistingBank(int bankIndex) async {
    final loadedBank = bankIndex >= 0 && bankIndex < _loader.loadedBanks.length
        ? _loader.loadedBanks[bankIndex]
        : null;

    if (loadedBank != null) {
      _swapBank(loadedBank);
      notifyListeners();
      return true;
    }

    return false;
  }
}
