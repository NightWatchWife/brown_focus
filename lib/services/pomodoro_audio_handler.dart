import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:rxdart/rxdart.dart';

import '../config.dart';
import '../models/pomodoro_state.dart';

/// The single source of truth for the timer + audio.
///
/// It runs inside the `audio_service` process, which is kept alive by an
/// Android foreground service. Because a foreground service prevents the OS
/// from killing the process, the `Timer.periodic` below keeps ticking and the
/// brown noise keeps looping even when the screen is off or the app is
/// backgrounded.
class PomodoroAudioHandler extends BaseAudioHandler {
  PomodoroAudioHandler() {
    _init();
  }

  /// Loops the brown noise seamlessly for the whole session.
  final AudioPlayer _noisePlayer = AudioPlayer();

  /// Fires the short "3・2・1" countdown / alert. Kept separate so it can play
  /// *over* the brown noise without interrupting the loop.
  final AudioPlayer _sfxPlayer = AudioPlayer();

  /// The reactive Pomodoro snapshot the UI subscribes to.
  final BehaviorSubject<PomodoroData> _pomodoro =
      BehaviorSubject<PomodoroData>.seeded(_initialData);

  Timer? _ticker;
  bool _countdownFiredForPhase = false;

  /// Wall-clock time the current phase ends while running. The remaining time
  /// is derived from this rather than counted tick-by-tick, so a throttled or
  /// backgrounded browser tab (which slows timers) still shows the correct time
  /// and fast-forwards through any phases that elapsed while it was hidden.
  DateTime? _phaseEndsAt;

  /// Which loop is currently loaded into [_noisePlayer] (brown vs. break), so
  /// we only swap the asset when the phase kind actually changes.
  String? _loadedNoiseAsset;

  static const PomodoroData _initialData = PomodoroData(
    phase: PomodoroPhase.focus,
    cycle: 1,
    totalCycles: PomodoroConfig.cyclesBeforeLongBreak,
    remainingSeconds: PomodoroConfig.focusSeconds,
    totalSeconds: PomodoroConfig.focusSeconds,
    isRunning: false,
    noiseEnabled: true,
  );

  /// Public stream consumed by Riverpod / the UI.
  ValueStream<PomodoroData> get pomodoroStream => _pomodoro.stream;
  PomodoroData get _state => _pomodoro.value;

  Future<void> _init() async {
    try {
      // Loop the focus (brown) noise seamlessly to start with.
      _loadedNoiseAsset = PomodoroConfig.brownNoiseAsset;
      await _noisePlayer.setAsset(PomodoroConfig.brownNoiseAsset);
      await _noisePlayer.setLoopMode(LoopMode.one);
      await _noisePlayer.setVolume(1.0);

      await _sfxPlayer.setAsset(PomodoroConfig.countdownAsset);

      // Do NOT auto-play here. The brown noise follows the timer: it starts on
      // play() and stops on pause()/reset(), so the ▶/⏸ button always matches
      // what you hear.
    } catch (e) {
      // Missing assets shouldn't crash the app; the timer still works silently.
      // ignore: avoid_print
      print('PomodoroAudioHandler: audio init failed: $e');
    }

    _publish(); // seeds mediaItem + playbackState for the notification.
  }

  // ---------------------------------------------------------------------------
  // Public controls (called from the UI and from the media notification).
  // ---------------------------------------------------------------------------

  /// Start / resume the countdown. Mapped to the notification "play" button.
  @override
  Future<void> play() async {
    if (_state.isRunning) return;
    _ensureNoisePlaying();
    _phaseEndsAt =
        DateTime.now().add(Duration(seconds: _state.remainingSeconds));
    _pomodoro.add(_state.copyWith(isRunning: true));
    _startTicker();
    _publish();
  }

  /// Pause the countdown and silence the brown noise.
  @override
  Future<void> pause() async {
    if (!_state.isRunning) return;
    _ticker?.cancel();
    final remaining = _remainingSecondsAt(DateTime.now());
    _phaseEndsAt = null;
    await _noisePlayer.pause();
    _pomodoro.add(_state.copyWith(isRunning: false, remainingSeconds: remaining));
    _publish();
  }

  /// Reset back to cycle 1 / focus and silence the audio.
  /// Keeps the user's brown-noise on/off preference.
  Future<void> reset() async {
    _ticker?.cancel();
    _countdownFiredForPhase = false;
    _phaseEndsAt = null;
    await _noisePlayer.pause();
    await _noisePlayer.seek(Duration.zero);
    _pomodoro.add(_initialData.copyWith(noiseEnabled: _state.noiseEnabled));
    _publish();
  }

  /// Jump straight to the focus block of [cycle] (1-based). Lets you join a
  /// session part-way through. Keeps running if the timer was already running.
  Future<void> jumpToCycle(int cycle) async {
    final target = cycle.clamp(1, _state.totalCycles);
    if (target == _state.cycle && _state.phase == PomodoroPhase.focus) return;

    _ticker?.cancel();
    _countdownFiredForPhase = false;
    final wasRunning = _state.isRunning;
    final total = _durationFor(PomodoroPhase.focus);

    _pomodoro.add(_state.copyWith(
      phase: PomodoroPhase.focus,
      cycle: target,
      remainingSeconds: total,
      totalSeconds: total,
    ));

    if (wasRunning) {
      _ensureNoisePlaying();
      _phaseEndsAt = DateTime.now().add(Duration(seconds: total));
      _startTicker();
    }
    _publish();
  }

  /// Toggle the brown noise on/off. Works as a plain Pomodoro timer (countdown
  /// sound only) when off.
  Future<void> setNoiseEnabled(bool enabled) async {
    _pomodoro.add(_state.copyWith(noiseEnabled: enabled));
    if (enabled) {
      if (_state.isRunning) _ensureNoisePlaying();
    } else {
      await _noisePlayer.pause();
    }
    _publish();
  }

  /// Full teardown — stops audio and removes the notification.
  @override
  Future<void> stop() async {
    _ticker?.cancel();
    await _noisePlayer.stop();
    await _sfxPlayer.stop();
    _pomodoro.add(_initialData.copyWith(noiseEnabled: _state.noiseEnabled));
    playbackState.add(playbackState.value.copyWith(
      playing: false,
      processingState: AudioProcessingState.idle,
    ));
    await super.stop();
  }

  /// audio_service routes unknown custom actions here (e.g. from a widget).
  @override
  Future<dynamic> customAction(String name, [Map<String, dynamic>? extras]) {
    if (name == 'reset') return reset();
    return super.customAction(name, extras);
  }

  // ---------------------------------------------------------------------------
  // Ticking + phase sequencing.
  // ---------------------------------------------------------------------------

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  /// Seconds left in the current phase at [now], derived from the deadline.
  int _remainingSecondsAt(DateTime now) {
    final end = _phaseEndsAt;
    if (end == null) return _state.remainingSeconds;
    final ms = end.difference(now).inMilliseconds;
    if (ms <= 0) return 0;
    return (ms / 1000).ceil();
  }

  void _onTick() {
    final now = DateTime.now();
    final end = _phaseEndsAt;
    if (end == null) return;
    var boundary = end; // non-null DateTime

    // Fast-forward through every phase whose end already passed. Normally this
    // loops zero times (one tick per second); after a hidden/throttled tab it
    // may cross several boundaries at once, staying drift-free by chaining each
    // new deadline off the previous exact boundary.
    var advanced = false;
    while (!now.isBefore(boundary)) {
      boundary = _advancePhaseFrom(boundary);
      advanced = true;
    }

    final remaining = (boundary.difference(now).inMilliseconds / 1000).ceil();

    // Fire the countdown SFX once, within the lead window before the switch.
    if (!_countdownFiredForPhase &&
        remaining > 0 &&
        remaining <= PomodoroConfig.countdownLeadSeconds) {
      _countdownFiredForPhase = true;
      _playCountdown();
    }

    _pomodoro.add(_state.copyWith(remainingSeconds: remaining));
    if (advanced) {
      _ensureNoisePlaying(); // swap focus <-> break loop for the new phase
      _publish();
    } else {
      _publish(updateMediaItem: false); // keep notification position fresh
    }
  }

  /// Advances one phase (25/5 ×4 / 20 pattern) as of the exact [boundary] time,
  /// updates state and the next deadline, and returns the new phase-end time.
  DateTime _advancePhaseFrom(DateTime boundary) {
    _countdownFiredForPhase = false;
    final s = _state;

    PomodoroPhase nextPhase;
    int nextCycle = s.cycle;

    switch (s.phase) {
      case PomodoroPhase.focus:
        // After the 4th focus block, take the long break.
        if (s.cycle >= PomodoroConfig.cyclesBeforeLongBreak) {
          nextPhase = PomodoroPhase.longBreak;
        } else {
          nextPhase = PomodoroPhase.shortBreak;
        }
        break;
      case PomodoroPhase.shortBreak:
        nextPhase = PomodoroPhase.focus;
        nextCycle = s.cycle + 1;
        break;
      case PomodoroPhase.longBreak:
        // Long break over → back to cycle 1.
        nextPhase = PomodoroPhase.focus;
        nextCycle = 1;
        break;
    }

    final total = _durationFor(nextPhase);
    final newEnd = boundary.add(Duration(seconds: total));
    _phaseEndsAt = newEnd;
    _pomodoro.add(s.copyWith(
      phase: nextPhase,
      cycle: nextCycle,
      remainingSeconds: total,
      totalSeconds: total,
      isRunning: true, // roll straight into the next phase
    ));
    return newEnd;
  }

  int _durationFor(PomodoroPhase phase) {
    switch (phase) {
      case PomodoroPhase.focus:
        return PomodoroConfig.focusSeconds;
      case PomodoroPhase.shortBreak:
        return PomodoroConfig.shortBreakSeconds;
      case PomodoroPhase.longBreak:
        return PomodoroConfig.longBreakSeconds;
    }
  }

  // ---------------------------------------------------------------------------
  // Audio helpers.
  // ---------------------------------------------------------------------------

  /// The looping asset that fits the current phase: brown noise for focus,
  /// the softer wave-like loop for breaks.
  String _noiseAssetForPhase(PomodoroPhase phase) =>
      phase.isFocus ? PomodoroConfig.brownNoiseAsset : PomodoroConfig.breakNoiseAsset;

  /// Loads the right loop for the current phase (if it changed) and starts it.
  /// Safe to call whenever the phase changes or playback (re)starts.
  void _ensureNoisePlaying() {
    if (!_state.noiseEnabled) return; // plain-timer mode: no background noise
    unawaited(_syncNoise());
  }

  Future<void> _syncNoise() async {
    try {
      final want = _noiseAssetForPhase(_state.phase);
      if (_loadedNoiseAsset != want) {
        _loadedNoiseAsset = want;
        // setAsset stops playback; we restart it below.
        await _noisePlayer.setAsset(want);
        await _noisePlayer.setLoopMode(LoopMode.one);
      }
      // IMPORTANT: never await play(). just_audio's play() future only
      // completes when playback ends/stops — for a looping source that is
      // never, so awaiting it would deadlock the caller.
      if (_state.noiseEnabled && !_noisePlayer.playing) {
        unawaited(_noisePlayer.play());
      }
    } catch (_) {/* asset may be missing */}
  }

  void _playCountdown() {
    try {
      _sfxPlayer.seek(Duration.zero);
      unawaited(_sfxPlayer.play());
    } catch (_) {/* asset may be missing */}
  }

  // ---------------------------------------------------------------------------
  // Sync state to audio_service (drives the system media notification).
  // ---------------------------------------------------------------------------

  void _publish({bool updateMediaItem = true}) {
    final s = _state;

    if (updateMediaItem) {
      mediaItem.add(MediaItem(
        id: 'brown_focus_${s.phase.name}_${s.cycle}',
        title: s.phase.label,
        artist: s.phase.isFocus
            ? 'サイクル ${s.cycle} / ${s.totalCycles}'
            : 'ゆったり休憩',
        duration: Duration(seconds: s.totalSeconds),
      ));
    }

    playbackState.add(playbackState.value.copyWith(
      controls: [
        if (s.isRunning) MediaControl.pause else MediaControl.play,
        MediaControl.stop,
      ],
      systemActions: const {
        MediaAction.play,
        MediaAction.pause,
        MediaAction.stop,
      },
      processingState: AudioProcessingState.ready,
      playing: s.isRunning,
      updatePosition: Duration(seconds: s.totalSeconds - s.remainingSeconds),
    ));
  }
}
