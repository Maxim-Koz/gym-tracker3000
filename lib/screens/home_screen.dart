import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:gym_tracker/services/db_helper.dart';
import 'package:gym_tracker/widgets/bottom_nav_bar.dart';
import 'package:gym_tracker/widgets/workout_calendar.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  // Call this on logout so a different account signing in afterwards
  // doesn't briefly show the previous user's cached username.
  static void clearCachedUsername() {
    _HomeScreenState._cachedUsername = null;
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
  late String _username = _cachedUsername ?? 'there';
  Set<DateTime> _loggedDates = <DateTime>{};

  @override
  void initState() {
    super.initState();
    _loadUsername();
    _loadLoggedDates();
  }

  Future<void> _loadUsername() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

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
      if (!mounted) return;
      setState(() {
        _username = username!;
      });
    } else if (user.email != null) {
      final fallback = user.email!.split('@').first;
      _cachedUsername = fallback;
      if (!mounted) return;
      setState(() {
        _username = fallback;
      });
    }
  }

  Future<void> _loadLoggedDates() async {
    final dates = await DBHelper().getLoggedDates();
    if (!mounted) return;
    setState(() => _loggedDates = dates.toSet());
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
