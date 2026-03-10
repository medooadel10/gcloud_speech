// ──────────────────────────────────────────────────────────────────────────────
// transcription_mode.dart
//
// Specifies *when* audio should be sent to Google Cloud Speech‑to‑Text.
// ──────────────────────────────────────────────────────────────────────────────

/// Controls how and when audio is transcribed during a recording session.
///
/// Choose the mode that fits your UX:
///
/// | Mode              | When audio is sent       | Typical use-case                   |
/// |-------------------|--------------------------|------------------------------------|
/// | [realTime]        | While recording          | Live subtitles / captions          |
/// | [afterRecording]  | After `stopRecording()`  | Summary / note-taking after a call |
/// | [none]            | Never                    | Record-only, no transcription      |
enum TranscriptionMode {
  /// Audio chunks are streamed to the Speech API **while** the user is still
  /// recording. The [GCloudSpeechService.liveTranscript] notifier updates
  /// incrementally as new text arrives.
  ///
  /// Under the hood a periodic timer drains the PCM buffer and sends each
  /// chunk to `speech:recognize`.
  realTime,

  /// Transcription starts **only after** the recording is stopped.
  ///
  /// * For audio ≤ 1 minute  → synchronous `speech:recognize` is used.
  /// * For audio > 1 minute  → asynchronous `speech:longrunningrecognize` is
  ///   used and the service polls until the operation completes.
  ///
  /// `stopRecording()` will `await` the full transcript before returning.
  afterRecording,

  /// No transcription at all – the service only records and returns the file
  /// path. Useful when you want to handle transcription yourself or just need
  /// the audio artifact.
  none,
}
