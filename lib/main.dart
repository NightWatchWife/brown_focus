import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/pomodoro_providers.dart';
import 'screens/home_screen.dart';
import 'services/pomodoro_audio_handler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Boot the audio_service foreground-service infrastructure and build our
  // handler. This must happen before runApp so the provider override is ready.
  final handler = await AudioService.init(
    builder: () => PomodoroAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.arigassamaryota.brown_focus.audio',
      androidNotificationChannelName: 'Brown Focus',
      androidNotificationChannelDescription:
          'ポモドーロタイマーとブラウンノイズの再生',
      // While the timer is running we report playing=true, which keeps the
      // foreground service (and thus the process/timer/audio) alive. On pause
      // the foreground state is released so the notification can be dismissed.
      // audio_service requires ongoing=true to be paired with this flag.
      androidStopForegroundOnPause: true,
      androidNotificationOngoing: true,
    ),
  );

  runApp(
    ProviderScope(
      overrides: [
        audioHandlerProvider.overrideWithValue(handler),
      ],
      child: const BrownFocusApp(),
    ),
  );
}

class BrownFocusApp extends StatelessWidget {
  const BrownFocusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Brown Focus',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      theme: _buildDarkTheme(),
      darkTheme: _buildDarkTheme(),
      home: const HomeScreen(),
    );
  }

  ThemeData _buildDarkTheme() {
    const seed = Color(0xFF8D6E63); // warm brown accent
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF121212),
      colorScheme: ColorScheme.fromSeed(
        seedColor: seed,
        brightness: Brightness.dark,
      ),
      fontFamily: 'Roboto',
    );
  }
}
