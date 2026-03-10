// ──────────────────────────────────────────────────────────────────────────────
// speech_config.dart
//
// All configurable parameters for the Google Cloud Speech-to-Text **V2** API.
// Maps 1-to-1 with the REST API's `RecognitionConfig` message:
// https://cloud.google.com/speech-to-text/docs/reference/rest/v2/RecognitionConfig
// ──────────────────────────────────────────────────────────────────────────────

/// The speech recognition model to use.
///
/// Different models are optimised for different audio scenarios. Picking the
/// right model improves accuracy significantly.
///
/// See: https://cloud.google.com/speech-to-text/docs/transcription-model
enum SpeechModel {
  /// Best for short queries / commands (< 1 min).  Uses the newest model.
  latestShort('latest_short'),

  /// Best for long-form audio (meetings, lectures).  Uses the newest model.
  latestLong('latest_long'),

  /// Optimised for phone-call audio (8 kHz telephony).
  phoneCall('phone_call'),

  /// Optimised for video / high-fidelity audio.
  video('video'),

  /// The default model.  Good general-purpose choice.
  defaultModel('default'),

  /// Best for short commands and voice search.
  commandAndSearch('command_and_search'),

  /// Medical dictation model (requires allowlisting).
  medicalDictation('medical_dictation'),

  /// Medical conversation model (requires allowlisting).
  medicalConversation('medical_conversation');

  /// Creates a [SpeechModel] with its corresponding API string value.
  const SpeechModel(this.value);

  /// The string value sent to the API's `model` field.
  final String value;
}

/// Audio encoding formats supported by the Google Cloud Speech API.
///
/// Must match the actual encoding of the audio bytes you send in the request.
///
/// For **real-time streaming** the package always uses [linear16] (raw PCM).
/// For **post-recording** this should match whatever encoder was used to
/// write the file (typically [linear16] for `.wav` files).
enum SpeechEncoding {
  /// Uncompressed 16-bit signed little-endian PCM samples (WAV without header
  /// when sent as raw bytes; or standard WAV file for post-recording).
  linear16('LINEAR16'),

  /// Free Lossless Audio Codec.
  flac('FLAC'),

  /// μ-law (mu-law) encoded audio (8-bit, 8 kHz telephony).
  mulaw('MULAW'),

  /// Adaptive Multi-Rate Narrowband (8 kHz telephony).
  amr('AMR'),

  /// Adaptive Multi-Rate Wideband (16 kHz).
  amrWb('AMR_WB'),

  /// Ogg container with Opus codec.
  oggOpus('OGG_OPUS'),

  /// WebM container with Opus codec.
  webmOpus('WEBM_OPUS'),

  /// Speex with header byte (deprecated but still accepted).
  speexWithHeaderByte('SPEEX_WITH_HEADER_BYTE'),

  /// MP3 (MPEG Audio Layer III).
  mp3('MP3');

  /// Creates a [SpeechEncoding] with its API-compatible string value.
  const SpeechEncoding(this.value);

  /// The string value sent to the API's `encoding` field.
  final String value;
}

/// A phrase (or collection of phrases) that acts as a "hint" to bias the
/// recogniser toward certain words or phrases.
///
/// Useful for domain-specific vocabulary (product names, jargon, etc.).
///
/// See: https://cloud.google.com/speech-to-text/docs/speech-adaptation
///
/// Example:
/// ```dart
/// SpeechContext(
///   phrases: ['Flutter', 'Dart', 'gcloud_speech'],
///   boost: 10.0,
/// )
/// ```
class SpeechContext {
  /// Creates a [SpeechContext].
  ///
  /// * [phrases] – A list of words or phrases to boost.
  /// * [boost]   – How much to boost these phrases.  Positive values increase
  ///               the likelihood the phrase is recognised.  Range varies by
  ///               API version; typically 0 – 20.
  const SpeechContext({required this.phrases, this.boost});

  /// The phrases to boost during recognition.
  final List<String> phrases;

  /// Boost value for the phrases.  Higher = more likely to appear in results.
  final double? boost;

  /// Converts this context into the V2 API's inline `PhraseSet` format.
  ///
  /// V2 wraps phrase hints inside `adaptation.phraseSets[].inlinePhraseSet`.
  /// Each phrase is an object with `value` and optional `boost`.
  Map<String, dynamic> toJson() => {
    'inlinePhraseSet': {
      'phrases': phrases
          .map((p) => {'value': p, if (boost != null) 'boost': boost})
          .toList(),
    },
  };
}

/// Full configuration for the Google Cloud Speech-to-Text **V2** recognition
/// request.
///
/// Every field maps to a parameter in the V2 API's `RecognitionConfig` message.
/// Only [languageCode] is required; everything else has sensible defaults.
///
/// V2 differences from V1:
/// * `languageCodes` is an array (the primary code is always first).
/// * Features (punctuation, word offsets, …) are nested under a `features`
///   object in the JSON.
/// * Audio decoding can be `autoDecodingConfig` (let the API detect the
///   format) or `explicitDecodingConfig` (you specify encoding, sample rate,
///   channels).
/// * `useEnhanced` is removed — V2 always uses the best available model.
/// * Adaptation uses `phraseSets` with inline phrase objects.
///
/// Example – a richly configured instance:
/// ```dart
/// SpeechConfig(
///   languageCode: 'en-US',
///   encoding: SpeechEncoding.linear16,
///   sampleRateHertz: 16000,
///   model: SpeechModel.latestLong,
///   enableAutomaticPunctuation: true,
///   enableWordTimeOffsets: true,
///   enableWordConfidence: true,
///   maxAlternatives: 3,
///   profanityFilter: false,
///   speechContexts: [
///     SpeechContext(phrases: ['Flutter', 'Dart'], boost: 15),
///   ],
/// )
/// ```
class SpeechConfig {
  /// Creates a [SpeechConfig].
  ///
  /// Only [languageCode] is mandatory.  All other parameters fall back to
  /// API defaults when omitted.
  const SpeechConfig({
    // ── Required ──────────────────────────────────────────────────────────
    required this.languageCode,

    // ── Audio format ──────────────────────────────────────────────────────
    this.encoding = SpeechEncoding.linear16,
    this.sampleRateHertz = 16000,
    this.audioChannelCount = 1,
    this.enableSeparateRecognitionPerChannel = false,

    // ── Language ──────────────────────────────────────────────────────────
    this.alternativeLanguageCodes,

    // ── Result options ────────────────────────────────────────────────────
    this.maxAlternatives = 1,
    this.profanityFilter = false,
    this.enableWordTimeOffsets = false,
    this.enableWordConfidence = false,
    this.enableAutomaticPunctuation = true,
    this.enableSpokenPunctuation = false,
    this.enableSpokenEmojis = false,

    // ── Model ─────────────────────────────────────────────────────────────
    this.model = SpeechModel.defaultModel,

    // ── Decoding ──────────────────────────────────────────────────────────
    this.autoDecoding = false,

    // ── Adaptation ────────────────────────────────────────────────────────
    this.speechContexts,

    // ── Real-time tuning ──────────────────────────────────────────────────
    this.chunkIntervalMs = 3000,
    this.minChunkSizeBytes = 1024,
  });

  // ────────────────────────────── Audio format ──────────────────────────────

  /// Audio encoding of the data sent to the API.
  ///
  /// For real-time streaming this is always overridden to [SpeechEncoding.linear16].
  /// For post-recording it should match the file's actual encoding.
  final SpeechEncoding encoding;

  /// Sample rate in Hertz.  Must match the audio source.
  ///
  /// Common values: `8000` (telephony), `16000` (wideband), `44100` (CD),
  /// `48000` (professional).
  final int sampleRateHertz;

  /// Number of audio channels.  For mono audio use `1`.
  ///
  /// If > 1 and [enableSeparateRecognitionPerChannel] is `true`, each channel
  /// is recognised independently.
  final int audioChannelCount;

  /// When `true` **and** [audioChannelCount] > 1, the API returns a separate
  /// result for each audio channel.
  final bool enableSeparateRecognitionPerChannel;

  // ─────────────────────────────── Language ──────────────────────────────────

  /// BCP-47 language code (e.g. `"en-US"`, `"ar-EG"`, `"fr-FR"`).
  ///
  /// This is the **primary** language the recogniser should expect.
  final String languageCode;

  /// Optional list of **additional** BCP-47 codes for multilingual audio.
  ///
  /// The API will attempt to detect which language is being spoken and switch
  /// accordingly.  Only a subset of language pairs is supported.
  final List<String>? alternativeLanguageCodes;

  // ──────────────────────────── Result options ───────────────────────────────

  /// Maximum number of alternative transcripts to return (1 – 30).
  ///
  /// Setting this > 1 populates [TranscriptionResult.alternatives].
  final int maxAlternatives;

  /// When `true`, the API attempts to filter out profanities by replacing them
  /// with asterisks.
  final bool profanityFilter;

  /// When `true`, each word in the transcript will include its start and end
  /// time offsets within the audio.
  ///
  /// Populates [WordInfo.startTime] and [WordInfo.endTime].
  final bool enableWordTimeOffsets;

  /// When `true`, each word gets an individual confidence score.
  ///
  /// Populates [WordInfo.confidence].
  final bool enableWordConfidence;

  /// When `true`, the API inserts punctuation automatically (commas, periods,
  /// question marks, etc.).
  final bool enableAutomaticPunctuation;

  /// When `true`, spoken punctuation like "period" or "comma" is included
  /// literally in the transcript.
  final bool enableSpokenPunctuation;

  /// When `true`, spoken emoji names (e.g. "smiley face") are converted to
  /// their emoji characters.
  final bool enableSpokenEmojis;

  // ─────────────────────────────── Model ─────────────────────────────────────

  /// The speech recognition model.
  ///
  /// See [SpeechModel] for descriptions of each option.
  final SpeechModel model;

  // ──────────────────────────── Decoding ─────────────────────────────────────

  /// When `true`, the V2 API uses `autoDecodingConfig` — it automatically
  /// detects the audio encoding from the file header (WAV, FLAC, OGG, etc.).
  ///
  /// When `false` (default), `explicitDecodingConfig` is used with the
  /// [encoding], [sampleRateHertz], and [audioChannelCount] values you
  /// provide.
  ///
  /// **Tip:** Use `autoDecoding: true` for post-recording of files with
  /// standard headers (WAV, FLAC). Use `false` (explicit) for real-time
  /// raw PCM, since PCM has no header.
  final bool autoDecoding;

  // ──────────────────────────── Adaptation ───────────────────────────────────

  /// Optional speech contexts (phrase hints) that bias the recogniser.
  ///
  /// See [SpeechContext] for details.
  final List<SpeechContext>? speechContexts;

  // ─────────────────────────── Real-time tuning ─────────────────────────────

  /// How often (in milliseconds) to drain the audio buffer and send a chunk
  /// to the Speech API when using [TranscriptionMode.realTime].
  ///
  /// Lower values = more responsive but more API calls.
  /// Higher values = fewer API calls but more latency.
  ///
  /// Default: 3000 ms (3 seconds).
  final int chunkIntervalMs;

  /// The minimum number of buffered bytes before a chunk is actually sent.
  ///
  /// If the buffer has fewer bytes than this at drain-time, the chunk is
  /// skipped to avoid sending near-empty requests (which waste quota and
  /// rarely produce useful results).
  ///
  /// Default: 1024 bytes.
  final int minChunkSizeBytes;

  // ─────────────────────────── Serialisation ─────────────────────────────────

  /// Converts this config into the V2 JSON body expected by the API's
  /// `RecognitionConfig` field.
  ///
  /// [overrideEncoding]    – used internally to force LINEAR16 for streaming.
  /// [overrideSampleRate]  – used internally to match the recording sample rate.
  /// [forceExplicit]       – when `true`, always uses `explicitDecodingConfig`
  ///                         regardless of [autoDecoding] (used for raw PCM
  ///                         chunks that have no header).
  Map<String, dynamic> toJson({
    SpeechEncoding? overrideEncoding,
    int? overrideSampleRate,
    bool forceExplicit = false,
  }) {
    final json = <String, dynamic>{};

    // ── Decoding config ──────────────────────────────────────────────────
    //    V2 uses either `autoDecodingConfig` (API detects format from
    //    headers) or `explicitDecodingConfig` (you specify encoding,
    //    sample rate, and channels).
    if (autoDecoding && !forceExplicit) {
      // Let the API auto-detect the encoding.
      json['autoDecodingConfig'] = <String, dynamic>{};
    } else {
      // Explicitly specify how to decode the audio.
      json['explicitDecodingConfig'] = {
        'encoding': (overrideEncoding ?? encoding).value,
        'sampleRateHertz': overrideSampleRate ?? sampleRateHertz,
        'audioChannelCount': audioChannelCount,
      };
    }

    // ── Language codes ───────────────────────────────────────────────────
    //    V2 uses `languageCodes` (an array).  The primary language comes
    //    first, followed by any alternatives.
    json['languageCodes'] = [languageCode, ...?alternativeLanguageCodes];

    // ── Model ────────────────────────────────────────────────────────────
    json['model'] = model.value;

    // ── Features ─────────────────────────────────────────────────────────
    //    V2 nests all feature flags under a single `features` object.
    json['features'] = {
      'maxAlternatives': maxAlternatives,
      'profanityFilter': profanityFilter,
      'enableWordTimeOffsets': enableWordTimeOffsets,
      'enableWordConfidence': enableWordConfidence,
      'enableAutomaticPunctuation': enableAutomaticPunctuation,
      'enableSpokenPunctuation': enableSpokenPunctuation,
      'enableSpokenEmojis': enableSpokenEmojis,
      if (enableSeparateRecognitionPerChannel)
        'multiChannelMode': 'SEPARATE_RECOGNITION_PER_CHANNEL',
    };

    // ── Adaptation ───────────────────────────────────────────────────────
    //    V2 uses `adaptation.phraseSets[]` with inline phrase sets.
    if (speechContexts != null && speechContexts!.isNotEmpty) {
      json['adaptation'] = {
        'phraseSets': speechContexts!.map((c) => c.toJson()).toList(),
      };
    }

    return json;
  }

  /// Returns a copy of this config with the given fields replaced.
  ///
  /// Useful for one-off overrides without mutating the original instance:
  /// ```dart
  /// final fast = baseConfig.copyWith(chunkIntervalMs: 1500);
  /// ```
  SpeechConfig copyWith({
    SpeechEncoding? encoding,
    int? sampleRateHertz,
    int? audioChannelCount,
    bool? enableSeparateRecognitionPerChannel,
    String? languageCode,
    List<String>? alternativeLanguageCodes,
    int? maxAlternatives,
    bool? profanityFilter,
    bool? enableWordTimeOffsets,
    bool? enableWordConfidence,
    bool? enableAutomaticPunctuation,
    bool? enableSpokenPunctuation,
    bool? enableSpokenEmojis,
    SpeechModel? model,
    bool? autoDecoding,
    List<SpeechContext>? speechContexts,
    int? chunkIntervalMs,
    int? minChunkSizeBytes,
  }) {
    return SpeechConfig(
      encoding: encoding ?? this.encoding,
      sampleRateHertz: sampleRateHertz ?? this.sampleRateHertz,
      audioChannelCount: audioChannelCount ?? this.audioChannelCount,
      enableSeparateRecognitionPerChannel:
          enableSeparateRecognitionPerChannel ??
          this.enableSeparateRecognitionPerChannel,
      languageCode: languageCode ?? this.languageCode,
      alternativeLanguageCodes:
          alternativeLanguageCodes ?? this.alternativeLanguageCodes,
      maxAlternatives: maxAlternatives ?? this.maxAlternatives,
      profanityFilter: profanityFilter ?? this.profanityFilter,
      enableWordTimeOffsets:
          enableWordTimeOffsets ?? this.enableWordTimeOffsets,
      enableWordConfidence: enableWordConfidence ?? this.enableWordConfidence,
      enableAutomaticPunctuation:
          enableAutomaticPunctuation ?? this.enableAutomaticPunctuation,
      enableSpokenPunctuation:
          enableSpokenPunctuation ?? this.enableSpokenPunctuation,
      enableSpokenEmojis: enableSpokenEmojis ?? this.enableSpokenEmojis,
      model: model ?? this.model,
      autoDecoding: autoDecoding ?? this.autoDecoding,
      speechContexts: speechContexts ?? this.speechContexts,
      chunkIntervalMs: chunkIntervalMs ?? this.chunkIntervalMs,
      minChunkSizeBytes: minChunkSizeBytes ?? this.minChunkSizeBytes,
    );
  }
}
