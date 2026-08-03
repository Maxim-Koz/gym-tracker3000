import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/services/session_note_utils.dart';
import 'package:gym_tracker/services/set_entry_utils.dart';

void main() {
  group('one-rep-max note helpers', () {
    test('encodes and decodes the one-rep-max marker without leaking it', () {
      expect(
        encodeSessionNote('Nice session', isOneRepMax: true),
        'Nice session $oneRepMaxMarker',
      );
      expect(noteHasOneRepMax('Nice session $oneRepMaxMarker'), isTrue);
      expect(
        stripOneRepMaxMarker('Nice session $oneRepMaxMarker'),
        'Nice session',
      );
      expect(
        encodeSessionNote('Nice session $oneRepMaxMarker', isOneRepMax: false),
        'Nice session',
      );
    });

    test('collects ORM as a single-weight entry with one rep', () {
      final normalRows = <Map<String, dynamic>>[
        {
          'weight': TextEditingController(text: '125'),
          'reps': TextEditingController(text: ''),
          'unit': 'kg',
          'restPauses': <TextEditingController>[],
        },
      ];

      final entries = collectValidSetEntries(
        type: 'normal',
        normalRows: normalRows,
        dropGroups: const [],
        isOneRepMax: true,
      );

      expect(entries, hasLength(1));
      expect(entries.single['weight'], 125.0);
      expect(entries.single['reps'], 1);
      expect(entries.single['isOneRepMax'], isTrue);
    });
  });
}
