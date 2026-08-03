const String oneRepMaxMarker = '[orm]';

String encodeSessionNote(String? note, {required bool isOneRepMax}) {
  final base = (note ?? '').trim();
  final withoutMarker = base.replaceAll(oneRepMaxMarker, '').trim();
  if (!isOneRepMax) {
    return withoutMarker;
  }
  return withoutMarker.isEmpty
      ? oneRepMaxMarker
      : '$withoutMarker $oneRepMaxMarker';
}

bool noteHasOneRepMax(String? note) {
  return (note ?? '').contains(oneRepMaxMarker);
}

String stripOneRepMaxMarker(String? note) {
  return (note ?? '').replaceAll(oneRepMaxMarker, '').trim();
}
