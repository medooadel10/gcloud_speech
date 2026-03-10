// ──────────────────────────────────────────────────────────────────────────────
// word_info.dart
//
// Data class for word-level timing and confidence information returned by the
// Google Cloud Speech‑to‑Text API when `enableWordTimeOffsets` or
// `enableWordConfidence` is turned on.
// ──────────────────────────────────────────────────────────────────────────────

/// Holds information about a single recognised word, including its timing
/// within the audio and an optional per-word confidence score.
///
/// This is only populated when:
/// * [SpeechConfig.enableWordTimeOffsets] is `true`  → [startTime] / [endTime]
/// * [SpeechConfig.enableWordConfidence]  is `true`  → [confidence]
///
/// Example:
/// ```dart
/// for (final w in result.words ?? []) {
///   print('${w.word}  ${w.startTime} → ${w.endTime}  conf=${w.confidence}');
/// }
/// ```
class WordInfo {
  /// Creates a [WordInfo] instance.
  ///
  /// * [word]       – The recognised word string.
  /// * [startTime]  – Offset from the beginning of the audio where the word
  ///                  starts being spoken.
  /// * [endTime]    – Offset from the beginning of the audio where the word
  ///                  stops being spoken.
  /// * [confidence] – Confidence score for this particular word (0.0 – 1.0).
  ///                  Only present when `enableWordConfidence` is `true`.
  const WordInfo({
    required this.word,
    required this.startTime,
    required this.endTime,
    this.confidence,
  });

  /// The recognised word (e.g. `"hello"`).
  final String word;

  /// When this word starts relative to the beginning of the audio.
  final Duration startTime;

  /// When this word ends relative to the beginning of the audio.
  final Duration endTime;

  /// Per-word confidence score in the range `[0.0, 1.0]`.
  ///
  /// `null` if [SpeechConfig.enableWordConfidence] was not set.
  final double? confidence;

  /// Builds a [WordInfo] from the raw JSON map returned by the Speech API V2.
  ///
  /// V2 uses `startOffset` / `endOffset` (strings like `"1.500s"`).
  /// For backwards-compat we also check V1's `startTime` / `endTime`.
  factory WordInfo.fromJson(Map<String, dynamic> json) {
    return WordInfo(
      // The "word" field is always a string.
      word: json['word'] as String? ?? '',

      // V2 field name is `startOffset`; fall back to V1's `startTime`.
      startTime: _parseDuration(json['startOffset'] ?? json['startTime']),

      // V2 field name is `endOffset`; fall back to V1's `endTime`.
      endTime: _parseDuration(json['endOffset'] ?? json['endTime']),

      // Confidence is a double; may be absent.
      confidence:
          (json['wordConfidence'] as num?)?.toDouble() ??
          (json['confidence'] as num?)?.toDouble(),
    );
  }

  /// Parses a protobuf Duration string like `"1.500s"` into a Dart [Duration].
  ///
  /// Returns [Duration.zero] for `null` or unparseable values.
  static Duration _parseDuration(dynamic value) {
    // If it's null, return zero.
    if (value == null) return Duration.zero;

    // The API returns durations as strings ending with 's' (seconds).
    final raw = value.toString().replaceAll('s', '');

    // Try to parse the numeric string to a double.
    final seconds = double.tryParse(raw);

    // If parsing failed, fall back to zero.
    if (seconds == null) return Duration.zero;

    // Convert seconds to microseconds for maximum precision.
    return Duration(microseconds: (seconds * 1000000).round());
  }

  @override
  String toString() =>
      'WordInfo(word: "$word", '
      'start: ${startTime.inMilliseconds}ms, '
      'end: ${endTime.inMilliseconds}ms, '
      'confidence: $confidence)';
}
