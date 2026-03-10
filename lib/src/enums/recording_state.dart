// ──────────────────────────────────────────────────────────────────────────────
// recording_state.dart
//
// Defines the lifecycle states of an audio recording session.
// ──────────────────────────────────────────────────────────────────────────────

/// Represents every possible phase of an audio recording session.
///
/// The typical lifecycle is:
///
/// ```
/// idle ──► recording ──► paused ──► recording ──► idle
///                   └──────────────────────────► idle  (stop / cancel)
/// ```
///
/// * [idle]      – No recording in progress. This is the initial & final state.
/// * [recording] – Audio is being captured from the microphone.
/// * [paused]    – Recording has been temporarily paused and can be resumed.
enum RecordingState {
  /// No recording in progress – the service is ready to start a new one.
  idle,

  /// The microphone is actively capturing audio data.
  recording,

  /// Recording has been temporarily suspended; call `resumeRecording()` to
  /// continue capturing from where it left off.
  paused,
}
