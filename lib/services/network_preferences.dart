import 'package:flutter/foundation.dart';
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

  /// Defaults to true (mobile data allowed) until the stored value has
  /// loaded, so behaviour is unchanged for anyone who hasn't touched the
  /// setting.
  final ValueNotifier<bool> allowMobileData = ValueNotifier<bool>(true);

  bool _loaded = false;
  Future<void>? _loading;

  Future<void> _ensureLoaded() {
    if (_loaded) return Future.value();
    return _loading ??= () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        allowMobileData.value = prefs.getBool(_prefKey) ?? true;
      } catch (_) {
        // Keep the default (true) if preferences can't be read.
      }
      _loaded = true;
    }();
  }

  Future<bool> isMobileDataAllowed() async {
    await _ensureLoaded();
    return allowMobileData.value;
  }

  Future<void> setMobileDataAllowed(bool allowed) async {
    allowMobileData.value = allowed;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKey, allowed);
    } catch (_) {
      // Setting still applies for the rest of this app session even if it
      // couldn't be persisted.
    }
  }
}
