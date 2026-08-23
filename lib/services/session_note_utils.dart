const String oneRepMaxMarker = '[orm]';
const String ignoreInGraphMarker = '[ignore_graph]';

String encodeSessionNote(
  String? note, {
  required bool isOneRepMax,
  bool ignoreInGraph = false,
}) {
  final base = (note ?? '').trim();
  final withoutMarkers = base
      .replaceAll(oneRepMaxMarker, '')
      .replaceAll(ignoreInGraphMarker, '')
      .trim();

  final markers = <String>[];
  if (isOneRepMax) {
    markers.add(oneRepMaxMarker);
  }
  if (ignoreInGraph) {
    markers.add(ignoreInGraphMarker);
  }

  if (withoutMarkers.isEmpty) {
    return markers.join(' ');
  }
  if (markers.isEmpty) {
    return withoutMarkers;
  }
  return '$withoutMarkers ${markers.join(' ')}';
}

bool noteHasOneRepMax(String? note) {
  return (note ?? '').contains(oneRepMaxMarker);
}

bool noteIsIgnoredInGraph(String? note) {
  return (note ?? '').contains(ignoreInGraphMarker);
}

String stripOneRepMaxMarker(String? note) {
  return (note ?? '')
      .replaceAll(oneRepMaxMarker, '')
      .replaceAll(ignoreInGraphMarker, '')
      .trim();
}
