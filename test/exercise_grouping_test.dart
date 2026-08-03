import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/services/exercise_grouping.dart';

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
  });
}
