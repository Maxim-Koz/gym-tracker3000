import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import 'db_helper.dart';

/// Triggers [DBHelper.syncPendingOperations] and [DBHelper.warmCaches] as
/// soon as connectivity comes back, so writes queued while offline go out
/// immediately, and the exercises/sessions/sets caches used by screens like
/// stats and the home calendar stay fresh even if the user hasn't actually
/// opened those screens recently.
///
/// Also keeps a long-interval backstop timer running, since a connectivity
/// event firing "online" doesn't always mean there's real internet access
/// (e.g. connected to a Wi-Fi network with no upstream) - both calls are
/// cheap no-ops when there's nothing to do or the network genuinely isn't
/// there, so polling occasionally costs nothing.
class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  Timer? _fallbackTimer;

  void start() {
    if (_subscription != null) return;

    // Try once immediately (covers the case where the app opened already
    // online with queued writes left over from a previous offline session).
    trigger();

    _subscription = _connectivity.onConnectivityChanged.listen((results) {
      final isOnline = results.any((r) => r != ConnectivityResult.none);
      if (isOnline) trigger();
    });

    _fallbackTimer = Timer.periodic(
      const Duration(minutes: 2),
      (_) => trigger(),
    );
  }

  void stop() {
    _subscription?.cancel();
    _subscription = null;
    _fallbackTimer?.cancel();
    _fallbackTimer = null;
  }

  /// Fire-and-forget: call this right after a login/signup, or whenever you
  /// want to nudge a sync + cache-warm attempt outside of a connectivity
  /// change.
  void trigger() {
    // ignore: discarded_futures
    _run();
  }

  Future<void> _run() async {
    await DBHelper().syncPendingOperations();
    await DBHelper().warmCaches();
  }
}
