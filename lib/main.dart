import 'package:bonsai/bonsai.dart';
import 'package:droid_synth_2/midi_device_handler.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';

import 'package:flutter_virtual_piano/flutter_virtual_piano.dart';
import 'package:msfa_plugin/msfa_plugin.dart';

void main() {
  if (kDebugMode) {
    Log.init();
  }
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  MyAppState createState() => MyAppState();
}

class MyAppState extends State<MyApp> {
  late MSFAPlugin plugin;
  late final Future midiInitCompleted;
  final MidiCommand midiCommand = MidiCommand();
  late final midi = DeviceHandler(midiCommand);

  @override
  void initState() {
    super.initState();
    plugin = MSFAPlugin();
    log("MIDI init...");
    midiInitCompleted = midi.connectDevice();
  }

  @override
  void reassemble() {
    super.reassemble();
    log("reassembling state...");
    plugin.shutDown();
    plugin = MSFAPlugin();
    midi.disconnect();
  }

  @override
  void dispose() {
    super.dispose();
  }

  void sendNoteOn(int noteNumber, int velocity) {
    log("send note on: $noteNumber");
    // Midi messages: [Status, NoteNumber, Velocity]
    // where status is 0x90-0x9F and the low nibble is the channel number 0-15
    // ref: http://midi.teragonaudio.com/tech/midispec/noteon.htm
    plugin.sendMidi([0x90, noteNumber, velocity]);
  }

  void sendNoteOff(int noteNumber) {
    log("send note off: $noteNumber");
    plugin.sendMidi([0x80, noteNumber, 0x00]);
  }

  @override
  Widget build(BuildContext context) {
    const textStyle = TextStyle(fontSize: 14);
    const spacerSmall = SizedBox(height: 10);
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Droid Synth'),
        ),
        body: FutureBuilder<void>(
            future: midiInitCompleted,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const CircularProgressIndicator();
              } else if (snapshot.hasError) {
                return Text("Midi error: ${snapshot.error}");
              }
              return SingleChildScrollView(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    children: [
                      spacerSmall,
                      SizedBox(
                        height: 120,
                        child: VirtualPiano(
                          noteRange: const RangeValues(52, 71),
                          onNotePressed: (note, pos) {
                            sendNoteOn(note, 0x57);
                          },
                          onNoteReleased: (note) {
                            sendNoteOff(note);
                          },
                        ),
                      ),
                      spacerSmall,
                      Container(
                        color: Colors.blueAccent[100],
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            FutureBuilder<bool>(
                              future: plugin.init(),
                              builder: (BuildContext context, AsyncSnapshot<bool> value) {
                                final displayValue =
                                    (value.hasData) ? (value.data == true ? "completed" : "failed") : 'loading...';
                                return Text(
                                  'MSFA Engine Init: $displayValue',
                                  style: textStyle,
                                  textAlign: TextAlign.center,
                                );
                              },
                            ),
                            const SizedBox(width: 16),
                            MaterialButton(
                              color: Colors.amberAccent,
                              child: const Text("shutdown"),
                              onPressed: () async {
                                log("shutdown engine");
                                plugin.shutDown();
                              },
                            ),
                          ],
                        ),
                      )
                    ],
                  ),
                ),
              );
            }),
      ),
    );
  }
}
