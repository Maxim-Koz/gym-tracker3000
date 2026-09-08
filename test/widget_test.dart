import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/screens/record_exercise_screen.dart';
import 'package:gym_tracker/screens/year_history_screen.dart';
import 'package:gym_tracker/widgets/edit_log_sheet.dart';
import 'package:gym_tracker/widgets/workout_calendar.dart';

void main() {
  testWidgets('calendar shows month title and day cells', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorkoutCalendar(
            month: DateTime(2024, 5),
            loggedDates: {DateTime(2024, 5, 10)},
          ),
        ),
      ),
    );

    expect(find.text('May 2024'), findsOneWidget);
    expect(find.text('10'), findsWidgets);
  });

  testWidgets('calendar notifies when a logged day is tapped', (tester) async {
    DateTime? selectedDate;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorkoutCalendar(
            month: DateTime(2024, 5),
            loggedDates: {DateTime(2024, 5, 10)},
            onDateSelected: (date) => selectedDate = date,
          ),
        ),
      ),
    );

    await tester.tap(find.text('10').last);
    await tester.pump();

    expect(selectedDate, DateTime(2024, 5, 10));
  });

  testWidgets('year history screen renders the contribution grid', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: YearHistoryScreen()));
    await tester.pumpAndSettle();

    expect(find.byType(DropdownButton<int>), findsOneWidget);
    expect(find.text('Each block represents a logged day.'), findsOneWidget);
  });

  testWidgets('year history screen spans the full selected year', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: YearHistoryScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Dec'), findsOneWidget);
  });

  test('inferDefaultUnitFromRecentSessions prefers the latest logged unit', () {
    final unit = inferDefaultUnitFromRecentSessions([
      {
        'session': {'id': 1},
        'sets': [
          {'unit': 'lb'},
        ],
      },
      {
        'session': {'id': 2},
        'sets': [
          {'unit': 'kg'},
        ],
      },
    ]);

    expect(unit, 'kg');
  });

  testWidgets('reorderable list callback reorders items', (tester) async {
    final items = <String>['Push', 'Pull', 'Legs'];

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            return Scaffold(
              body: ReorderableListView(
                onReorder: (oldIndex, newIndex) {
                  setState(() {
                    if (oldIndex < newIndex) {
                      newIndex -= 1;
                    }
                    final item = items.removeAt(oldIndex);
                    items.insert(newIndex, item);
                  });
                },
                children: [
                  for (final item in items)
                    ListTile(key: ValueKey(item), title: Text(item)),
                ],
              ),
            );
          },
        ),
      ),
    );

    final list = tester.widget<ReorderableListView>(
      find.byType(ReorderableListView),
    );
    list.onReorder?.call(0, 2);
    await tester.pump();

    expect(items, ['Pull', 'Push', 'Legs']);
  });

  testWidgets('edit log sheet allows negative weights', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditLogSheet(
            session: {'id': 1, 'note': null, 'timestamp': DateTime(2024, 1, 2)},
            sets: [
              {
                'id': 10,
                'weight': 70.0,
                'reps': 5,
                'unit': 'kg',
                'parent_set_id': null,
                'group_index': null,
              },
            ],
            onChanged: () {},
          ),
        ),
      ),
    );

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Weight' &&
            widget.keyboardType ==
                const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
      ),
      findsWidgets,
    );
  });

  testWidgets('edit log sheet uses one shared unit selector for all sets', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditLogSheet(
            session: {'id': 1, 'note': null, 'timestamp': DateTime(2024, 1, 2)},
            sets: [
              {
                'id': 10,
                'weight': 70.0,
                'reps': 5,
                'unit': 'kg',
                'parent_set_id': null,
                'group_index': null,
              },
              {
                'id': 11,
                'weight': 80.0,
                'reps': 3,
                'unit': 'kg',
                'parent_set_id': null,
                'group_index': null,
              },
            ],
            onChanged: () {},
          ),
        ),
      ),
    );

    expect(find.text('Unit'), findsOneWidget);
    expect(find.text('kg'), findsWidgets);

    await tester.tap(find.byType(DropdownButton<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('lb').last);
    await tester.pumpAndSettle();

    expect(find.text('lb'), findsWidgets);
  });

  testWidgets(
    'record exercise screen ignores dependency updates after disposal',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const RecordExerciseScreen()),
              ),
              child: const Text('Open record screen'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open record screen'));
      await tester.pumpAndSettle();

      final screenState = tester.state(find.byType(RecordExerciseScreen));
      await tester.pumpWidget(const SizedBox());

      expect(() => screenState.didChangeDependencies(), returnsNormally);
      expect(find.byType(RecordExerciseScreen), findsNothing);
    },
  );
}
