import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Whether the app is allowed to use mobile (cellular) data to talk to
/// Supabase. When this is off, a connection that's mobile-only is treated
/// as if there were no connection at all: reads fall back to the local
/// cache and writes get queued for later, exactly like being offline. A
/// Wi-Fi (or ethernet) connection is always used regardless of this
/// setting.
class NetworkPreferences {
  static final NetworkPreferences _instance = NetworkPreferences._internal();
  factory NetworkPreferences() => _instance;
  NetworkPreferences._internal();

  static const _prefKey = 'allow_mobile_data_sync';

  String _currentScope() {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    return userId?.trim().isNotEmpty == true ? userId!.trim() : 'anonymous';
  }

  String _prefKeyForScope({String? userIdOverride}) {
    final scope = userIdOverride?.trim().isNotEmpty == true
        ? userIdOverride!.trim()
        : _currentScope();
    return '$_prefKey::$scope';
  }

  /// Defaults to true (mobile data allowed) until the stored value has
  /// loaded, so behaviour is unchanged for anyone who hasn't touched the
  /// setting.
  final ValueNotifier<bool> allowMobileData = ValueNotifier<bool>(true);

  bool _loaded = false;
  String? _loadedScope;
  Future<void>? _loading;

  Future<void> _ensureLoaded({String? userIdOverride}) {
    final scope = userIdOverride?.trim().isNotEmpty == true
        ? userIdOverride!.trim()
        : _currentScope();
    if (_loaded && _loadedScope == scope) return Future.value();

    _loaded = false;
    _loadedScope = scope;
    _loading = null;
    final storageKey = _prefKeyForScope(userIdOverride: userIdOverride);
    return _loading ??= () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        allowMobileData.value =
            prefs.getBool(storageKey) ?? scope != 'anonymous';
      } catch (_) {
        // Keep the startup default (off for anonymous users, on for signed-in
        // users) if preferences can't be read.
      }
      _loaded = true;
    }();
  }

  Future<bool> isMobileDataAllowed({String? userIdOverride}) async {
    await _ensureLoaded(userIdOverride: userIdOverride);
    return allowMobileData.value;
  }

  Future<void> setMobileDataAllowed(
    bool allowed, {
    String? userIdOverride,
  }) async {
    allowMobileData.value = allowed;
    _loaded = true;
    _loadedScope = userIdOverride?.trim().isNotEmpty == true
        ? userIdOverride!.trim()
        : _currentScope();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(
        _prefKeyForScope(userIdOverride: userIdOverride),
        allowed,
      );
    } catch (_) {
      // Setting still applies for the rest of this app session even if it
      // couldn't be persisted.
    }
  }

  void clearLoadedState() {
    _loaded = false;
    _loadedScope = null;
    _loading = null;
  }
}
