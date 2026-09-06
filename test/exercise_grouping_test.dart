import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/services/exercise_grouping.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('buildExerciseGroupSections', () {
    test('always includes the all exercises group and user-made groups', () {
      final exercises = [
        {
          'id': 1,
          'name': 'Bench Press',
          'data': {
            'groups': ['Push', 'Upper Body'],
          },
        },
        {
          'id': 2,
          'name': 'Squat',
          'data': {
            'groups': ['Lower Body'],
          },
        },
      ];

      final sections = buildExerciseGroupSections(exercises);

      expect(sections.map((section) => section.name).toList(), [
        'All Exercises',
        'Lower Body',
        'Push',
        'Upper Body',
      ]);
      expect(
        sections.first.exercises.map((exercise) => exercise['name']).toList(),
        ['Bench Press', 'Squat'],
      );
      expect(
        sections.firstWhere((section) => section.name == 'Push').exercises,
        [
          {
            'id': 1,
            'name': 'Bench Press',
            'data': {
              'groups': ['Push', 'Upper Body'],
            },
          },
        ],
      );
    });

    test('includes groups that have no exercises assigned', () {
      final sections = buildExerciseGroupSections(
        [
          {
            'id': 1,
            'name': 'Bench Press',
            'data': {
              'groups': ['Push'],
            },
          },
        ],
        extraGroupNames: ['Empty Group'],
      );

      expect(sections.map((section) => section.name).toList(), [
        'All Exercises',
        'Empty Group',
        'Push',
      ]);
      expect(
        sections
            .firstWhere((section) => section.name == 'Empty Group')
            .exercises,
        isEmpty,
      );
    });

    test('respects a saved manual group order when building sections', () {
      final exercises = [
        {
          'id': 1,
          'name': 'Bench Press',
          'data': {
            'groups': ['Push'],
          },
        },
        {
          'id': 2,
          'name': 'Squat',
          'data': {
            'groups': ['Lower Body'],
          },
        },
      ];

      final sections = buildExerciseGroupSections(
        exercises,
        extraGroupNames: ['Push', 'Lower Body', 'Upper Body'],
        groupNameOrder: ['Upper Body', 'Push', 'Lower Body'],
      );

      expect(sections.skip(1).map((section) => section.name).toList(), [
        'Upper Body',
        'Push',
        'Lower Body',
      ]);
    });

    test('applies saved per-group exercise order', () {
      final exercises = [
        {
          'id': 1,
          'name': 'Bench Press',
          'data': {
            'groups': ['Push'],
          },
        },
        {
          'id': 2,
          'name': 'Incline Press',
          'data': {
            'groups': ['Push'],
          },
        },
        {
          'id': 3,
          'name': 'Shoulder Press',
          'data': {
            'groups': ['Push'],
          },
        },
      ];

      final sections = buildExerciseGroupSections(
        exercises,
        groupExerciseOrder: {
          'Push': [3, 1, 2],
        },
      );

      final pushSection = sections.firstWhere(
        (section) => section.name == 'Push',
      );
      expect(pushSection.exercises.map((exercise) => exercise['id']).toList(), [
        3,
        1,
        2,
      ]);
    });
  });

  test('reorders group names using Flutter reorder semantics', () {
    final ordered = reorderExerciseGroupNames(
      ['Upper Body', 'Push', 'Lower Body'],
      0,
      2,
    );

    expect(ordered, ['Push', 'Upper Body', 'Lower Body']);
  });

  group('group name storage scoping', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('stores names per user id scope', () async {
      await addExerciseGroupName('Push', userIdOverride: 'user-a');
      await addExerciseGroupName('Pull', userIdOverride: 'user-b');

      final aNames = await loadExerciseGroupNames(
        const [],
        userIdOverride: 'user-a',
      );
      final bNames = await loadExerciseGroupNames(
        const [],
        userIdOverride: 'user-b',
      );

      expect(aNames, ['Push']);
      expect(bNames, ['Pull']);
    });

    test('does not read legacy global key into scoped user data', () async {
      SharedPreferences.setMockInitialValues({
        'exercise_group_names': ['Legacy Group'],
      });

      final names = await loadExerciseGroupNames(
        const [],
        userIdOverride: 'user-a',
      );

      expect(names, isEmpty);
    });
  });

  group('group exercise order storage scoping', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('stores and loads per-user exercise order for a group', () async {
      await saveExerciseGroupOrder('Push', [3, 1, 2], userIdOverride: 'user-a');
      await saveExerciseGroupOrder('Push', [2, 1], userIdOverride: 'user-b');

      final aOrder = await loadExerciseGroupOrder(
        'Push',
        userIdOverride: 'user-a',
      );
      final bOrder = await loadExerciseGroupOrder(
        'Push',
        userIdOverride: 'user-b',
      );

      expect(aOrder, [3, 1, 2]);
      expect(bOrder, [2, 1]);
    });

    test('clears only one user scoped exercise group storage', () async {
      await addExerciseGroupName('Push', userIdOverride: 'user-a');
      await addExerciseGroupName('Pull', userIdOverride: 'user-b');
      await saveExerciseGroupOrder('Push', [3, 1, 2], userIdOverride: 'user-a');
      await saveExerciseGroupOrder('Pull', [4, 5], userIdOverride: 'user-b');

      await clearExerciseGroupingForUser('user-a');

      expect(
        await loadExerciseGroupNames(const [], userIdOverride: 'user-a'),
        isEmpty,
      );
      expect(await loadExerciseGroupNames(const [], userIdOverride: 'user-b'), [
        'Pull',
      ]);
      expect(
        await loadExerciseGroupOrder('Push', userIdOverride: 'user-a'),
        isEmpty,
      );
      expect(await loadExerciseGroupOrder('Pull', userIdOverride: 'user-b'), [
        4,
        5,
      ]);
    });
  });
}
