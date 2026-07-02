package com.arigassamaryota.brown_focus

import com.ryanheise.audioservice.AudioServiceActivity

// Must extend AudioServiceActivity (not FlutterActivity) so audio_service can
// re-launch / resume the Flutter UI when the user taps the media notification.
class MainActivity : AudioServiceActivity()
