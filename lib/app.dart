import 'package:bonsai/bonsai.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:flutter_virtual_piano/flutter_virtual_piano.dart';
import 'package:file_picker/file_picker.dart';
import 'package:msfa_plugin/msfa_plugin.dart';

import 'models/dx7_bank.dart';
import 'services/midi_router.dart';
import 'services/patch_manager.dart';

class App extends StatefulWidget {
  const App({Key? key}) : super(key: key);

  @override
  AppState createState() => AppState();
}

class AppState extends State<App> {
  late MSFAPlugin plugin;
  late final Future midiInitCompleted;
  late final MidiCommand midiCommand;
  late final MidiRouter midiRouter;
  late final PatchManager patchManager;

  @override
  void initState() {
    super.initState();

    midiCommand = MidiCommand();
    plugin = MSFAPlugin();
    patchManager = PatchManager();
    midiRouter = MidiRouter(
      midi: midiCommand,
      patchManager: patchManager,
      onSendRawMidi: _sendRawMidiToPlugin,
    );

    log('MIDI init');
    midiInitCompleted = midiRouter.connectDevice();

    // Listen to MIDI input events
    midiRouter.midiEvents.listen((event) {
      log('midi event: ${event.data}');
      // Note events are already routed by MidiRouter
    });

    // Listen to status messages
    midiRouter.messages.listen((message) {
      log(message);
    });
  }

  void _sendRawMidiToPlugin(Uint8List bytes) {
    log('Plugin sendMidi: $bytes');
    plugin.sendMidi(bytes);
  }

  @override
  void reassemble() {
    super.reassemble();
    log('reassembling state...');
    plugin.shutDown();
    plugin = MSFAPlugin();
    midiRouter.disconnect();
  }

  @override
  void dispose() {
    patchManager.dispose();
    midiRouter.close();
    midiCommand.dispose();
    plugin.shutDown();
    super.dispose();
  }

  void sendNoteOn(int noteNumber, int velocity, [int channel = 0]) {
    final statusByte = 0x90 | channel; // Note On status for channel
    // Note On MIDI format: [Status, Note number, Velocity] on a single channel
    final bytes = Uint8List.fromList([statusByte, noteNumber, velocity.clamp(0, 127)]);
    plugin.sendMidi(bytes);
  }

  void sendProgramChange(int channel, int program) {
    final statusByte = 0xC0 | channel; // Program Change format: C0 + channel number
    final bytes = Uint8List.fromList([statusByte, program]);
    plugin.sendMidi(bytes);
  }

  /// Build a DX7 single voice SYSEX message from 128 bytes of voice data
  /// DX7 single voice format:
  ///   F0 43 00 20 00 00 00 44 02 <128 byte voice> F7
  /// Total: 145 bytes
  Uint8List _buildDx7Sysex(Uint8List voiceData) {
    if (voiceData.length != 128) {
      throw ArgumentError(
          'DX7 voice data must be exactly 128 bytes, got ${voiceData.length}',
      );
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

  /// Send a DX7 voice SYSEX to load it into the msfa_plugin
  void sendDx7Voice(Uint8List voiceData) {
    final sysex = _buildDx7Sysex(voiceData);
    log('Sending DX7 SYSEX to plugin: ${sysex.length} bytes');
    plugin.sendMidi(sysex);
  }

  @override
  Widget build(BuildContext context) {
    const textStyle = TextStyle(fontSize: 14);
    const spacerSmall = SizedBox(height: 10);
    const spacerMedium = SizedBox(height: 20);

    return Scaffold(
        appBar: AppBar(
          title: const Text('Droid Synth'),
          actions: [
            IconButton(
              icon: const Icon(Icons.storage),
              tooltip: 'Load DX7 Bank',
              onPressed: _showBankLoaderDialog,
            ),
            IconButton(
              icon: const Icon(Icons.list),
              tooltip: 'Channel Assignments',
              onPressed: _showChannelAssignments,
            ),
          ],
        ),
        body: FutureBuilder<void>(
          future: midiInitCompleted,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            } else if (snapshot.hasError) {
              return Center(child: Text("MIDI error: ${snapshot.error}"));
            }

            return SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Multitimbral DX7 Synth',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    spacerMedium,
                    // Bank status
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.storage, color: Colors.blue),
                          const Spacer(),
                          Text(
                            patchManager.isBankLoaded
                                ? '${patchManager.bank?.validPatches.length ?? 0} patches loaded'
                                : 'No bank loaded',
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.refresh),
                            tooltip: 'Load New Bank',
                            onPressed: _showBankLoaderDialog,
                          ),
                        ],
                      ),
                    ),
                    spacerMedium,
                    // Channel assignment summary
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green[50],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Channel Assignments Summary',
                            style: TextStyle(fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 16,
                            runSpacing: 8,
                            children: List.generate(16, (index) {
                              final assignment = patchManager.getAssignment(index);
                              final patchInfo = assignment.isAssigned
                                  ? patchManager.bank?.getPatch(assignment.patchIndex)?.name ?? 'Unknown'
                                  : 'Unassigned';
                              return _buildChannelChip(
                                assignment.midiChannel,
                                patchInfo,
                                assignment.isAssigned,
                              );
                            }),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Tap a channel to change its patch',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    spacerMedium,
                    // Virtual piano (always uses channel 0 - MIDI chan 1)
                    Text(
                      'Virtual Piano (Channel 1)',
                      style: textStyle.copyWith(fontWeight: FontWeight.bold),
                    ),
                    spacerSmall,
                    Container(
                      height: 120,
                      decoration: BoxDecoration(
                        color: Colors.orange[50],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: VirtualPiano(
                        noteRange: const RangeValues(52, 71),
                        onNotePressed: (note, pos) {
                          _onNoteDown(note);
                        },
                        onNoteReleased: (note) {
                          _onNoteUp(note);
                        },
                      ),
                    ),
                    spacerMedium,
                    // Plugin status
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.blueAccent[100],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          FutureBuilder<bool>(
                            future: plugin.init(),
                            builder: (
                              BuildContext context,
                              AsyncSnapshot<bool> value,
                            ) {
                              final displayValue = value.hasData
                                  ? (value.data == true
                                      ? 'active'
                                      : 'failed')
                                  : 'initializing...';
                              return Text(
                                'MSFA Engine: $displayValue',
                                style: textStyle,
                                textAlign: TextAlign.center,
                              );
                            },
                          ),
                          const SizedBox(width: 16),
                          MaterialButton(
                            color: Colors.amberAccent,
                            onPressed: () {
                              log('shutdown engine');
                              plugin.shutDown();
                            },
                            child: const Text('shutdown'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
  }

  Widget _buildChannelChip(int channel, String patchName, bool isAssigned) {
    final color = isAssigned
        ? Colors.green[700]!
        : Colors.grey[400]!;
    final label = patchName.isNotEmpty ? patchName : 'CH $channel';
    return GestureDetector(
      onTap: () => _showChannelAssignments(channel: channel),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color),
        ),
        child: Text(
          label,
          style: TextStyle(color: color, fontSize: 12),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  void _showBankLoaderDialog() {
    showDialog(
      context: context,
      builder: (context) => BankLoaderDialog(patchManager: patchManager),
    );
  }

  void _showChannelAssignments({int? channel}) {
    showDialog(
      context: context,
      builder: (context) => ChannelAssignmentsDialog(
        patchManager: patchManager,
        startChannel: channel,
        onClose: () {
          // No need to notify listeners; dialog handles its own state
        },
      ),
    );
  }

  void _onNoteDown(int note) {
    // Virtual piano always sends on channel 0 (MIDI channel 1) for testing
    // The piano widget returns velocity, but we use a fixed value
    final bytes = Uint8List.fromList([0x90, note, 0x57]); // 0x90 = Note On on channel 0
    plugin.sendMidi(bytes);
  }

  void _onNoteUp(int note) {
    final bytes = Uint8List.fromList([0x90, note, 0x00]); // Note Off
    plugin.sendMidi(bytes);
  }
}

/// Dialog for loading a DX7 bank
class BankLoaderDialog extends StatefulWidget {
  final PatchManager patchManager;

  const BankLoaderDialog({Key? key, required this.patchManager}) : super(key: key);

  @override
  State<BankLoaderDialog> createState() => _BankLoaderDialogState();
}

class _BankLoaderDialogState extends State<BankLoaderDialog> {
  bool _isLoading = false;

  Future<void> _pickAndLoadBank() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['sysex', 'syx'],
      withData: true,
    );

    if (result == null) {
      // User canceled
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final bytes = result.files.single.bytes;
      if (bytes == null) {
        throw Exception('No file data');
      }
      final success = await widget.patchManager.loadBank(bytes,
          identifier: result.files.single.name);
      if (success) {
        // Optionally store identifier in shared preferences
        // For now just close dialog
        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Bank loaded successfully')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to load bank')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading bank: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Load DX7 Bank'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Select a DX7 SYSEX bank file to load.'),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _pickAndLoadBank,
            icon: const Icon(Icons.folder_open),
            label: const Text('Choose File'),
          ),
          const SizedBox(height: 16),
          if (widget.patchManager.bank != null)
            Container(
              padding: const EdgeInsets.all(12),
              color: Colors.blue[50],
              child: Column(
                children: [
                  Text(
                    'Current Bank',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Loaded: ${widget.patchManager.bank!.validPatches.length} patches',
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: () {
                      widget.patchManager.clearBank();
                      Navigator.pop(context);
                    },
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.red),
                    ),
                    child: const Text('Clear Bank'),
                  ),
                ],
              ),
            ),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(width: 16),
                  Text('Loading...'),
                ],
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(context);
          },
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

/// Dialog for channel assignments
class ChannelAssignmentsDialog extends StatefulWidget {
  final PatchManager patchManager;
  final int? startChannel;
  final VoidCallback onClose;

  const ChannelAssignmentsDialog({
    Key? key,
    required this.patchManager,
    this.startChannel,
    required this.onClose,
  }) : super(key: key);

  @override
  State<ChannelAssignmentsDialog> createState() =>
      _ChannelAssignmentsDialogState();
}

class _ChannelAssignmentsDialogState extends State<ChannelAssignmentsDialog> {
  late PatchManager _pm;
  late List<ChannelAssignment> _assignmentsCopy;

  @override
  void initState() {
    super.initState();
    _pm = widget.patchManager;
    // Work on a copy so we can discard changes if needed
    _assignmentsCopy = List<ChannelAssignment>.from(_pm.assignments);
    _pm.addListener(_onStateChanged);
  }

  void _onStateChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _pm.removeListener(_onStateChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final numVisible = (widget.startChannel != null) ? 1 : 16;
    final start = widget.startChannel ?? 0;
    final end = (start + numVisible - 1).clamp(0, 15);

    List<int> visibleChannels = [];
    for (int i = start; i <= end; i++) {
      visibleChannels.add(i);
    }

    return Dialog(
      child: Container(
        width: double.maxFinite,
        constraints: const BoxConstraints(maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.list),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Channel Assignments',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          widget.startChannel != null
                              ? 'Channel ${widget.startChannel! + 1}'
                              : 'All 16 MIDI Channels',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      widget.onClose();
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                children: visibleChannels.map((channel) => _buildChannelRowDropdown(
                      channel,
                    )).toList(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _assignAllSamePatch,
                    icon: const Icon(Icons.check_circle),
                    label: const Text('Assign All Same Patch'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _unassignAll,
                    icon: const Icon(Icons.clear_all),
                    label: const Text('Unassign All'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () {
                      // Discard changes
                      widget.onClose();
                      Navigator.pop(context);
                    },
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _saveAndClose,
                    icon: const Icon(Icons.save),
                    label: const Text('Save'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChannelRowDropdown(int channel) {
    final assignment = _assignmentsCopy[channel];
    final List<DropdownMenuItem<int?>> items = [];

    // None option
    items.add(const DropdownMenuItem<int?>(
      value: -1,
      child: Text('None (Unassigned)'),
    ));

    // Patch options from bank
    if (_pm.bank != null) {
      for (int i = 0; i < _pm.bank!.patches.length; i++) {
        final patch = _pm.bank!.patches[i];
        final name = patch?.name ?? 'Empty';
        items.add(DropdownMenuItem<int?>(
          value: i,
          child: Text('$i: $name'),
        ));
      }
    } else {
      items.add(const DropdownMenuItem<int?>(
        value: -1,
        child: Text('No bank loaded'),
      ));
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text('Channel ${channel + 1}', style: const TextStyle(fontSize: 16)),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: DropdownButtonFormField<int?>(
              initialValue: assignment.patchIndex == -1 ? null : assignment.patchIndex,
              items: items,
              onChanged: (value) {
                setState(() {
                  _assignmentsCopy[channel] = ChannelAssignment(channel, value ?? -1);
                });
              },
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _assignAllSamePatch() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Assign Same Patch to All Channels'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Select a patch to assign to all 16 channels:'),
            const SizedBox(height: 12),
            if (_pm.bank == null)
              const Text('No bank loaded')
            else
              DropdownButtonFormField<int?>(
                initialValue: null,
                items: [
                  const DropdownMenuItem<int?>(
                    value: -1,
                    child: Text('None (Unassigned)'),
                  ),
                  ..._pm.bank!.patches.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final patch = entry.value;
                    final name = patch?.name ?? 'Empty';
                    return DropdownMenuItem<int?>(
                      value: idx,
                      child: Text('$idx: $name'),
                    );
                  }),
                ],
                onChanged: (value) {
                  Navigator.pop(context);
                  if (value != null) {
                    for (int i = 0; i < 16; i++) {
                      _assignmentsCopy[i] = ChannelAssignment(i, value);
                    }
                    setState(() {});
                  }
                },
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _unassignAll() {
    for (int i = 0; i < 16; i++) {
      _assignmentsCopy[i] = ChannelAssignment.unassigned(i);
    }
    setState(() {});
  }

  void _saveAndClose() {
    // Apply copy back to PatchManager
    for (int i = 0; i < 16; i++) {
      _pm.assignPatch(i, _assignmentsCopy[i].patchIndex);
    }
    widget.onClose();
    Navigator.pop(context);
  }
}
