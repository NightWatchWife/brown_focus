// Basic smoke test for the Pomodoro model.

import 'package:brown_focus/config.dart';
import 'package:brown_focus/models/pomodoro_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('initial focus phase formats remaining time as 25:00', () {
    const data = PomodoroData(
      phase: PomodoroPhase.focus,
      cycle: 1,
      totalCycles: PomodoroConfig.cyclesBeforeLongBreak,
      remainingSeconds: PomodoroConfig.focusSeconds,
      totalSeconds: PomodoroConfig.focusSeconds,
      isRunning: false,
      noiseEnabled: true,
      volume: 0.8,
    );

    expect(data.formattedRemaining, '25:00');
    expect(data.phase.label, '集中時間');
    expect(data.progress, 0.0);
  });

  test('progress reflects elapsed time', () {
    const data = PomodoroData(
      phase: PomodoroPhase.shortBreak,
      cycle: 1,
      totalCycles: 4,
      remainingSeconds: 150,
      totalSeconds: 300,
      isRunning: true,
      noiseEnabled: false,
      volume: 0.8,
    );

    expect(data.progress, 0.5);
    expect(data.formattedRemaining, '02:30');
  });
}
