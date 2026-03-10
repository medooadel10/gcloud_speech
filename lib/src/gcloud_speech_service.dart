// ──────────────────────────────────────────────────────────────────────────────
// gcloud_speech_service.dart
//
// The **main public class** of the package. This is the only class most users
// need to interact with.
//
// It orchestrates:
//   • AudioRecorderService  – microphone recording
//   • SpeechRecognizerService – Google Cloud Speech API calls
//
// And exposes a simple, high-level API:
//   startRecording → pauseRecording → resumeRecording → stopRecording
//
// ──────────────────────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'config/recording_config.dart';
import 'config/speech_config.dart';
import 'enums/recording_state.dart';
import 'enums/transcription_mode.dart';
import 'models/transcription_result.dart';
import 'models/word_info.dart';
import 'services/audio_recorder_service.dart';
import 'services/speech_recognizer_service.dart';

/// A high-level service that combines **audio recording** with
/// **Google Cloud Speech-to-Text V2 transcription**.
///
/// ## Quick start
///
/// ```dart
/// // 1. Create the service.
/// final service = GCloudSpeechService(
///   apiKey: 'YOUR_GOOGLE_CLOUD_API_KEY',
///   projectId: 'my-project-123',
///   speechConfig: SpeechConfig(languageCode: 'en-US'),
/// );
///
/// // 2. Start recording with real-time transcription.
/// await service.startRecording(mode: TranscriptionMode.realTime);
///
/// // 3. Listen for live updates.
/// service.liveTranscript.addListener(() {
///   print('Live: ${service.liveTranscript.value}');
/// });
///
/// // 4. Stop & get the final result.
/// final result = await service.stopRecording();
/// print(result.audioPath);
/// print(result.transcript);
/// ```
///
/// ## Lifecycle
///
/// ```
///           ┌──────────┐
///    ──────►│   idle    │◄─── stopRecording / cancelRecording
///           └────┬─────┘
///                │ startRecording(mode: …)
///           ┌────▼─────┐
///    ┌─────►│recording │────► stopRecording → TranscriptionResult
///    │      └────┬─────┘
///    │           │ pauseRecording
///    │      ┌────▼─────┐
///    └──────│  paused  │
///           └──────────┘
///              resumeRecording
/// ```
class GCloudSpeech {
  /// Creates a [GCloudSpeech].
  ///
  /// * [apiKey]          – Your Google Cloud API key with the Speech-to-Text
  ///                       API enabled (pass an empty string when using
  ///                       [accessToken] only).
  /// * [projectId]       – **Required**. Your Google Cloud project ID
  ///                       (e.g. `'my-project-123'`).
  /// * [location]        – Processing location. Defaults to `'global'`.
  ///                       Other options: `'us'`, `'eu'`, or a specific region.
  /// * [accessToken]     – An optional OAuth2 Bearer token obtained from a
  ///                       Google Cloud **service account**.  Required when
  ///                       using the V2 API, which enforces IAM permissions
  ///                       (`speech.recognizers.recognize`). Obtain via
  ///                       `googleapis_auth`:
  ///                       ```dart
  ///                       final client = await clientViaServiceAccount(
  ///                         credentials, ['https://www.googleapis.com/auth/cloud-platform']);
  ///                       final token = client.credentials.accessToken.data;
  ///                       ```
  /// * [speechConfig]    – Configuration for the Speech API (language, model,
  ///                       punctuation, etc.). Defaults to `en-US` with
  ///                       automatic punctuation.
  /// * [recordingConfig] – Configuration for the audio recorder (encoder,
  ///                       sample rate, etc.). Defaults to WAV, 16 kHz, mono.
  /// * [onError]         – Optional callback invoked when a non-fatal error
  ///                       occurs (e.g. a single chunk fails). The recording
  ///                       continues.
  GCloudSpeech({
    required String apiKey,
    required String projectId,
    String location = 'global',
    required String accessToken,
    SpeechConfig? speechConfig,
    RecordingConfig? recordingConfig,
    this.onError,
  }) : // Store the provided SpeechConfig or fall back to a sensible default.
       _speechConfig =
           speechConfig ?? const SpeechConfig(languageCode: 'en-US'),

       // Store the provided RecordingConfig or fall back to a sensible default.
       _recordingConfig = recordingConfig ?? const RecordingConfig(),

       // Create the lower-level recogniser with the API key, optional bearer
       // token, and project details.
       _recognizer = SpeechRecognizerService(
         apiKey: apiKey,
         projectId: projectId,
         location: location,
         accessToken: accessToken,
       );

  // ── Configuration ──────────────────────────────────────────────────────────

  /// The Speech API configuration (language, model, etc.).
  final SpeechConfig _speechConfig;

  /// The audio recording configuration (encoder, sample rate, etc.).
  final RecordingConfig _recordingConfig;

  // ── Sub-services ───────────────────────────────────────────────────────────

  /// The lower-level audio recorder.
  final AudioRecorderService _recorder = AudioRecorderService();

  /// The lower-level Speech API client.
  final SpeechRecognizerService _recognizer;

  // ── Real-time timer ────────────────────────────────────────────────────────

  /// Periodic timer that drains the audio buffer and sends chunks while in
  /// [TranscriptionMode.realTime].
  Timer? _chunkTimer;

  // ── Transcription mode for the current session ─────────────────────────────

  /// The transcription mode chosen when [startRecording] was called.
  TranscriptionMode _activeMode = TranscriptionMode.none;

  // ── Recorded file path (set after recording starts) ────────────────────────

  /// Holds the file path returned by the recorder when recording starts.
  String? _currentFilePath;

  // ── Observable state ───────────────────────────────────────────────────────

  /// The current recording state (idle / recording / paused).
  ///
  /// Use this with [ValueListenableBuilder] to rebuild UI elements whenever
  /// the state changes:
  ///
  /// ```dart
  /// ValueListenableBuilder<RecordingState>(
  ///   valueListenable: service.recordingState,
  ///   builder: (_, state, __) {
  ///     if (state == RecordingState.recording) return StopButton();
  ///     return RecordButton();
  ///   },
  /// )
  /// ```
  ValueNotifier<RecordingState> get recordingState => _recorder.state;

  /// The live transcript accumulated from real-time chunks.
  ///
  /// Only meaningful when [TranscriptionMode.realTime] is used.
  /// The value is appended to after every successful chunk transcription.
  ///
  /// Reset to an empty string when a new recording starts.
  final ValueNotifier<String> liveTranscript = ValueNotifier('');

  /// The transcription progress percentage (0 – 100).
  ///
  /// Only meaningful when [TranscriptionMode.afterRecording] is used with
  /// a long audio file (> 1 min) that triggers the long-running API.
  final ValueNotifier<int> transcriptionProgress = ValueNotifier(0);

  // ── Error callback ─────────────────────────────────────────────────────────

  /// Optional callback invoked when a non-fatal error occurs.
  ///
  /// Example: a single real-time chunk fails to transcribe. The recording
  /// continues, but you may want to log or display the error.
  final void Function(String message)? onError;

  // ── Internal text accumulator ──────────────────────────────────────────────

  /// Buffer that accumulates transcript text from each real-time chunk.
  final StringBuffer _transcriptBuffer = StringBuffer();

  // ── Permission ─────────────────────────────────────────────────────────────

  /// Checks (and optionally requests) microphone permission.
  ///
  /// Returns `true` if the permission is granted. Call this before
  /// [startRecording] for the best UX so you can show a custom rationale
  /// when the user denies permission.
  Future<bool> checkPermission() => _recorder.hasPermission();

  // ── Recording controls ─────────────────────────────────────────────────────

  /// Starts a new recording session.
  ///
  /// * [mode] – Determines how (and when) transcription happens.
  ///   * [TranscriptionMode.realTime]       – Audio chunks are transcribed
  ///     while recording. [liveTranscript] updates incrementally.
  ///   * [TranscriptionMode.afterRecording] – Transcription happens only
  ///     after [stopRecording] is called. [stopRecording] awaits the result.
  ///   * [TranscriptionMode.none]           – No transcription. Only the
  ///     audio file path is returned.
  ///
  /// Returns the **file path** where the recording will be saved.
  ///
  /// Throws if:
  /// * Microphone permission is not granted.
  /// * A recording is already in progress.
  ///
  /// Example:
  /// ```dart
  /// final path = await service.startRecording(
  ///   mode: TranscriptionMode.realTime,
  /// );
  /// print('Recording to: $path');
  /// ```
  Future<String> startRecording({
    TranscriptionMode mode = TranscriptionMode.none,
  }) async {
    // ── 1. Guard: don't start if already recording ───────────────────────
    if (_recorder.state.value != RecordingState.idle) {
      throw StateError(
        'Cannot start a new recording while one is already in progress. '
        'Call stopRecording() or cancelRecording() first.',
      );
    }

    // ── 2. Reset accumulated state from any previous session ─────────────
    _transcriptBuffer.clear();
    liveTranscript.value = '';
    transcriptionProgress.value = 0;
    _activeMode = mode;

    // ── 3. Determine whether we need the PCM stream ──────────────────────
    //    Real-time mode needs the parallel PCM stream so we can drain chunks.
    //    Other modes only need the file recorder.
    final needsStream = mode == TranscriptionMode.realTime;

    // ── 4. Start the recorder ────────────────────────────────────────────
    //    This returns the file path where audio will be written.
    _currentFilePath = await _recorder.start(
      _recordingConfig,
      withStream: needsStream,
    );

    // ── 5. Start the periodic chunk timer (real-time only) ───────────────
    if (needsStream) {
      _startChunkTimer();
    }

    // ── 6. Return the path so the caller can display / use it ────────────
    return _currentFilePath!;
  }

  /// Pauses the current recording.
  ///
  /// During a pause:
  /// * No audio is captured.
  /// * The chunk timer (if active) keeps firing but drains an empty buffer,
  ///   so no API calls are made.
  /// * Call [resumeRecording] to continue.
  ///
  /// Throws if no recording is in progress.
  Future<void> pauseRecording() async {
    // Guard: only allow pausing when actively recording.
    if (_recorder.state.value != RecordingState.recording) {
      throw StateError('Cannot pause – not currently recording.');
    }

    await _recorder.pause();
  }

  /// Resumes a previously paused recording.
  ///
  /// Throws if the recording is not in the paused state.
  Future<void> resumeRecording() async {
    // Guard: only allow resuming when paused.
    if (_recorder.state.value != RecordingState.paused) {
      throw StateError('Cannot resume – recording is not paused.');
    }

    await _recorder.resume();
  }

  /// Stops the recording and returns the full [TranscriptionResult].
  ///
  /// Behaviour depends on the [TranscriptionMode] chosen at start time:
  ///
  /// | Mode              | What `stopRecording` does                        |
  /// |-------------------|--------------------------------------------------|
  /// | `realTime`        | Stops recording, drains the last chunk, returns   |
  /// |                   | the accumulated transcript.                       |
  /// | `afterRecording`  | Stops recording, sends the **full file** to the   |
  /// |                   | API, **awaits** the transcript, then returns.      |
  /// | `none`            | Stops recording and returns only the file path.   |
  ///
  /// Example:
  /// ```dart
  /// final result = await service.stopRecording();
  ///
  /// print(result.audioPath);   // '/data/.../audio_17...wav'
  /// print(result.transcript);  // 'Hello, world!'
  /// print(result.confidence);  // 0.95
  /// print(result.words);       // [WordInfo(...), ...]
  /// ```
  Future<TranscriptionResult> stopRecording() async {
    // ── 1. Stop the chunk timer (real-time mode) ─────────────────────────
    _stopChunkTimer();

    // ── 2. Drain any remaining audio in real-time mode ───────────────────
    //    The last chunk may contain important trailing audio that hasn't
    //    been sent yet.
    if (_activeMode == TranscriptionMode.realTime) {
      await _drainAndTranscribeChunk();
    }

    // ── 3. Stop the recorder ─────────────────────────────────────────────
    //    This finalises the file on disk.
    final audioPath = await _recorder.stop();

    // ── 4. Handle post-recording transcription ───────────────────────────
    if (_activeMode == TranscriptionMode.afterRecording && audioPath != null) {
      // Send the full file to the API and wait for the result.
      final response = await _recognizer.recognizeFile(
        audioPath,
        _speechConfig,
        onProgress: (percent) {
          // Update the progress notifier so the UI can show a progress bar.
          transcriptionProgress.value = percent;
        },
      );

      transcriptionProgress.value = 100;

      // Wrap the response into a TranscriptionResult.
      return TranscriptionResult(
        audioPath: audioPath,
        transcript: response?.transcript,
        confidence: response?.confidence,
        words: response?.words,
        alternatives: response?.alternatives,
        audioDuration: _computeDuration(response?.words),
      );
    }

    // ── 5. Build the result for real-time or none mode ───────────────────
    return TranscriptionResult(
      audioPath: audioPath,
      // For real-time: the accumulated transcript from all chunks.
      // For none: null.
      transcript: _activeMode == TranscriptionMode.realTime
          ? (_transcriptBuffer.isNotEmpty ? _transcriptBuffer.toString() : null)
          : null,
      confidence: null, // Not available for chunk-by-chunk mode.
    );
  }

  /// Cancels the recording and discards all data.
  ///
  /// No [TranscriptionResult] is returned. The audio file is not saved.
  ///
  /// Example:
  /// ```dart
  /// await service.cancelRecording();
  /// // Recording is now idle — no file, no transcript.
  /// ```
  Future<void> cancelRecording() async {
    // Stop the timer first.
    _stopChunkTimer();

    // Discard all audio.
    await _recorder.cancel();

    // Clear transcript state.
    _transcriptBuffer.clear();
    liveTranscript.value = '';
    transcriptionProgress.value = 0;
    _activeMode = TranscriptionMode.none;
    _currentFilePath = null;
  }

  // ── Configuration getters ──────────────────────────────────────────────────

  /// The active [SpeechConfig]. Useful for debugging or display.
  SpeechConfig get speechConfig => _speechConfig;

  /// The active [RecordingConfig]. Useful for debugging or display.
  RecordingConfig get recordingConfig => _recordingConfig;

  /// The transcription mode of the current (or most recent) session.
  TranscriptionMode get activeMode => _activeMode;

  /// The file path of the current (or most recent) recording.
  String? get currentFilePath => _currentFilePath;

  // ── Cleanup ────────────────────────────────────────────────────────────────

  /// Releases all resources (recorders, HTTP client, notifiers, timers).
  ///
  /// After calling this, the instance must not be used again.
  Future<void> dispose() async {
    _stopChunkTimer();
    await _recorder.dispose();
    _recognizer.dispose();
    liveTranscript.dispose();
    transcriptionProgress.dispose();
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  /// Starts a periodic timer that drains audio chunks and sends them to the
  /// Speech API for real-time transcription.
  void _startChunkTimer() {
    // Use the chunk interval from the speech config.
    final interval = Duration(milliseconds: _speechConfig.chunkIntervalMs);

    _chunkTimer = Timer.periodic(interval, (_) async {
      // Don't send chunks while paused.
      if (_recorder.state.value != RecordingState.recording) return;

      await _drainAndTranscribeChunk();
    });
  }

  /// Stops the periodic chunk timer.
  void _stopChunkTimer() {
    _chunkTimer?.cancel();
    _chunkTimer = null;
  }

  /// Drains the buffered audio bytes and sends them to the Speech API.
  ///
  /// If the buffer is empty or too small (below [SpeechConfig.minChunkSizeBytes])
  /// the call is skipped.
  Future<void> _drainAndTranscribeChunk() async {
    // Drain whatever has accumulated since the last call.
    final chunk = _recorder.drainChunk();

    // Skip if there's nothing to send.
    if (chunk == null) return;

    // Skip if the chunk is too small to produce useful results.
    if (chunk.length < _speechConfig.minChunkSizeBytes) return;

    try {
      // Send the raw PCM bytes to the synchronous endpoint.
      final response = await _recognizer.recognizeBytes(chunk, _speechConfig);

      if (response != null && response.transcript.isNotEmpty) {
        // Append to the running buffer.
        if (_transcriptBuffer.isNotEmpty) _transcriptBuffer.write(' ');
        _transcriptBuffer.write(response.transcript);

        // Update the live notifier so listeners (UI) can react.
        liveTranscript.value = _transcriptBuffer.toString();
      }
    } on Exception catch (e) {
      // Report the error but keep recording.
      debugPrint('[GCloudSpeechService] chunk error: $e');
      onError?.call('Chunk transcription failed: $e');
    }
  }

  /// Computes an approximate audio duration from the last word's end-time.
  ///
  /// Returns `null` if word-level info is not available.
  Duration? _computeDuration(List<WordInfo>? words) {
    if (words == null || words.isEmpty) return null;

    // The last word's endTime gives us the audio duration.
    return words.last.endTime;
  }
}
