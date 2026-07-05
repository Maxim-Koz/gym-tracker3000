import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:gym_tracker/services/db_helper.dart';
import 'package:gym_tracker/widgets/bottom_nav_bar.dart';
import 'package:gym_tracker/widgets/workout_calendar.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  String _username = 'there';
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
      setState(() {
        _username = username!;
      });
    } else if (user.email != null) {
      setState(() {
        _username = user.email!.split('@').first;
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
        title: Text('Hello, $_username'),
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
            const SizedBox(height: 24),
            const Text(
              'Tap the tab bar below to add or configure exercises.',
              style: TextStyle(color: Colors.white70),
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
