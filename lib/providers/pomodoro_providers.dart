import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/pomodoro_state.dart';
import '../services/pomodoro_audio_handler.dart';

/// Holds the singleton handler. Overridden in `main()` once `AudioService.init`
/// has created it, so the rest of the app can read it synchronously.
final audioHandlerProvider = Provider<PomodoroAudioHandler>((ref) {
  throw UnimplementedError(
    'audioHandlerProvider must be overridden in main() with the initialised '
    'PomodoroAudioHandler.',
  );
});

/// Streams the live Pomodoro snapshot to the UI.
final pomodoroProvider = StreamProvider<PomodoroData>((ref) {
  final handler = ref.watch(audioHandlerProvider);
  return handler.pomodoroStream;
});
