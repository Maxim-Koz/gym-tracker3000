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
  bool _handledRouteTutorialArgs = false;
  bool _showTutorialOverlay = false;
  int _tutorialStep = 0;
  final GlobalKey _browseHistoryKey = GlobalKey();

  static const int _tutorialTotalSteps = 5;

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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_handledRouteTutorialArgs) return;
    _handledRouteTutorialArgs = true;

    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map && args['showTutorial'] == true) {
      final rawStartStep = args['tutorialStartStep'];
      final startStep = rawStartStep is int ? rawStartStep : 0;
      final safeStep = startStep.clamp(0, _tutorialTotalSteps - 1);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _tutorialStep = safeStep;
          _showTutorialOverlay = true;
        });
      });
      return;
    }

    if (args is Map && args['showHistoryTutorial'] == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _tutorialStep = 4;
          _showTutorialOverlay = true;
        });
      });
    }
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
      setState(() {
        _tutorialStep = 0;
        _showTutorialOverlay = true;
      });
    });
  }

  Future<void> _openGroupsTutorial({required int startStep}) async {
    if (_isTutorialFlowLaunching) return;
    _isTutorialFlowLaunching = true;
    if (!mounted) {
      _isTutorialFlowLaunching = false;
      return;
    }

    await Navigator.of(context).pushNamed(
      '/add_exercise',
      arguments: {'showTutorial': true, 'tutorialStartStep': startStep},
    );
    _isTutorialFlowLaunching = false;
  }

  void _closeTutorialOverlay() {
    if (!mounted) return;
    setState(() => _showTutorialOverlay = false);
  }

  void _onHomeTutorialPrimary() {
    if (_tutorialStep == 0) {
      _openGroupsTutorial(startStep: 1);
      return;
    }
    if (_tutorialStep == 4) {
      _closeTutorialOverlay();
    }
  }

  void _onHomeTutorialBack() {
    if (_tutorialStep == 4) {
      _openGroupsTutorial(startStep: 3);
    }
  }

  Widget _buildHomeTutorialOverlay() {
    final size = MediaQuery.of(context).size;
    final isWelcomeStep = _tutorialStep == 0;
    final isViewLogsStep = _tutorialStep == 4;
    final target = isViewLogsStep ? _rectForKey(_browseHistoryKey) : null;
    final title = isWelcomeStep ? 'Welcome Tutorial' : 'View Logs';
    final description = isWelcomeStep
        ? 'This tutorial will guide you through the main features of the app. Tap "Next" to continue.'
        : 'Tap on this button to view all your exercises past logs, as well as a graph to visualise your progress.';
    final primaryLabel = isWelcomeStep ? 'Next' : 'Done';

    return Positioned.fill(
      child: ColoredBox(
        color: TutorialThemeTokens.overlay,
        child: Stack(
          children: [
            if (target != null)
              Positioned(
                left: target.left - 4,
                top: target.top - 4,
                child: IgnorePointer(
                  child: Container(
                    width: target.width + 8,
                    height: target.height + 8,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: TutorialThemeTokens.border,
                        width: 2.5,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0xAA93C5FD),
                          blurRadius: 12,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            Align(
              alignment: isViewLogsStep
                  ? Alignment.topCenter
                  : Alignment.center,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  10,
                  isViewLogsStep ? 34 : 0,
                  10,
                  0,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 560,
                    maxHeight: (size.height * 0.24).clamp(140.0, 185.0),
                  ),
                  child: TutorialPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: TutorialThemeTokens.titleStyle),
                        const SizedBox(height: 6),
                        Text(description, style: TutorialThemeTokens.bodyStyle),
                        const Spacer(),
                        Row(
                          children: [
                            TextButton(
                              onPressed: _closeTutorialOverlay,
                              style: TextButton.styleFrom(
                                foregroundColor: TutorialThemeTokens.title,
                                textStyle: TutorialThemeTokens.buttonStyle,
                              ),
                              child: const Text('Skip'),
                            ),
                            Expanded(
                              child: Center(
                                child: TutorialDots(
                                  count: _tutorialTotalSteps,
                                  currentIndex: _tutorialStep,
                                ),
                              ),
                            ),
                            Row(
                              children: [
                                if (isViewLogsStep) ...[
                                  OutlinedButton(
                                    onPressed: _onHomeTutorialBack,
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(
                                        color: TutorialThemeTokens.border,
                                      ),
                                      foregroundColor:
                                          TutorialThemeTokens.title,
                                      textStyle:
                                          TutorialThemeTokens.buttonStyle,
                                    ),
                                    child: const Text('Back'),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                FilledButton(
                                  onPressed: _onHomeTutorialPrimary,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: TutorialThemeTokens.button,
                                    foregroundColor: Colors.white,
                                    textStyle: TutorialThemeTokens.buttonStyle,
                                  ),
                                  child: Text(primaryLabel),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Rect? _rectForKey(GlobalKey key) {
    final targetContext = key.currentContext;
    if (targetContext == null) return null;
    final renderObject = targetContext.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return null;
    final origin = renderObject.localToGlobal(Offset.zero);
    return origin & renderObject.size;
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
    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            toolbarHeight: 100,
            title: Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Text(
                'Hello, $_username',
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
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
                  onPressed: () =>
                      Navigator.of(context).pushNamed('/history/year'),
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
                  key: _browseHistoryKey,
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
        ),
        if (_showTutorialOverlay) _buildHomeTutorialOverlay(),
      ],
    );
  }
}
