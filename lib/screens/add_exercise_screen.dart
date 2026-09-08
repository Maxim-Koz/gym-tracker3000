import 'package:flutter/material.dart';
import 'package:gym_tracker/widgets/bottom_nav_bar.dart';
import 'package:gym_tracker/services/db_helper.dart';
import 'package:gym_tracker/services/exercise_grouping.dart';
import 'package:gym_tracker/widgets/tutorial_theme.dart';

class AddExerciseScreen extends StatefulWidget {
  const AddExerciseScreen({super.key});

  @override
  State<AddExerciseScreen> createState() => _AddExerciseScreenState();
}

class _AddExerciseScreenState extends State<AddExerciseScreen> {
  int _selectedIndex = 1;
  List<Map<String, dynamic>> _exercises = [];
  List<String> _knownGroupNames = const <String>[];
  List<String> _groupNameOrder = const <String>[];
  final TextEditingController _searchController = TextEditingController();
  final GlobalKey _addGroupButtonKey = GlobalKey();
  final GlobalKey _addExerciseButtonKey = GlobalKey();
  final GlobalKey _groupListKey = GlobalKey();
  final GlobalKey _firstGroupCardKey = GlobalKey();
  final PageController _tutorialPageController = PageController();
  String _searchQuery = '';
  bool _showTutorial = false;
  bool _handledTutorialArgs = false;
  int _tutorialStep = 0;
  bool _isTutorialNavigating = false;

  static const int _tutorialSteps = 5;

  @override
  void initState() {
    super.initState();
    _loadExercises();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_handledTutorialArgs) return;
    _handledTutorialArgs = true;

    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map && args['showTutorial'] == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final rawStartStep = args['tutorialStartStep'];
        final startStep = rawStartStep is int ? rawStartStep : 0;
        final safeStartStep = startStep.clamp(1, 3);
        setState(() {
          _tutorialStep = safeStartStep;
          _showTutorial = true;
        });
        _tutorialPageController.jumpToPage(safeStartStep - 1);
      });
    }
  }

  Future<void> _loadExercises() async {
    final list = await DBHelper().getExercises();
    final groupNames = await loadExerciseGroupNames(list);
    final groupNameOrder = await loadExerciseGroupNameOrder();
    if (!mounted) return;
    setState(() {
      _exercises = list;
      _knownGroupNames = groupNames;
      _groupNameOrder = groupNameOrder.isNotEmpty ? groupNameOrder : groupNames;
    });
  }

  Future<void> _openNewGroupScreen() async {
    final result = await Navigator.of(context).pushNamed('/new_group');
    if (result == true && mounted) {
      await _loadExercises();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tutorialPageController.dispose();
    super.dispose();
  }

  Rect? _rectForKey(GlobalKey key) {
    final targetContext = key.currentContext;
    if (targetContext == null) return null;
    final renderObject = targetContext.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return null;
    final origin = renderObject.localToGlobal(Offset.zero);
    return origin & renderObject.size;
  }

  void _setTutorialStep(int step) {
    if (step < 0 || step >= _tutorialSteps) return;

    if (step == 0) {
      _showWelcomeOnHome();
      return;
    }

    if (step == 4) {
      _showHistoryButtonOnHome();
      return;
    }

    _tutorialPageController.animateToPage(
      step - 1,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
    setState(() => _tutorialStep = step);
  }

  void _finishTutorial() {
    if (!mounted) return;
    setState(() => _showTutorial = false);
  }

  void _showWelcomeOnHome() {
    if (!mounted || _isTutorialNavigating) return;
    _isTutorialNavigating = true;
    setState(() => _showTutorial = false);
    Navigator.of(context).pushReplacementNamed(
      '/home',
      arguments: {'showTutorial': true, 'tutorialStartStep': 0},
    );
    _isTutorialNavigating = false;
  }

  void _showHistoryButtonOnHome() {
    if (!mounted || _isTutorialNavigating) return;
    _isTutorialNavigating = true;
    setState(() => _showTutorial = false);
    Navigator.of(context).pushReplacementNamed(
      '/home',
      arguments: {'showTutorial': true, 'tutorialStartStep': 4},
    );
    _isTutorialNavigating = false;
  }

  Widget _buildTutorialCard({
    required String title,
    required String description,
  }) {
    final isLastGroupsStep = _tutorialStep == 3;
    final canGoBack = _tutorialStep > 0;

    return TutorialPanel(
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TutorialThemeTokens.titleStyle),
                const SizedBox(height: 8),
                Text(description, style: TutorialThemeTokens.bodyStyle),
                const SizedBox(height: 14),
                Row(
                  children: [
                    TextButton(
                      onPressed: _finishTutorial,
                      style: TextButton.styleFrom(
                        foregroundColor: TutorialThemeTokens.title,
                        textStyle: TutorialThemeTokens.buttonStyle,
                      ),
                      child: const Text('Skip'),
                    ),
                    Expanded(
                      child: Center(
                        child: TutorialDots(
                          count: _tutorialSteps,
                          currentIndex: _tutorialStep,
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        if (canGoBack)
                          OutlinedButton(
                            onPressed: () =>
                                _setTutorialStep(_tutorialStep - 1),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(
                                color: TutorialThemeTokens.border,
                              ),
                              foregroundColor: TutorialThemeTokens.title,
                              textStyle: TutorialThemeTokens.buttonStyle,
                            ),
                            child: const Text('Back'),
                          ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: () => _setTutorialStep(_tutorialStep + 1),
                          style: FilledButton.styleFrom(
                            backgroundColor: TutorialThemeTokens.button,
                            foregroundColor: Colors.white,
                            textStyle: TutorialThemeTokens.buttonStyle,
                          ),
                          child: Text(isLastGroupsStep ? 'Next' : 'Next'),
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
    );
  }

  Widget _buildTutorialPointer({required Rect target, required String label}) {
    final size = MediaQuery.of(context).size;
    final bubbleWidth = (size.width - 56).clamp(220.0, 420.0);
    final bubbleLeft = 16.0;
    final desiredBubbleTop = target.bottom + 8;
    final maxBubbleTop = size.height - 120;
    final bubbleTop = desiredBubbleTop > maxBubbleTop
        ? maxBubbleTop
        : desiredBubbleTop;

    return Stack(
      children: [
        Positioned(
          left: target.left - 4,
          top: target.top - 4,
          child: IgnorePointer(
            child: Container(
              width: target.width + 8,
              height: target.height + 8,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
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
        Positioned(
          left: target.center.dx - 12,
          top: target.bottom + 2,
          child: const Icon(
            Icons.arrow_drop_up,
            color: TutorialThemeTokens.border,
            size: 30,
          ),
        ),
        Positioned(
          left: bubbleLeft,
          top: bubbleTop,
          child: Container(
            width: bubbleWidth,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A).withValues(alpha: 0.96),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: TutorialThemeTokens.border.withValues(alpha: 0.35),
              ),
            ),
            child: Text(label, style: TutorialThemeTokens.bodyStyle),
          ),
        ),
      ],
    );
  }

  Widget _buildTutorialOverlay() {
    final size = MediaQuery.of(context).size;
    final tutorialCardHeight = (size.height * 0.26).clamp(150.0, 190.0);

    final addExerciseRect = _rectForKey(_addExerciseButtonKey);
    final addGroupRect = _rectForKey(_addGroupButtonKey);
    final listRect = _rectForKey(_groupListKey);
    final firstGroupRect = _rectForKey(_firstGroupCardKey);

    final cards = <Map<String, String>>[
      {
        'title': 'Add Exercise',
        'description':
            'Use this button to create a new exercise. Give it a name and optionally assign groups.',
      },
      {
        'title': 'Add Group',
        'description':
            'Use this button to create a group and organize your exercises.',
      },
      {
        'title': 'Log Workouts',
        'description':
            'Open any group, then tap an exercise to record sets and save a session log.',
      },
    ];

    return Positioned.fill(
      child: ColoredBox(
        color: TutorialThemeTokens.overlay,
        child: SafeArea(
          child: Stack(
            children: [
              if (_tutorialStep == 1 && addExerciseRect != null)
                _buildTutorialPointer(
                  target: addExerciseRect,
                  label: 'Tap here to add a new exercise.',
                ),
              if (_tutorialStep == 2 && addGroupRect != null)
                _buildTutorialPointer(
                  target: addGroupRect,
                  label: 'Tap here to create a new group.',
                ),
              if (_tutorialStep == 3 && listRect != null)
                _buildTutorialPointer(
                  target:
                      firstGroupRect ??
                      Rect.fromLTWH(
                        listRect.left + 8,
                        listRect.top + 8,
                        listRect.width - 16,
                        52,
                      ),
                  label:
                      'After creating items, tap a group card and then an exercise to log your workout.',
                ),
              Align(
                alignment: _tutorialStep == 1
                    ? Alignment.bottomCenter
                    : _tutorialStep == 2
                    ? Alignment.bottomCenter
                    : _tutorialStep == 3
                    ? Alignment.topCenter
                    : Alignment.center,
                child: Padding(
                  padding: EdgeInsets.only(
                    left: 8,
                    right: 8,
                    top: _tutorialStep == 3 ? 12 : 0,
                    bottom: _tutorialStep == 1 || _tutorialStep == 2 ? 16 : 0,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: SizedBox(
                      height: tutorialCardHeight.toDouble(),
                      child: PageView(
                        controller: _tutorialPageController,
                        onPageChanged: (index) {
                          if (!mounted) return;
                          setState(() => _tutorialStep = index + 1);
                        },
                        children: [
                          for (var i = 0; i < cards.length; i++)
                            _buildTutorialCard(
                              title: cards[i]['title']!,
                              description: cards[i]['description']!,
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
      ),
    );
  }

  List<ExerciseGroupSection> get _filteredSections {
    final query = _searchQuery.trim().toLowerCase();
    final sections = buildExerciseGroupSections(
      _exercises,
      extraGroupNames: _knownGroupNames,
      groupNameOrder: _groupNameOrder,
    );
    if (query.isEmpty) return sections;
    return sections
        .where((section) => section.name.toLowerCase().contains(query))
        .toList();
  }

  Future<void> _reorderGroupNamesByIndex(int oldIndex, int newIndex) async {
    final orderedNames = List<String>.from(
      _groupNameOrder.isNotEmpty ? _groupNameOrder : _knownGroupNames,
    );
    if (oldIndex < 0 || oldIndex >= orderedNames.length) return;
    if (newIndex < 0 || newIndex > orderedNames.length) return;

    final moved = orderedNames.removeAt(oldIndex);
    if (newIndex > orderedNames.length) {
      orderedNames.add(moved);
    } else {
      orderedNames.insert(newIndex, moved);
    }

    setState(() {
      _knownGroupNames = orderedNames;
      _groupNameOrder = orderedNames;
    });

    try {
      await saveExerciseGroupNameOrder(orderedNames);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save group order: $e')));
    }
  }

  void _onNavTap(int index) {
    setState(() {
      _selectedIndex = index;
    });

    switch (index) {
      case 0:
        Navigator.of(context).pushNamed('/home');
        break;
      case 1:
        break;
      case 2:
        Navigator.of(context).pushNamed('/weight');
        break;
      case 3:
        Navigator.of(context).pushNamed('/settings');
        break;
    }
  }

  Widget _buildGroupCard(ExerciseGroupSection section, {Key? cardKey}) {
    return Padding(
      key: cardKey ?? ValueKey(section.name),
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: ListTile(
          title: Text(section.name),
          subtitle: Text(
            '${section.exercises.length} exercise${section.exercises.length == 1 ? '' : 's'}',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            await Navigator.of(
              context,
            ).pushNamed('/exercise_groups', arguments: section.name);
            if (mounted) _loadExercises();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sections = _filteredSections;
    final customSections = sections
        .where((section) => section.name != 'All Exercises')
        .toList();
    final allExercisesSection = sections
        .where((section) => section.name == 'All Exercises')
        .toList();
    final canReorder = _searchQuery.trim().isEmpty;

    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            title: const Text('Groups'),
            automaticallyImplyLeading: false,
            actions: [
              IconButton(
                key: _addGroupButtonKey,
                tooltip: 'Add group',
                icon: const Icon(Icons.grid_view),
                onPressed: _openNewGroupScreen,
              ),
              IconButton(
                key: _addExerciseButtonKey,
                tooltip: 'Add exercise',
                icon: const Icon(Icons.add_circle_outline),
                onPressed: () async {
                  final res = await Navigator.of(
                    context,
                  ).pushNamed('/new_exercise');
                  if (res == true) _loadExercises();
                },
              ),
            ],
          ),
          body: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              children: [
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      hintText: 'Search groups',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                      });
                    },
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  key: _groupListKey,
                  child: _exercises.isEmpty && _knownGroupNames.isEmpty
                      ? const Center(
                          child: Text('No exercises yet. Tap + to add.'),
                        )
                      : sections.isEmpty
                      ? const Center(
                          child: Text('No groups match your search.'),
                        )
                      : Column(
                          children: [
                            for (final section in allExercisesSection)
                              _buildGroupCard(section),
                            Expanded(
                              child: customSections.isEmpty
                                  ? const SizedBox.shrink()
                                  : canReorder
                                  ? ReorderableListView.builder(
                                      itemCount: customSections.length,
                                      onReorderItem:
                                          (oldIndex, newIndex) async {
                                            if (oldIndex < 0 ||
                                                oldIndex >=
                                                    customSections.length ||
                                                newIndex < 0 ||
                                                newIndex >
                                                    customSections.length) {
                                              return;
                                            }
                                            await _reorderGroupNamesByIndex(
                                              oldIndex,
                                              newIndex,
                                            );
                                          },
                                      itemBuilder: (context, index) =>
                                          _buildGroupCard(
                                            customSections[index],
                                            cardKey: index == 0
                                                ? _firstGroupCardKey
                                                : null,
                                          ),
                                    )
                                  : ListView.builder(
                                      itemCount: customSections.length,
                                      itemBuilder: (context, index) =>
                                          _buildGroupCard(
                                            customSections[index],
                                            cardKey: index == 0
                                                ? _firstGroupCardKey
                                                : null,
                                          ),
                                    ),
                            ),
                          ],
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
        if (_showTutorial) _buildTutorialOverlay(),
      ],
    );
  }
}
