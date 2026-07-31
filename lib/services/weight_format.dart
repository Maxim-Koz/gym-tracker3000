/// Formats a weight value for display and for pre-filling edit fields.
///
/// Unlike a bare `toStringAsFixed(1)`, this keeps up to [maxDecimals]
/// decimal places (2 by default) without forcing extra trailing zeros -
/// 72 stays "72", 72.5 stays "72.5", and 72.45 stays "72.45" instead of
/// being silently rounded to "72.5" or "72.4".
///
/// This matters anywhere a formatted value is used to re-populate a text
/// field for editing (e.g. the weight-log edit dialog, or editing a set's
/// weight in a past session): rounding there would permanently truncate
/// the stored precision the next time the user saves, even if they didn't
/// touch the weight field at all.
String formatWeight(double weight, {int maxDecimals = 2}) {
  if (weight == weight.roundToDouble()) {
    return weight.toInt().toString();
  }
  var text = weight.toStringAsFixed(maxDecimals);
  // Trim any trailing zeros (and a trailing '.' if nothing's left after
  // trimming), so 72.50 displays as 72.5 rather than 72.50.
  if (text.contains('.')) {
    text = text.replaceFirst(RegExp(r'0+$'), '');
    text = text.replaceFirst(RegExp(r'\.$'), '');
  }
  return text;
}
