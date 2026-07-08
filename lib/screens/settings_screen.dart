import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:gym_tracker/providers/theme_provider.dart';
import 'package:gym_tracker/screens/home_screen.dart';
import 'package:gym_tracker/services/db_helper.dart';
import 'package:gym_tracker/services/network_preferences.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    // Ensures the stored value is loaded so the switch below reflects it
    // right away (NetworkPreferences.allowMobileData defaults to true
    // until this resolves).
    NetworkPreferences().isMobileDataAllowed();
  }

  Future<void> _handleLogout() async {
    final pending = DBHelper().pendingSyncCount.value;
    if (pending > 0) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Unsynced changes'),
          content: Text(
            pending == 1
                ? 'You have 1 change that hasn\'t synced yet. '
                      'Logging out now will discard it. Log out anyway?'
                : 'You have $pending changes that haven\'t synced yet. '
                      'Logging out now will discard them. Log out anyway?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Log out anyway'),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }

    try {
      await DBHelper().clearLocalDataForCurrentUser();
      await Supabase.instance.client.auth.signOut();
      HomeScreen.clearCachedUsername();
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Theme',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          RadioGroup<ThemeMode>(
            groupValue: themeProvider.themeMode,
            onChanged: (value) {
              if (value != null) {
                context.read<ThemeProvider>().setThemeMode(value);
              }
            },
            child: const Column(
              children: [
                RadioListTile<ThemeMode>(
                  title: Text('Light'),
                  value: ThemeMode.light,
                ),
                RadioListTile<ThemeMode>(
                  title: Text('Dark'),
                  value: ThemeMode.dark,
                ),
                RadioListTile<ThemeMode>(
                  title: Text('System (Auto)'),
                  value: ThemeMode.system,
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          const Text(
            'Data usage',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<bool>(
            valueListenable: NetworkPreferences().allowMobileData,
            builder: (context, allowMobileData, _) {
              return SwitchListTile(
                title: const Text('Use mobile data'),
                subtitle: const Text(
                  'When off, syncing and loading only happens over Wi-Fi - '
                  'on mobile data the app behaves as if offline.',
                ),
                value: allowMobileData,
                onChanged: (value) {
                  NetworkPreferences().setMobileDataAllowed(value);
                },
              );
            },
          ),
          const SizedBox(height: 32),
          ListTile(
            title: const Text('Logout'),
            trailing: const Icon(Icons.logout),
            onTap: _handleLogout,
          ),
        ],
      ),
    );
  }
}
