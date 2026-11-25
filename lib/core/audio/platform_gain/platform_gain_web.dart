import 'dart:js' as js;

void applyPlatformGain(double gain, bool isMuted) {
  try {
    js.context.callMethod('setWebSoftwareGain', [isMuted ? 0.0 : gain]);
  } catch (_) {}
}

void setupWebAudioStream() {
  try {
    js.context.callMethod('attachStreamToWebAudio');
  } catch (_) {}
}

void requestScreenWakeLockPlatform() {
  try {
    js.context.callMethod('requestScreenWakeLock');
  } catch (_) {}
}

void releaseScreenWakeLockPlatform() {
  try {
    js.context.callMethod('releaseScreenWakeLock');
  } catch (_) {}
}
