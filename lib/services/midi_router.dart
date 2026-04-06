import 'dart:async';
import 'dart:typed_data';
import 'package:collection/collection.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import '../midi_device_handler.dart';
import '../services/patch_manager.dart';

/// Router for MIDI events that routes to the correct patches based on channel assignments
/// Extends the functionality of DeviceHandler
class MidiRouter {
  final MidiCommand _midi;
  final PatchManager _patchManager;
  MidiDevice? _device;
  StreamSubscription<MidiPacket>? _rxSubscription;

  final _inputStreamController = StreamController<MidiInputEvent>();
  final _messagesStreamController = StreamController<String>();

  late Stream<MidiInputEvent> midiEvents = _inputStreamController.stream.asBroadcastStream();

  late Stream<String> messages = _messagesStreamController.stream.asBroadcastStream();

  /// Track active notes per channel for Note Off handling
  final Map<int, Set<int>> _activeNotes = {};

  /// Track current program per channel to avoid duplicate Program Change messages
  final Map<int, int> _currentPrograms = {};

  /// Callback for sending raw MIDI bytes (typically to the synthesis engine)
  final void Function(Uint8List bytes)? onSendRawMidi;

  /// Callback for sending program changes to the synthesis engine
  final void Function(int channel, int program)? onSendProgramChange;

  MidiRouter({
    required MidiCommand midi,
    required PatchManager patchManager,
    this.onSendProgramChange,
    this.onSendRawMidi,
  }) : _midi = midi,
       _patchManager = patchManager {
    // Listen for assignment changes to send program changes immediately
    _patchManager.onAssignmentChanged = _handleAssignmentChanged;
  }

  /// Helper logging function
  void _log(String message) {
    print('[MidiRouter] $message');
  }

  /// Handle patch assignment changes from the UI
  void _handleAssignmentChanged(int channel, int patchIndex) {
    _log('Assignment changed: channel=$channel, patch=$patchIndex');
    
    // Send program change immediately to update the sound
    if (patchIndex != -1 && _patchManager.isBankLoaded) {
      _ensurePatchLoaded(channel, patchIndex);
    }
  }

  /// Connect to the MIDI device
  Future<void> connectDevice() async {
    try {
      final devices = await _midi.devices;
      _log('MIDI devices found: ${devices?.length}');
      for (var dev in devices ?? []) {
        _log('Device: ${dev.name}');
      }

      // Find LaunchKey device, or use first available
      MidiDevice? device;
      if (devices != null) {
        device = devices.firstWhereOrNull((dev) =>
            dev.name.toLowerCase().contains('launchkey') ||
            dev.name.toLowerCase().contains('midi'));
      }

      if (device != null) {
        await _midi.connectToDevice(device);
        _rxSubscription ??=
            _midi.onMidiDataReceived?.listen(_handleMidiInput);
        _device = device;
        _log('Connected to device: ${_device?.name}');
        _messagesStreamController.add('MIDI device connected: ${_device?.name}');
      } else {
        _log('No MIDI device found');
        _messagesStreamController.add('No MIDI device found');
      }
    } catch (e) {
      _log('Error connecting to MIDI device: $e');
      _messagesStreamController.add('Error: $e');
    }
  }

  /// Disconnect from the MIDI device
  void disconnect() {
    if (_device != null) {
      _midi.disconnectDevice(_device!);
      _log('Disconnected from device: ${_device?.name}');
      _messagesStreamController.add('MIDI device disconnected');
      _device = null;
    }
  }

  /// Clear subscriptions
  void close() {
    _rxSubscription?.cancel();
    _rxSubscription = null;
  }

  /// Send raw MIDI bytes (for testing or direct control)
  void sendMidi(Uint8List bytes) {
    onSendRawMidi?.call(bytes);
  }

  /// Send program change to the synthesis engine
  /// For DX7: sends bank select (MSB=0, LSB=0) then program change
  void _sendProgramChange(int channel, int program) {
    if (program == -1) {
      _log('Skipping program change: channel=$channel, program=-1 (unassigned)');
      return;
    }

    // For DX7 compatibility, send bank select MSB and LSB first (both 0 for single bank)
    // Bank Select MSB: 0xB0 | channel, 0x00, 0x00
    final bankSelectMsb = Uint8List.fromList([0xB0 | channel, 0x00, 0x00]);
    // Bank Select LSB: 0xB0 | channel, 0x20, 0x00
    final bankSelectLsb = Uint8List.fromList([0xB0 | channel, 0x20, 0x00]);
    // Program Change: 0xC0 | channel, program
    final programChange = Uint8List.fromList([0xC0 | channel, program]);

    // Send bank select MSB
    onSendRawMidi?.call(bankSelectMsb);
    _log('Bank Select MSB: channel=$channel, value=0');

    // Send bank select LSB
    onSendRawMidi?.call(bankSelectLsb);
    _log('Bank Select LSB: channel=$channel, value=0');

    // Send program change via the callback (for plugin integration)
    onSendProgramChange?.call(channel, program);
    _currentPrograms[channel] = program;

    _log('Program Change: channel=$channel, program=$program');
    onSendRawMidi?.call(programChange);
  }

  /// Ensure the correct patch is loaded for a channel
  /// Sends program change if the current patch differs from the assigned patch
  void _ensurePatchLoaded(int channel, int patchIndex) {
    if (patchIndex == -1) {
      _log('Channel $channel: no patch assigned, skipping');
      return; // No patch assigned
    }

    if (_patchManager.bank == null) {
      _log('Channel $channel: no bank loaded, cannot ensure patch');
      return;
    }

    final currentProgram = _currentPrograms[channel];
    if (currentProgram == patchIndex) {
      _log('Channel $channel: patch $patchIndex already loaded');
      return; // Already loaded, no need to resend
    }

    _log('Channel $channel: ensuring patch $patchIndex (current: $currentProgram)');
    _sendProgramChange(channel, patchIndex);
  }

  /// Route an incoming MIDI note event to the correct patch
  void _routeNoteEvent(MidiPacket packet) {
    if (packet.data.length != 3) {
      _log('Skipping invalid note message: ${packet.data}');
      return;
    }

    final status = packet.data[0];
    final note = packet.data[1];
    final velocity = packet.data[2];

    // Determine MIDI channel (low nibble of status byte)
    final int channel = status & 0x0F;

    // Determine if it's a note-on or note-off
    final isNoteOn = (status & 0xF0) == 0x90;
    final isNoteOff = (status & 0xF0) == 0x80;

    if (!isNoteOn && !isNoteOff) {
      _log('Skipping non-note message: $packet');
      return;
    }

    // If velocity is 0, treat as note-off
    if (isNoteOn && velocity == 0) {
      _routeNoteOff(channel, note);
      return;
    }

    if (isNoteOn) {
      _handleNoteOn(channel, note, velocity);
    } else if (isNoteOff) {
      _handleNoteOff(channel, note);
    }
  }

  /// Handle a note-on event
  void _handleNoteOn(int channel, int note, int velocity) {
    // Get patch assignment for this channel
    final assignment = _patchManager.getAssignment(channel);
    final patchIndex = assignment.patchIndex;

    // If no patch assigned and bank is loaded, don't play
    if (patchIndex == -1 && _patchManager.isBankLoaded) {
      _log('Channel $channel: no patch assigned, note muted');
      return;
    }

    // Ensure the correct patch is loaded before playing
    _ensurePatchLoaded(channel, patchIndex);

    // Track active note
    _activeNotes.putIfAbsent(channel, () => {}).add(note);

    // Route the note-on event (original velocity)
    final message = [0x90 | channel, note, velocity];
    onSendRawMidi?.call(Uint8List.fromList(message));
    _log('Note On: channel=$channel, note=$note, velocity=$velocity');
  }

  /// Handle a note-off event
  void _handleNoteOff(int channel, int note) {
    // Track active note
    _activeNotes[channel]?.remove(note);

    // Route the note-off event
    final message = [0x80 | channel, note, 0x00];
    onSendRawMidi?.call(Uint8List.fromList(message));
  }

  /// Handle a non-note-off note-on (velocity 0)
  void _routeNoteOff(int channel, int note) {
    _handleNoteOff(channel, note);
  }

  /// Handle incoming MIDI data
  void _handleMidiInput(MidiPacket packet) {
    // Filter out MIDI timing clock messages (0xF8)
    if (packet.data.isNotEmpty && packet.data[0] == 0xF8) {
      return; // Skip clock messages
    }

    // Check for SYSEX messages (we'll forward them as-is if the plugin supports it)
    if (packet.data.isNotEmpty && packet.data[0] == 0xF0) {
      _log('Received SYSEX message: ${packet.data}');
      // Optionally forward SYSEX to the synthesis engine
      // onSendRawMidi?.call(packet.data);
      return;
    }

    // Handle different types of MIDI messages
    final statusByte = packet.data[0];
    final message = packet.data;

    // Check message type by status byte high nibble
    final messageType = statusByte & 0xF0;

    switch (messageType) {
      case 0x80: // Note Off
      case 0x90: // Note On
        _routeNoteEvent(packet);
        break;

      case 0xB0: // Control Change / Bank Select
        _handleControlChange(packet);
        break;

      case 0xC0: // Program Change
        // Update internal tracking and forward to synthesis
        final pcChannel = statusByte & 0x0F;
        final pcProgram = message[1];
        _currentPrograms[pcChannel] = pcProgram;
        _log('Program Change received: channel=$pcChannel, program=$pcProgram');
        onSendRawMidi?.call(packet.data);
        break;

      case 0xA0: // Key Aftertouch
      case 0xD0: // Channel Aftertouch
      case 0xE0: // Pitch Bend
        // Forward other messages
        onSendRawMidi?.call(packet.data);
        break;

      default:
        _log('Unhandled MIDI message type: ${packet.data}');
        break;
    }
  }

  /// Handle Control Change messages (including Bank Select)
  void _handleControlChange(MidiPacket packet) {
    if (packet.data.length < 2) {
      _log('Invalid CC message: ${packet.data}');
      return;
    }

    final ccNumber = packet.data[1];
    final value = packet.data[2];
    final channel = packet.data[0] & 0x0F;

    // Bank Select messages
    if (ccNumber == 0x00) {
      // Bank Select MSB (Main Bank number 0-127)
      _log('Bank Select MSB: channel=$channel, value=$value');

      // For DX7 compatibility, we need to track this for program changes
      // But for simplicity, we'll handle Bank Select MSB=0 separately
      // when program changes arrive
    } else if (ccNumber == 0x20) {
      // Bank Select LSB (Sub-bank number 0-127)
      _log('Bank Select LSB: channel=$channel, value=$value');
      // Same as MSB for single-bank synth behavior
    } else {
      // Other CC messages - forward them
      onSendRawMidi?.call(packet.data);
    }
  }

  /// Get the PatchManager
  PatchManager get patchManager => _patchManager;

  /// Check if bank is loaded
  bool get patchManagerIsBankLoaded => _patchManager.isBankLoaded;

  /// Add listener to internal streams
  void listenToEvents(
    void Function(MidiInputEvent event)? onMidiEvent,
    void Function(String message)? onMessage,
  ) {
    midiEvents.listen((event) => onMidiEvent?.call(event));
    messages.listen((message) => onMessage?.call(message));
  }

  /// Debug: Log current state
  void debugState() {
    _log('=== MIDI Router State ===');
    _log('Bank loaded: $_patchManager.isBankLoaded');
    if (_patchManager.isBankLoaded) {
      _log('Bank has ${_patchManager.bank!.validPatches.length} patches');
    }
    _log('Active channels:');
    for (int i = 0; i < 16; i++) {
      final assignment = _patchManager.getAssignment(i);
      _log('  Channel ${assignment.midiChannel}: patch=${assignment.patchIndex} ($assignment)');
    }
    _log('Active notes: $_activeNotes');
    _log('========================');
  }
}

/// Helper class to manage multiple subscriptions
class StreamSubscriptionList {
  final List<StreamSubscription> _subs;

  StreamSubscriptionList(this._subs);

  Future<void> cancel() async {
    for (var sub in _subs) {
      await sub.cancel();
    }
  }
}
