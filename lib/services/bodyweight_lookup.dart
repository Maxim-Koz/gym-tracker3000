import 'weight_format.dart';

/// Given a list of body weight entries (as returned by
/// `DBHelper().getBodyWeights()`, newest first) and a [date], returns the
/// latest known bodyweight entry for that session date. When no entry has
/// been recorded on or before that date yet, this intentionally falls back to
/// the most recent bodyweight entry overall so older exercise logs do not lose
/// the bodyweight annotation.
Map<String, dynamic>? findBodyWeightAtOrBefore(
  DateTime date,
  List<Map<String, dynamic>> bodyWeightsNewestFirst,
) {
  if (bodyWeightsNewestFirst.isEmpty) return null;

  for (final entry in bodyWeightsNewestFirst) {
    final entryDate = entry['timestamp'] as DateTime;
    if (!entryDate.isAfter(date)) {
      return entry;
    }
  }

  // No bodyweight has been recorded on or before this session date yet.
  // Preserve the latest known measurement rather than stripping the label off
  // older exercise logs entirely.
  return bodyWeightsNewestFirst.first;
}

/// Formats a body weight entry as e.g. "75 kg" (no decimal when the value
/// is a whole number).
String formatBodyWeightEntry(Map<String, dynamic> entry) {
  final weight = (entry['weight'] as num).toDouble();
  final unit = entry['unit'] as String? ?? '';
  return '${formatWeight(weight)} $unit'.trim();
}
