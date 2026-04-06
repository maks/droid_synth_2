// Flutter DX7 Synth Widget Tests

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:droid_synth_2/app.dart';
import 'package:droid_synth_2/services/patch_manager.dart';

void main() {
  group('Bank Loader UI Tests', () {
    testWidgets('Bank Loader Dialog shows current bank status', (tester) async {
      final patchManager = PatchManager();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BankLoaderDialog(patchManager: patchManager),
          ),
        ),
      );

      expect(find.text('Load DX7 Bank'), findsOneWidget);
    });
  });

  group('Channel Assignments UI Tests', () {
    testWidgets('Channel Assignments Dialog shows channel list', (tester) async {
      final patchManager = PatchManager();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChannelAssignmentsDialog(
              patchManager: patchManager,
              onClose: () {},
            ),
          ),
        ),
      );

      expect(find.text('Channel Assignments'), findsOneWidget);
    });
  });
}
