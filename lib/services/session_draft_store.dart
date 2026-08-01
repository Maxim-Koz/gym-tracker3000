/// Holds an in-progress (unsaved) "log new session" form per exercise, so
/// that if the user accidentally navigates away from RecordExerciseScreen
/// before hitting Save - e.g. an accidental back-tap - whatever they'd
/// already typed is restored the next time they open that same exercise,
/// instead of silently being lost.
///
/// Deliberately in-memory only and cleared when the app process ends -
/// this is meant to survive a stray navigation, not to be a durable
/// offline draft (unsaved sets were never written to the database, so
/// there's nothing to sync/recover after a real restart anyway).
class SessionDraftStore {
  static final SessionDraftStore _instance = SessionDraftStore._internal();
  factory SessionDraftStore() => _instance;
  SessionDraftStore._internal();

  final Map<int, SessionDraft> _drafts = {};

  SessionDraft? get(int exerciseId) => _drafts[exerciseId];

  /// Stores [draft] for [exerciseId], or drops any existing draft if
  /// [draft] has nothing meaningful in it (no point restoring "nothing").
  void save(int exerciseId, SessionDraft draft) {
    if (draft.isEmpty) {
      _drafts.remove(exerciseId);
    } else {
      _drafts[exerciseId] = draft;
    }
  }

  void clear(int exerciseId) {
    _drafts.remove(exerciseId);
  }
}

/// A plain-data snapshot of the log-new-session form - deliberately holds
/// text values rather than TextEditingControllers, since controllers get
/// disposed along with the screen that's being navigated away from.
class SessionDraft {
  SessionDraft({
    required this.type,
    required this.unit,
    required this.note,
    required this.normalRows,
    required this.dropGroups,
  });

  final String type;
  final String unit;
  final String note;
  final List<NormalRowDraft> normalRows;
  final List<List<DropRowDraft>> dropGroups;

  bool get isEmpty {
    final hasNormalContent = normalRows.any((row) => row.hasContent);
    final hasDropContent = dropGroups.any(
      (group) => group.any((row) => row.hasContent),
    );
    return note.trim().isEmpty && !hasNormalContent && !hasDropContent;
  }
}

class NormalRowDraft {
  NormalRowDraft({
    required this.weight,
    required this.reps,
    required this.unit,
    required this.restPauses,
  });

  final String weight;
  final String reps;
  final String unit;
  final List<String> restPauses;

  bool get hasContent =>
      weight.trim().isNotEmpty ||
      reps.trim().isNotEmpty ||
      restPauses.any((pause) => pause.trim().isNotEmpty);
}

class DropRowDraft {
  DropRowDraft({required this.weight, required this.reps, required this.unit});

  final String weight;
  final String reps;
  final String unit;

  bool get hasContent => weight.trim().isNotEmpty || reps.trim().isNotEmpty;
}
