import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'db_helper.dart';
import 'network_preferences.dart';

/// Triggers [DBHelper.syncPendingOperations] and [DBHelper.warmCaches] as
/// soon as connectivity comes back. Also monitors state changes to display
/// an app-wide online/offline pop-up notification.
class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  Timer? _fallbackTimer;

  // Tracks the previous status to detect actual transitions
  bool? _lastIsOnline;

  /// Global key to display snackbars from outside the widget tree.
  /// Register this key in your MaterialApp root definition.
  static final GlobalKey<ScaffoldMessengerState> messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  void start() {
    if (_subscription != null) return;

    // Determine initial state quietly on startup
    _connectivity.checkConnectivity().then((results) {
      _updateOnlineStatus(results, isInitial: true);
    });

    // Listen to physical connection changes
    _subscription = _connectivity.onConnectivityChanged.listen((results) {
      _updateOnlineStatus(results);
    });

    // Listen to user mobile data preference changes
    NetworkPreferences().allowMobileData.addListener(_onPrefChanged);

    _fallbackTimer = Timer.periodic(
      const Duration(minutes: 2),
      (_) => trigger(),
    );
  }

  void stop() {
    _subscription?.cancel();
    _subscription = null;
    NetworkPreferences().allowMobileData.removeListener(_onPrefChanged);
    _fallbackTimer?.cancel();
    _fallbackTimer = null;
    _lastIsOnline = null;
  }

  void _onPrefChanged() async {
    final results = await _connectivity.checkConnectivity();
    _updateOnlineStatus(results);
  }

  Future<void> _updateOnlineStatus(
    List<ConnectivityResult> results, {
    bool isInitial = false,
  }) async {
    final usable = results.where((r) => r != ConnectivityResult.none).toSet();
    bool isOnline = false;

    if (usable.isNotEmpty) {
      final hasNonMobile = usable.any((r) => r != ConnectivityResult.mobile);
      if (hasNonMobile) {
        isOnline = true;
      } else {
        // Fall back to user preferences if only cellular data is running
        isOnline = NetworkPreferences().allowMobileData.value;
      }
    }

    if (isOnline) trigger();

    // Trigger the pop-up only when an actual change happens after initial load
    if (!isInitial && _lastIsOnline != null && _lastIsOnline != isOnline) {
      final message = isOnline ? 'App is now online' : 'App is now offline';

      messengerKey.currentState?.removeCurrentSnackBar();
      messengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    }

    _lastIsOnline = isOnline;
  }

  void trigger() {
    // ignore: discarded_futures
    _run();
  }

  Future<void> _run() async {
    await DBHelper().syncPendingOperations();
    await DBHelper().warmCaches();
  }
}
