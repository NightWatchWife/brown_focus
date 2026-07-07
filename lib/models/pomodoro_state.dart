import 'package:flutter/foundation.dart';

/// The kind of phase the Pomodoro timer is currently in.
enum PomodoroPhase {
  focus, // 集中時間 (25 min)
  shortBreak, // 短い休憩 (5 min)
  longBreak, // 長い休憩 (20 min)
}

extension PomodoroPhaseX on PomodoroPhase {
  /// Japanese label shown in the UI / notification.
  String get label {
    switch (this) {
      case PomodoroPhase.focus:
        return '集中時間';
      case PomodoroPhase.shortBreak:
        return '短い休憩';
      case PomodoroPhase.longBreak:
        return '長い休憩';
    }
  }

  bool get isFocus => this == PomodoroPhase.focus;
  bool get isBreak => !isFocus;
}

/// Immutable snapshot of the timer that the UI renders.
@immutable
class PomodoroData {
  const PomodoroData({
    required this.phase,
    required this.cycle,
    required this.totalCycles,
    required this.remainingSeconds,
    required this.totalSeconds,
    required this.isRunning,
    required this.noiseEnabled,
    required this.volume,
  });

  final PomodoroPhase phase;

  /// 1-based index of the current focus/short-break cycle (1..totalCycles).
  final int cycle;
  final int totalCycles;

  final int remainingSeconds;
  final int totalSeconds;

  /// Whether the countdown is actively ticking.
  final bool isRunning;

  /// Whether the brown noise plays while the timer runs. When false the app is
  /// a plain Pomodoro timer with only the countdown sound.
  final bool noiseEnabled;

  /// Background-noise volume, 0.0–1.0.
  final double volume;

  /// 0.0 – 1.0 progress through the current phase.
  double get progress {
    if (totalSeconds <= 0) return 0;
    return (totalSeconds - remainingSeconds) / totalSeconds;
  }

  /// "MM:SS" for the remaining time.
  String get formattedRemaining {
    final m = (remainingSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (remainingSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  PomodoroData copyWith({
    PomodoroPhase? phase,
    int? cycle,
    int? totalCycles,
    int? remainingSeconds,
    int? totalSeconds,
    bool? isRunning,
    bool? noiseEnabled,
    double? volume,
  }) {
    return PomodoroData(
      phase: phase ?? this.phase,
      cycle: cycle ?? this.cycle,
      totalCycles: totalCycles ?? this.totalCycles,
      remainingSeconds: remainingSeconds ?? this.remainingSeconds,
      totalSeconds: totalSeconds ?? this.totalSeconds,
      isRunning: isRunning ?? this.isRunning,
      noiseEnabled: noiseEnabled ?? this.noiseEnabled,
      volume: volume ?? this.volume,
    );
  }
}
