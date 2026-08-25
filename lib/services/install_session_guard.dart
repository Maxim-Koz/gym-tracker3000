import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Ensures reinstalled apps do not auto-login from restored secure storage.
class InstallSessionGuard {
  static const String _installMarkerKey = 'install_marker_v1';

  Future<void> clearRestoredSessionOnFreshInstall() async {
    final prefs = await SharedPreferences.getInstance();
    final hasMarker = prefs.getBool(_installMarkerKey) ?? false;

    if (hasMarker) return;

    final auth = Supabase.instance.client.auth;
    if (auth.currentSession != null) {
      try {
        await auth.signOut(scope: SignOutScope.local);
      } catch (_) {
        // Fallback in case scope support changes.
        await auth.signOut();
      }
    }

    await prefs.setBool(_installMarkerKey, true);
  }
}
