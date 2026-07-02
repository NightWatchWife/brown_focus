/// Central place for all tunable Pomodoro / audio settings.
class PomodoroConfig {
  const PomodoroConfig._();

  // Phase durations (in seconds). Tweak these to change the whole cycle.
  static const int focusSeconds = 25 * 60; // 集中: 25 min
  static const int shortBreakSeconds = 5 * 60; // 短い休憩: 5 min
  static const int longBreakSeconds = 20 * 60; // 長い休憩: 20 min

  /// Focus + short-break repetitions before a long break kicks in.
  static const int cyclesBeforeLongBreak = 4;

  /// How many seconds before a phase ends we start the "3・2・1" countdown SFX.
  static const int countdownLeadSeconds = 3;

  // Asset paths (declared in pubspec.yaml under assets/audio/).
  static const String brownNoiseAsset = 'assets/audio/brown_noise.mp3';
  static const String countdownAsset = 'assets/audio/countdown.mp3';
}
