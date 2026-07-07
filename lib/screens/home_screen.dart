import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/pomodoro_state.dart';
import '../providers/pomodoro_providers.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _requestPermissions());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back to the foreground: re-assert playback so a loop or ticker
    // that stopped while backgrounded recovers instead of leaving the UI stuck.
    if (state == AppLifecycleState.resumed) {
      ref.read(audioHandlerProvider).resyncPlayback();
    }
  }

  Future<void> _requestPermissions() async {
    // Android-only: permission_handler's battery/notification permissions are
    // unsupported on web/desktop and would throw, so bail out elsewhere.
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

    // Ongoing notification (Android 13+).
    await Permission.notification.request();
    // Ask the user to exempt the app from battery optimization so the OS does
    // not kill background playback. Only prompts if not already granted.
    if (await Permission.ignoreBatteryOptimizations.isDenied) {
      await Permission.ignoreBatteryOptimizations.request();
    }
  }

  @override
  Widget build(BuildContext context) {
    final asyncState = ref.watch(pomodoroProvider);
    final handler = ref.read(audioHandlerProvider);

    return Scaffold(
      body: SafeArea(
        child: asyncState.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('エラー: $e')),
          data: (state) => _Content(
            state: state,
            onStart: handler.play,
            onPause: handler.pause,
            onReset: handler.reset,
            onToggleNoise: handler.setNoiseEnabled,
            onSelectCycle: handler.jumpToCycle,
            onVolume: handler.setVolume,
          ),
        ),
      ),
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({
    required this.state,
    required this.onStart,
    required this.onPause,
    required this.onReset,
    required this.onToggleNoise,
    required this.onSelectCycle,
    required this.onVolume,
  });

  final PomodoroData state;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onReset;
  final ValueChanged<bool> onToggleNoise;
  final ValueChanged<int> onSelectCycle;
  final ValueChanged<double> onVolume;

  Color get _accent {
    switch (state.phase) {
      case PomodoroPhase.focus:
        return const Color(0xFFD7A86E); // warm brown/amber
      case PomodoroPhase.shortBreak:
        return const Color(0xFF4DB6AC); // teal
      case PomodoroPhase.longBreak:
        return const Color(0xFF7986CB); // indigo
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          const SizedBox(height: 24),
          _Header(state: state, accent: _accent, onSelectCycle: onSelectCycle),
          const Spacer(),
          _TimerRing(state: state, accent: _accent),
          const Spacer(),
          _Controls(
            isRunning: state.isRunning,
            noiseEnabled: state.noiseEnabled,
            accent: _accent,
            onStart: onStart,
            onPause: onPause,
            onReset: onReset,
            onToggleNoise: onToggleNoise,
          ),
          const SizedBox(height: 14),
          Text(
            state.noiseEnabled
                ? 'ブラウンノイズ ON'
                : 'ブラウンノイズ OFF ・ カウントダウンのみ',
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 13,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 10),
          // Keep the volume bar compact and centered (Spotify-like) rather than
          // stretching edge-to-edge on wide/web layouts.
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: _VolumeBar(
                volume: state.volume,
                accent: _accent,
                enabled: state.noiseEnabled,
                onChanged: onVolume,
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// Horizontal volume control for the background noise.
class _VolumeBar extends StatelessWidget {
  const _VolumeBar({
    required this.volume,
    required this.accent,
    required this.enabled,
    required this.onChanged,
  });

  final double volume;
  final Color accent;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final active = enabled ? accent : Colors.white.withOpacity(0.25);
    final icon = volume <= 0.01
        ? Icons.volume_off_rounded
        : volume < 0.5
            ? Icons.volume_down_rounded
            : Icons.volume_up_rounded;
    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: Row(
        children: [
          Icon(icon, size: 22, color: Colors.white.withOpacity(0.7)),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 4,
                activeTrackColor: active,
                inactiveTrackColor: Colors.white.withOpacity(0.12),
                thumbColor: active,
                overlayColor: accent.withOpacity(0.18),
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 8),
                overlayShape:
                    const RoundSliderOverlayShape(overlayRadius: 16),
              ),
              child: Slider(
                value: volume.clamp(0.0, 1.0),
                onChanged: enabled ? onChanged : null,
              ),
            ),
          ),
          SizedBox(
            width: 38,
            child: Text(
              '${(volume * 100).round()}%',
              textAlign: TextAlign.end,
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 13,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.state,
    required this.accent,
    required this.onSelectCycle,
  });

  final PomodoroData state;
  final Color accent;
  final ValueChanged<int> onSelectCycle;

  Future<void> _maybeJump(BuildContext context, int target) async {
    // Tapping the current focus cycle does nothing.
    if (target == state.cycle && state.phase == PomodoroPhase.focus) return;

    // Only confirm when a session is under way (running, or the current phase
    // has already progressed). A fresh, paused timer jumps instantly so you can
    // pick a starting cycle before you begin.
    final inProgress = state.isRunning ||
        state.remainingSeconds != state.totalSeconds ||
        state.phase != PomodoroPhase.focus;
    if (!inProgress) {
      onSelectCycle(target);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.6),
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text(
          'サイクルを移動しますか？',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        content: Text(
          '$target サイクル目の集中（25:00）に移動します。今の経過はなくなります。',
          style: TextStyle(color: Colors.white.withOpacity(0.7), height: 1.5),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white.withOpacity(0.7),
            ),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: accent),
            child: const Text(
              '移動',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) onSelectCycle(target);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Phase pill
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          decoration: BoxDecoration(
            color: accent.withOpacity(0.15),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: accent.withOpacity(0.5)),
          ),
          child: Text(
            state.phase.label,
            style: TextStyle(
              color: accent,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Cycle dots — tap a dot to jump to that cycle's focus block.
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (int i = 1; i <= state.totalCycles; i++)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _maybeJump(context, i),
                child: Padding(
                  // Generous padding = larger, finger-friendly tap target.
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: i == state.cycle ? 22 : 12,
                    height: 12,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      color: i <= state.cycle
                          ? accent
                          : Colors.white.withOpacity(0.18),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '${state.cycle} / ${state.totalCycles} サイクル目 ・ タップで移動',
          style: TextStyle(
            color: Colors.white.withOpacity(0.55),
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}

class _TimerRing extends StatelessWidget {
  const _TimerRing({required this.state, required this.accent});

  final PomodoroData state;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 280,
      height: 280,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.expand(
            child: CustomPaint(
              painter: _RingPainter(
                progress: state.progress,
                accent: accent,
                track: Colors.white.withOpacity(0.08),
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                state.formattedRemaining,
                style: const TextStyle(
                  fontSize: 64,
                  fontWeight: FontWeight.w300,
                  color: Colors.white,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                state.isRunning ? '再生中' : '一時停止中',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 14,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.accent,
    required this.track,
  });

  final double progress;
  final Color accent;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 14.0;
    final center = size.center(Offset.zero);
    final radius = (size.width - stroke) / 2;

    final trackPaint = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, trackPaint);

    final progressPaint = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    const start = -math.pi / 2; // 12 o'clock
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      start,
      2 * math.pi * progress.clamp(0.0, 1.0),
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.accent != accent;
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.isRunning,
    required this.noiseEnabled,
    required this.accent,
    required this.onStart,
    required this.onPause,
    required this.onReset,
    required this.onToggleNoise,
  });

  final bool isRunning;
  final bool noiseEnabled;
  final Color accent;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onReset;
  final ValueChanged<bool> onToggleNoise;

  Future<void> _confirmReset(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.6),
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text(
          'リセットしますか？',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        content: Text(
          'タイマーを最初（25:00・1サイクル目）に戻します。今の経過はなくなります。',
          style: TextStyle(color: Colors.white.withOpacity(0.7), height: 1.5),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white.withOpacity(0.7),
            ),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: accent),
            child: const Text(
              'リセット',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) onReset();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _CircleButton(
          icon: Icons.refresh,
          size: 60,
          background: Colors.white.withOpacity(0.08),
          iconColor: Colors.white.withOpacity(0.8),
          onTap: () => _confirmReset(context),
        ),
        const SizedBox(width: 28),
        // Primary play/pause
        _CircleButton(
          icon: isRunning ? Icons.pause : Icons.play_arrow,
          size: 84,
          background: accent,
          iconColor: const Color(0xFF121212),
          onTap: isRunning ? onPause : onStart,
        ),
        const SizedBox(width: 28),
        // Brown noise on/off toggle
        _CircleButton(
          icon: noiseEnabled ? Icons.graphic_eq : Icons.volume_off_outlined,
          size: 60,
          background: noiseEnabled
              ? accent.withOpacity(0.18)
              : Colors.white.withOpacity(0.08),
          iconColor:
              noiseEnabled ? accent : Colors.white.withOpacity(0.55),
          onTap: () => onToggleNoise(!noiseEnabled),
        ),
      ],
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.icon,
    required this.size,
    required this.background,
    required this.iconColor,
    required this.onTap,
  });

  final IconData icon;
  final double size;
  final Color background;
  final Color iconColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, color: iconColor, size: size * 0.42),
        ),
      ),
    );
  }
}
