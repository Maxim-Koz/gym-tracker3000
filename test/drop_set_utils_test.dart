import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/services/set_entry_utils.dart';

void main() {
  test('collects valid drop-set entries and preserves their group index', () {
    final firstRow = SetEntryRow()
      ..weightController.text = '100'
      ..repsController.text = '8';
    final invalidRow = SetEntryRow()
      ..weightController.text = '0'
      ..repsController.text = '0';
    final secondRow = SetEntryRow()
      ..weightController.text = '80'
      ..repsController.text = '10'
      ..unit = 'lb';

    final entries = collectValidSetEntries(
      type: 'drop',
      normalRows: const [],
      dropGroups: [
        DropGroup(rows: [firstRow, invalidRow]),
        DropGroup(rows: [secondRow]),
      ],
    );

    expect(entries, hasLength(2));
    expect(entries.first['groupIndex'], 0);
    expect(entries.last['groupIndex'], 1);
    expect(entries.first['weight'], 100.0);
    expect(entries.last['reps'], 10);
    expect(entries.last['unit'], 'lb');
  });

  test('ignores empty rows when collecting drop-set entries', () {
    final emptyRow = SetEntryRow();

    final entries = collectValidSetEntries(
      type: 'drop',
      normalRows: const [],
      dropGroups: [
        DropGroup(rows: [emptyRow]),
      ],
    );

    expect(entries, isEmpty);
  });
}
