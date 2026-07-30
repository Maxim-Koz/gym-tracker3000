import 'package:flutter/material.dart';

/// App-wide bottom navigation: Home, Add Exercise, Weight, Settings.
///
/// NOTE: this file was not part of the uploaded project - your real
/// bottom_nav_bar.dart may already exist with different styling/icons. If
/// so, just add the 'Weight' BottomNavigationBarItem below in the same
/// position (index 2, between Add Exercise and Settings) rather than
/// replacing the whole file.
class BottomNavBar extends StatelessWidget {
  const BottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: currentIndex,
      onTap: onTap,
      type: BottomNavigationBarType.fixed,
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.home_outlined),
          activeIcon: Icon(Icons.home),
          label: 'Home',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.add_circle_outline),
          activeIcon: Icon(Icons.add_circle),
          label: 'Add',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.monitor_weight_outlined),
          activeIcon: Icon(Icons.monitor_weight),
          label: 'Weight',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.settings_outlined),
          activeIcon: Icon(Icons.settings),
          label: 'Settings',
        ),
      ],
    );
  }
}
