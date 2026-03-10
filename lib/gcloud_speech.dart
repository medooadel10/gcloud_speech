// ──────────────────────────────────────────────────────────────────────────────
// gcloud_speech.dart — Library barrel file
//
// This is the single import that users of the package need:
//
//   import 'package:gcloud_speech/gcloud_speech.dart';
//
// It re-exports every public class, enum, and typedef so the consumer doesn't
// need to know about the internal directory structure.
// ──────────────────────────────────────────────────────────────────────────────

/// A comprehensive Flutter package for Google Cloud Speech-to-Text.
///
/// Provides audio recording (start / pause / resume / stop) combined with
/// real-time streaming transcription or post-recording batch transcription.
///
/// ## Quick start
///
/// ```dart
/// import 'package:gcloud_speech/gcloud_speech.dart';
///
/// final service = GCloudSpeechService(
///   apiKey: 'YOUR_API_KEY',
///   speechConfig: SpeechConfig(languageCode: 'en-US'),
/// );
///
/// await service.startRecording(mode: TranscriptionMode.realTime);
/// // ... user speaks ...
/// final result = await service.stopRecording();
/// print(result.transcript);
/// ```
library;

export 'src/config/recording_config.dart';
// ── Configuration ────────────────────────────────────────────────────────────
export 'src/config/speech_config.dart';
// ── Enums ────────────────────────────────────────────────────────────────────
export 'src/enums/recording_state.dart';
export 'src/enums/transcription_mode.dart';
// ── Main service (the facade) ────────────────────────────────────────────────
export 'src/gcloud_speech_service.dart';
// ── Models ───────────────────────────────────────────────────────────────────
export 'src/models/transcription_result.dart';
export 'src/models/word_info.dart';
