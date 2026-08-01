import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:gym_tracker/services/data_migration_service.dart';
import 'package:gym_tracker/services/db_helper.dart';
import 'package:gym_tracker/widgets/bottom_nav_bar.dart';
import 'package:gym_tracker/widgets/workout_calendar.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  // Call this on logout so a different account signing in afterwards
  // doesn't briefly show the previous user's cached username.
  static void clearCachedUsername() {
    _HomeScreenState._cachedUsername = null;
    _HomeScreenState._clearPersistedUsername();
  }

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Cached across HomeScreen instances (a new one is pushed each time the
  // bottom nav bar returns here), so we don't flash the 'there' placeholder
  // every time this screen is rebuilt while the real username loads.
  static String? _cachedUsername;

  int _selectedIndex = 0;
  String _username = 'there';
  Set<DateTime> _loggedDates = <DateTime>{};

  static String _usernameKey(String userId) => 'cached_username_$userId';

  static Future<String?> _readPersistedUsername(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_usernameKey(userId));
  }

  static Future<void> _writePersistedUsername(
    String userId,
    String username,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_usernameKey(userId), username);
  }

  static Future<void> _clearPersistedUsername() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    await prefs.remove(_usernameKey(userId));
  }

  @override
  void initState() {
    super.initState();
    _loadUsername();
    // Run independently rather than one after the other - migration is
    // now offline-safe on its own (see DataMigrationService), but even so,
    // the calendar shouldn't have to wait on it: a slow migration (a
    // large legacy import, for instance) shouldn't leave the calendar
    // sitting blank in the meantime when it has nothing to do with it.
    DataMigrationService().migrateIfNeeded(); // ignore: discarded_futures
    _loadLoggedDates();
  }

  Future<void> _loadUsername() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      if (!mounted) return;
      setState(() => _username = 'there');
      return;
    }

    final persisted = await _readPersistedUsername(user.id);
    if (persisted != null && persisted.isNotEmpty) {
      _cachedUsername = persisted;
      if (!mounted) return;
      setState(() => _username = persisted);
    }

    try {
      final response = await Supabase.instance.client
          .from('profiles')
          .select('username')
          .eq('id', user.id)
          .maybeSingle();

      String? username;
      if (response is Map<String, dynamic>) {
        username = response['username'] as String?;
      }

      if (username != null && username.isNotEmpty) {
        _cachedUsername = username;
        await _writePersistedUsername(user.id, username);
        if (!mounted) return;
        setState(() {
          _username = username!;
        });
      }
    } catch (_) {
      if (_cachedUsername != null && mounted) {
        setState(() => _username = _cachedUsername!);
      }
    }
  }

  Future<void> _loadLoggedDates() async {
    try {
      final dates = await DBHelper().getLoggedDates();
      if (!mounted) return;
      setState(() => _loggedDates = dates.toSet());
    } catch (e) {
      // Leave whatever was already showing (possibly nothing, on first
      // load) rather than crash the home screen over a calendar that
      // failed to load - the full year view has its own retry affordance.
      debugPrint('Failed to load logged dates: $e');
    }
  }

  void _onNavTap(int index) {
    setState(() {
      _selectedIndex = index;
    });

    switch (index) {
      case 0:
        // Already on home
        break;
      case 1:
        Navigator.of(context).pushNamed('/add_exercise');
        break;
      case 2:
        Navigator.of(context).pushNamed('/weight');
        break;
      case 3:
        Navigator.of(context).pushNamed('/settings');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        toolbarHeight: 100,
        title: Padding(
          padding: const EdgeInsets.only(top: 24),
          child: Text(
            'Hello, $_username',
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
          ),
        ),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            WorkoutCalendar(month: DateTime.now(), loggedDates: _loggedDates),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () => Navigator.of(context).pushNamed('/history/year'),
              icon: const Icon(Icons.calendar_month_outlined),
              label: const Text('View more logged days'),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () => Navigator.of(context).pushNamed('/stats'),
              icon: const Icon(Icons.insights_outlined),
              label: const Text('Stats'),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => Navigator.of(context).pushNamed('/history'),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: const [
                    Expanded(
                      child: Text(
                        'Browse exercise history',
                        style: TextStyle(
                          color: Colors.black87,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Icon(Icons.history, color: Colors.black87),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavBar(
        currentIndex: _selectedIndex,
        onTap: _onNavTap,
      ),
    );
  }
}
