import 'dart:async';

import 'package:bonsai/bonsai.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:flutter_virtual_piano/flutter_virtual_piano.dart';
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
  static const int _synthChannelCount = 16;

  late MSFAPlugin plugin;
  late final Future<void> appInitCompleted;
  late final MidiCommand midiCommand;
  late final MidiRouter midiRouter;
  late final PatchManager patchManager;

  bool _engineReady = false;
  String _engineStatus = 'initializing';
  int _selectedPianoChannel = 0;

  @override
  void initState() {
    super.initState();

    midiCommand = MidiCommand();
    plugin = MSFAPlugin();
    patchManager = PatchManager();
    patchManager.setOnSendSysexToPlugin(_sendBankSysexToAllSynths);
    midiRouter = MidiRouter(
      midi: midiCommand,
      patchManager: patchManager,
      onSendRawMidi: _sendRawMidiToPlugin,
      onSendProgramChange: _sendProgramChangeToPlugin,
    );

    appInitCompleted = _initializeApp();

    midiRouter.midiEvents.listen((event) {
      log('midi event: ${event.data}');
    });

    midiRouter.messages.listen((message) {
      log(message);
    });
  }

  Future<void> _initializeApp() async {
    try {
      final initialized = await plugin.init();
      if (!initialized) {
        throw StateError('MSFA engine failed to initialize');
      }

      for (int channel = 1; channel < _synthChannelCount; channel++) {
        plugin.createSynth();
      }

      await midiRouter.connectDevice();

      if (!mounted) {
        return;
      }

      setState(() {
        _engineReady = true;
        _engineStatus = 'active';
      });
    } catch (error, stackTrace) {
      log('App initialization failed: $error\n$stackTrace');
      if (mounted) {
        setState(() {
          _engineStatus = 'failed';
        });
      }
      rethrow;
    }
  }

  void _sendRawMidiToPlugin(Uint8List bytes) {
    if (!_engineReady) {
      log('Ignoring MIDI before engine init: $bytes');
      return;
    }
    log('Plugin sendMidi: $bytes');
    plugin.sendMidi(bytes);
  }

  @override
  void dispose() {
    patchManager.dispose();
    midiRouter.disconnect();
    midiRouter.close();
    midiCommand.dispose();
    plugin.shutDown();
    super.dispose();
  }

  void _sendProgramChangeToPlugin(int channel, int program) {
    if (!_engineReady) {
      return;
    }
    final statusByte = 0xC0 | channel;
    final bytes = Uint8List.fromList([statusByte, program]);
    log('Sending Program Change to plugin: channel=$channel, program=$program, bytes=$bytes');
    plugin.sendMidiToChannel(channel, bytes);
  }

  void _sendBankSysexToAllSynths(Uint8List sysexBytes) {
    Future<void> send() async {
      await appInitCompleted;
      if (!_engineReady) {
        return;
      }

      for (int channel = 0; channel < _synthChannelCount; channel++) {
        plugin.sendMidiToChannel(channel, sysexBytes);
      }

      for (final assignment in patchManager.assignments) {
        if (assignment.isAssigned) {
          _sendProgramChangeToPlugin(assignment.channel, assignment.patchIndex);
        }
      }
    }

    unawaited(send());
  }

  String _patchLabelForChannel(int channel) {
    final assignment = patchManager.getAssignment(channel);
    if (!assignment.isAssigned) {
      return 'Unassigned';
    }
    return patchManager.bank?.getPatch(assignment.patchIndex)?.name ?? 'Patch ${assignment.patchIndex}';
  }

  @override
  Widget build(BuildContext context) {
    const textStyle = TextStyle(fontSize: 14);
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
        future: appInitCompleted,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Initialization error: ${snapshot.error}'));
          }

          return AnimatedBuilder(
            animation: patchManager,
            builder: (context, _) {
              final assignedChannels = patchManager.assignments.where((assignment) => assignment.isAssigned).length;

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
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue[50],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.storage, color: Colors.blue),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    patchManager.isBankLoaded
                                        ? '${patchManager.bank?.validPatches.length ?? 0} patches loaded'
                                        : 'No bank loaded',
                                    style: const TextStyle(fontWeight: FontWeight.w500),
                                  ),
                                  if (patchManager.bankIdentifier != null)
                                    Text(
                                      patchManager.bankIdentifier!,
                                      style: const TextStyle(fontSize: 12, color: Colors.black54),
                                    ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.refresh),
                              tooltip: 'Load New Bank',
                              onPressed: _showBankLoaderDialog,
                            ),
                          ],
                        ),
                      ),
                      spacerMedium,
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green[50],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Channel Assignments Summary ($assignedChannels/16)',
                              style: const TextStyle(fontWeight: FontWeight.w500),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: List.generate(16, (index) {
                                final assignment = patchManager.getAssignment(index);
                                return _buildChannelChip(
                                  index,
                                  _patchLabelForChannel(index),
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
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange[50],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Expanded(
                                  child: Text(
                                    'Virtual Piano',
                                    style: TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                ),
                                DropdownButton<int>(
                                  value: _selectedPianoChannel,
                                  onChanged: (value) {
                                    if (value == null) {
                                      return;
                                    }
                                    setState(() {
                                      _selectedPianoChannel = value;
                                    });
                                  },
                                  items: List.generate(16, (channel) {
                                    return DropdownMenuItem<int>(
                                      value: channel,
                                      child: Text('CH ${channel + 1}'),
                                    );
                                  }),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Current patch: ${_patchLabelForChannel(_selectedPianoChannel)}',
                              style: const TextStyle(fontSize: 12, color: Colors.black54),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              height: 120,
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
                          ],
                        ),
                      ),
                      spacerMedium,
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blueAccent[100],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'MSFA Engine: $_engineStatus',
                                style: textStyle,
                              ),
                            ),
                            TextButton(
                              onPressed: () {
                                plugin.shutDown();
                                setState(() {
                                  _engineReady = false;
                                  _engineStatus = 'stopped';
                                });
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
          );
        },
      ),
    );
  }

  Widget _buildChannelChip(int channelIndex, String patchName, bool isAssigned) {
    final color = isAssigned ? Colors.green[700]! : Colors.grey[400]!;
    final label = isAssigned ? 'CH ${channelIndex + 1}: $patchName' : 'CH ${channelIndex + 1}: None';
    return GestureDetector(
      onTap: () => _showChannelAssignments(channel: channelIndex),
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
        onPreviewPatch: (patchIndex) {
          final originalPatch = patchManager.getPatchIndexForChannel(0);
          patchManager.assignPatch(0, patchIndex);
          midiRouter.sendVirtualPianoNote(60, 87, channel: 0);

          Future.delayed(const Duration(milliseconds: 500), () {
            midiRouter.sendVirtualPianoNoteOff(60, channel: 0);
            patchManager.assignPatch(0, originalPatch);
          });
        },
      ),
    );
  }

  void _onNoteDown(int note) {
    midiRouter.sendVirtualPianoNote(note, 87, channel: _selectedPianoChannel);
  }

  void _onNoteUp(int note) {
    midiRouter.sendVirtualPianoNoteOff(note, channel: _selectedPianoChannel);
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
          identifier: result.files.single.name, rawSysex: bytes);
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
  final Function(int patchIndex)? onPreviewPatch;

  const ChannelAssignmentsDialog({
    Key? key,
    required this.patchManager,
    this.startChannel,
    required this.onClose,
    this.onPreviewPatch,
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
              child: Column(
                children: [
                  Row(
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
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _previewCurrentPatch,
                        icon: const Icon(Icons.play_arrow, size: 18),
                        label: const Text('Preview Patch', style: TextStyle(fontSize: 12)),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                      ),
                    ],
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

  void _previewCurrentPatch() {
    // Find a patch to preview - use the first channel that has a patch assigned
    // or use channel 0's assignment
    int patchIndexToPreview = _assignmentsCopy[0].patchIndex;
    
    // If channel 0 is unassigned, find any assigned patch
    if (patchIndexToPreview == -1 && _pm.bank != null) {
      for (int i = 0; i < 16; i++) {
        if (_assignmentsCopy[i].patchIndex != -1) {
          patchIndexToPreview = _assignmentsCopy[i].patchIndex;
          break;
        }
      }
    }
    
    if (patchIndexToPreview == -1) {
      // No patches assigned, use first patch in bank
      if (_pm.bank != null && _pm.bank!.validPatches.isNotEmpty) {
        patchIndexToPreview = _pm.bank!.validPatches[0].key;
      } else {
        return; // No patches available
      }
    }
    
    // Call the parent's preview callback
    widget.onPreviewPatch?.call(patchIndexToPreview);
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
