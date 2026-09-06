import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:gym_tracker/services/data_migration_service.dart';
import 'package:gym_tracker/services/db_helper.dart';
import 'package:gym_tracker/widgets/bottom_nav_bar.dart';
import 'package:gym_tracker/widgets/tutorial_theme.dart';
import 'package:gym_tracker/widgets/workout_calendar.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  static void clearCachedUsername({String? userId}) {
    _HomeScreenState._cachedUsername = null;
    _HomeScreenState._clearPersistedUsername(userId: userId);
  }

  static String _miniTutorialSeenKey(String userId) =>
      'mini_tutorial_seen_$userId';

  static Future<void> resetMiniTutorialSeen({String? userId}) async {
    final resolvedUserId =
        userId ?? Supabase.instance.client.auth.currentUser?.id;
    if (resolvedUserId == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_miniTutorialSeenKey(resolvedUserId));
  }

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static String? _cachedUsername;

  int _selectedIndex = 0;
  String _username = 'there';
  Set<DateTime> _loggedDates = <DateTime>{};
  bool _isTutorialFlowLaunching = false;

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

  static Future<void> _clearPersistedUsername({String? userId}) async {
    final prefs = await SharedPreferences.getInstance();
    final resolvedUserId =
        userId ?? Supabase.instance.client.auth.currentUser?.id;
    if (resolvedUserId == null) return;
    await prefs.remove(_usernameKey(resolvedUserId));
  }

  @override
  void initState() {
    super.initState();
    _loadUsername();
    DataMigrationService().migrateIfNeeded();
    _loadLoggedDates();
    _maybeShowMiniTutorial();
  }

  Future<void> _maybeShowMiniTutorial() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    final prefs = await SharedPreferences.getInstance();
    final seen =
        prefs.getBool(HomeScreen._miniTutorialSeenKey(userId)) ?? false;
    if (seen) return;

    await prefs.setBool(HomeScreen._miniTutorialSeenKey(userId), true);
    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isTutorialFlowLaunching) return;
      _startMiniTutorialFlow();
    });
  }

  Future<void> _startMiniTutorialFlow() async {
    if (_isTutorialFlowLaunching) return;
    _isTutorialFlowLaunching = true;
    final shouldStart = await _showTutorialIntroDialog();
    if (!mounted || shouldStart != true) {
      _isTutorialFlowLaunching = false;
      return;
    }
    await Navigator.of(context).pushNamed(
      '/add_exercise',
      arguments: {'showTutorial': true, 'tutorialStartStep': 0},
    );
    _isTutorialFlowLaunching = false;
  }

  Future<bool?> _showTutorialIntroDialog() {
    return showGeneralDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Tutorial intro',
      barrierColor: TutorialThemeTokens.overlay,
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        final width = MediaQuery.of(dialogContext).size.width;
        return SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: width > 640 ? 560 : width - 20,
              ),
              child: TutorialPanel(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Welcome Tutorial',
                      style: TutorialThemeTokens.titleStyle,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'This short tutorial will walk you through groups, exercises, '
                      'logging a workout, and where to view your logs.',
                      style: TutorialThemeTokens.bodyStyle,
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(false),
                          style: TextButton.styleFrom(
                            foregroundColor: TutorialThemeTokens.title,
                            textStyle: TutorialThemeTokens.buttonStyle,
                          ),
                          child: const Text('Skip'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(true),
                          style: FilledButton.styleFrom(
                            backgroundColor: TutorialThemeTokens.button,
                            foregroundColor: Colors.white,
                            textStyle: TutorialThemeTokens.buttonStyle,
                          ),
                          child: const Text('Start'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
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
    } catch (_) {}
  }

  void _onNavTap(int index) {
    setState(() {
      _selectedIndex = index;
    });

    switch (index) {
      case 0:
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
            WorkoutCalendar(
              month: DateTime.now(),
              loggedDates: _loggedDates,
              onDateSelected: (date) {
                Navigator.of(
                  context,
                ).pushNamed('/history/day', arguments: {'date': date});
              },
            ),
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
