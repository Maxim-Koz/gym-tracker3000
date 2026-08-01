import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/services/bodyweight_lookup.dart';

void main() {
  group('findBodyWeightAtOrBefore', () {
    test(
      'returns the latest known bodyweight when a session is older than the first entry',
      () {
        final bodyWeights = [
          {
            'timestamp': DateTime(2026, 7, 31, 12),
            'weight': 75.0,
            'unit': 'kg',
          },
        ];

        final entry = findBodyWeightAtOrBefore(
          DateTime(2026, 7, 28, 12),
          bodyWeights,
        );

        expect(entry, isNotNull);
        expect(entry!['weight'], 75.0);
      },
    );

    test(
      'returns the newest bodyweight that is on or before the session date',
      () {
        final bodyWeights = [
          {
            'timestamp': DateTime(2026, 7, 31, 12),
            'weight': 75.0,
            'unit': 'kg',
          },
          {
            'timestamp': DateTime(2026, 7, 28, 12),
            'weight': 74.0,
            'unit': 'kg',
          },
        ];

        final entry = findBodyWeightAtOrBefore(
          DateTime(2026, 7, 31, 18),
          bodyWeights,
        );

        expect(entry, isNotNull);
        expect(entry!['weight'], 75.0);
      },
    );
  });
}
