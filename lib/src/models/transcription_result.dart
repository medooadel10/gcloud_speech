// ──────────────────────────────────────────────────────────────────────────────
// transcription_result.dart
//
// The final data class returned by `GCloudSpeechService.stopRecording()`.
// Contains everything the caller needs: the audio file, transcript text,
// confidence, word-level info, and alternative transcripts.
// ──────────────────────────────────────────────────────────────────────────────

import 'word_info.dart';

/// The result returned by [GCloudSpeechService.stopRecording].
///
/// Depending on the [TranscriptionMode] used when starting the recording:
///
/// | Mode              | What is populated                              |
/// |-------------------|------------------------------------------------|
/// | `realTime`        | [audioPath], [transcript], [confidence], etc.  |
/// | `afterRecording`  | [audioPath], [transcript], [confidence], etc.  |
/// | `none`            | [audioPath] only                               |
///
/// Example:
/// ```dart
/// final result = await service.stopRecording();
///
/// print(result.audioPath);   // '/data/.../audio_17...wav'
/// print(result.transcript);  // 'Hello, how are you?'
/// print(result.confidence);  // 0.96
///
/// for (final alt in result.alternatives ?? []) {
///   print('Alt: ${alt.transcript} (${alt.confidence})');
/// }
/// ```
class TranscriptionResult {
  /// Creates a [TranscriptionResult].
  ///
  /// All parameters are optional because different modes populate different
  /// subsets of the fields.
  const TranscriptionResult({
    this.audioPath,
    this.transcript,
    this.confidence,
    this.words,
    this.audioDuration,
    this.alternatives,
  });

  /// Absolute path to the recorded audio file on disk.
  ///
  /// Will be `null` only if the recording was cancelled before any audio was
  /// captured.
  final String? audioPath;

  /// The best (highest-confidence) transcript returned by the Speech API.
  ///
  /// `null` when [TranscriptionMode.none] was used or if the API returned no
  /// results (e.g. silence).
  final String? transcript;

  /// Overall confidence score for [transcript], in the range `[0.0, 1.0]`.
  ///
  /// `null` when no transcript is available.
  final double? confidence;

  /// Word-level details (timing + optional per-word confidence).
  ///
  /// Only populated when [SpeechConfig.enableWordTimeOffsets] or
  /// [SpeechConfig.enableWordConfidence] is `true`.
  final List<WordInfo>? words;

  /// Duration of the recorded audio.
  ///
  /// Computed from the last word's end-time when word offsets are available,
  /// otherwise `null`.
  final Duration? audioDuration;

  /// Additional alternative transcriptions ranked by confidence.
  ///
  /// Only populated when [SpeechConfig.maxAlternatives] > 1.
  final List<SpeechAlternative>? alternatives;

  @override
  String toString() =>
      'TranscriptionResult('
      'audioPath: $audioPath, '
      'transcript: "${transcript ?? ""}", '
      'confidence: $confidence, '
      'words: ${words?.length ?? 0} words, '
      'audioDuration: $audioDuration, '
      'alternatives: ${alternatives?.length ?? 0}'
      ')';
}

/// A single alternative transcript returned by the Speech API.
///
/// When [SpeechConfig.maxAlternatives] > 1, the API returns multiple possible
/// transcripts ordered by [confidence] (highest first).
class SpeechAlternative {
  /// Creates a [SpeechAlternative].
  const SpeechAlternative({
    required this.transcript,
    this.confidence,
    this.words,
  });

  /// The alternative transcript text.
  final String transcript;

  /// Confidence score for this alternative, in the range `[0.0, 1.0]`.
  final double? confidence;

  /// Word-level info for this alternative (if word offsets were requested).
  final List<WordInfo>? words;

  /// Builds a [SpeechAlternative] from the raw JSON map returned by the API.
  factory SpeechAlternative.fromJson(Map<String, dynamic> json) {
    return SpeechAlternative(
      // The transcript text.
      transcript: json['transcript'] as String? ?? '',

      // Overall confidence for this alternative.
      confidence: (json['confidence'] as num?)?.toDouble(),

      // Parse word-level info if present.
      words: (json['words'] as List<dynamic>?)
          ?.map((w) => WordInfo.fromJson(w as Map<String, dynamic>))
          .toList(),
    );
  }

  @override
  String toString() =>
      'SpeechAlternative(transcript: "$transcript", '
      'confidence: $confidence, '
      'words: ${words?.length ?? 0})';
}
