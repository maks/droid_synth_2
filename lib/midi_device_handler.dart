import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:bonsai/bonsai.dart';
import 'package:collection/collection.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:ninja_hex/ninja_hex.dart';

class DeviceHandler {
  final MidiCommand _midi;
  MidiDevice? _device;

  StreamSubscription<MidiPacket>? _rxSubscription;
  final _inputStreamController = StreamController<MidiInputEvent>();
  final _messagesStreamController = StreamController<String>();

  late Stream<MidiInputEvent> midiEvents = _inputStreamController.stream.asBroadcastStream();

  late Stream<String> messages = _messagesStreamController.stream.asBroadcastStream();

  DeviceHandler(this._midi);

  Future<void> connectDevice() async {

    log("Fetching Midi device list");
    final devices = await _midi.devices;
    log("DEVICES:${devices?.length}");
    devices?.forEach((element) {
      log("midi device:${element.name}");
    });
    MidiDevice? device;
    device = devices?.firstWhereOrNull((dev) => dev.name.toLowerCase().contains('circuit tracks'));
    // device = devices?.firstWhereOrNull((dev) => dev.name.toLowerCase().contains('studio fire'));
    
    if (device != null) {
      await _midi.connectToDevice(device);
      _rxSubscription ??= _midi.onMidiDataReceived?.listen(_handleMidiInput);
      _device = device;
      log('connected device:${_device?.name}');
      _messagesStreamController.add('Midi device Connected');
    } else {
      log('no Midi device to connect to');
      _messagesStreamController.add('no Midi device to connect to: ');
    }
  }

  void disconnect() {
    if (_device != null) {
      _midi.disconnectDevice(_device!);
      log('disconnected device:${_device?.name}');
      _messagesStreamController.add('Midi Disconnected');
    } else {
      log('no device to disconnect');
      _messagesStreamController.add('no device to disconnect');
    }
  }

  void close() {
    _rxSubscription?.cancel();
  }

  void _handleMidiInput(MidiPacket packet) {
    if (packet.data.length == 1 && packet.data[0] == 0xF8) {
      // skip clock mesgs
    } else {
      // don't debug log Midi clock mesgs
      if (packet.data[0] != 0xF8) {
        log('received Std Midi packet: ${hexView(0, packet.data)}');
        if (isProgramChange(packet.data)) {
          log('program change: $packet');
        } else {
          _inputStreamController.add(MidiInputEvent(packet.data));
        }
      }
    }
  }
}

bool isSysex(Uint8List data) => data.isNotEmpty && data[0] == 0xF0;

bool isBankSelect(Uint8List data) => data.isNotEmpty && data[0] == 0xB0;

bool isProgramChange(Uint8List data) => data.isNotEmpty && data[0] == 0xC0;

class MidiInputEvent {
  final Uint8List data;

  MidiInputEvent(this.data);
}

/// thank you @Sunbreak!
/// https://github.com/timsneath/win32/issues/142#issuecomment-829846260
extension CharArray on ffi.Array<ffi.Uint8> {
  String getDartString(int maxLength) {
    var list = <int>[];
    for (var i = 0; i < maxLength; i++) {
      if (this[i] != 0) list.add(this[i]);
    }
    return utf8.decode(list);
  }

  void setDartString(String s, int maxLength) {
    var list = utf8.encode(s);
    for (var i = 0; i < maxLength; i++) {
      this[i] = i < list.length ? list[i] : 0;
    }
  }
}
