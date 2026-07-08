import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:gym_tracker/screens/login_screen.dart';
import 'package:gym_tracker/screens/home_screen.dart';
import 'package:gym_tracker/screens/signup_screen.dart';
import 'package:gym_tracker/screens/add_exercise_screen.dart';
import 'package:gym_tracker/screens/new_exercise_screen.dart';
import 'package:gym_tracker/screens/record_exercise_screen.dart';
import 'package:gym_tracker/screens/log_session_screen.dart';
import 'package:gym_tracker/screens/settings_screen.dart';
import 'package:gym_tracker/screens/history_screen.dart';
import 'package:gym_tracker/screens/exercise_history_screen.dart';
import 'package:gym_tracker/screens/year_history_screen.dart';
import 'package:gym_tracker/screens/workout_stats_screen.dart';
import 'package:gym_tracker/providers/theme_provider.dart';
import 'package:gym_tracker/services/sync_service.dart';

final lightTheme = ThemeData(
  brightness: Brightness.light,
  colorScheme: ColorScheme.fromSeed(
    seedColor: Colors.blue,
    brightness: Brightness.light,
  ),
  textSelectionTheme: const TextSelectionThemeData(cursorColor: Colors.black),
  useMaterial3: true,
);

final darkTheme = ThemeData(
  brightness: Brightness.dark,
  colorScheme: ColorScheme.fromSeed(
    seedColor: Colors.blue,
    brightness: Brightness.dark,
  ),
  textSelectionTheme: const TextSelectionThemeData(cursorColor: Colors.white),
  useMaterial3: true,
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://bztpiuywbgfivichfkyg.supabase.co',
    publishableKey: 'sb_publishable_mNNITpH_jYrlJpOlFoWJSA_Ncem4MEV',
  );

  // Retries any queued offline writes in the background for as long as the
  // app is running, so they go out automatically once the network is back.
  SyncService().start();

  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final session = Supabase.instance.client.auth.currentSession;
    final themeMode = context.watch<ThemeProvider>().themeMode;

    return MaterialApp(
      title: 'SupaBase auth',
      // Add this line right here:
      scaffoldMessengerKey: SyncService.messengerKey,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: themeMode,
      initialRoute: session != null ? '/home' : '/',
      routes: {
        '/': (context) => const LoginScreen(),
        '/signup': (context) => const SignupScreen(),
        '/home': (context) => const HomeScreen(),
        '/add_exercise': (context) => const AddExerciseScreen(),
        '/new_exercise': (context) => const NewExerciseScreen(),
        '/record_exercise': (context) => const RecordExerciseScreen(),
        '/log_session': (context) => const LogSessionScreen(),
        '/history': (context) => const HistoryScreen(),
        '/history/exercise': (context) => const ExerciseHistoryScreen(),
        '/history/year': (context) => const YearHistoryScreen(),
        '/stats': (context) => const WorkoutStatsScreen(),
        '/settings': (context) => const SettingsScreen(),
      },
    );
  }
}
