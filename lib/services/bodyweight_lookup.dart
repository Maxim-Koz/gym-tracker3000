import 'weight_format.dart';

/// Given a list of body weight entries (as returned by
/// `DBHelper().getBodyWeights()`, newest first) and a [date], returns the
/// most recent entry that was logged at or before that date - i.e. "the
/// last recorded body weight at that time". Returns null if every entry
/// was logged after [date] (nothing recorded yet as of then).
Map<String, dynamic>? findBodyWeightAtOrBefore(
  DateTime date,
  List<Map<String, dynamic>> bodyWeightsNewestFirst,
) {
  for (final entry in bodyWeightsNewestFirst) {
    final entryDate = entry['timestamp'] as DateTime;
    if (!entryDate.isAfter(date)) {
      return entry;
    }
  }
  return null;
}

/// Formats a body weight entry as e.g. "75 kg" (no decimal when the value
/// is a whole number).
String formatBodyWeightEntry(Map<String, dynamic> entry) {
  final weight = (entry['weight'] as num).toDouble();
  final unit = entry['unit'] as String? ?? '';
  return '${formatWeight(weight)} $unit'.trim();
}
