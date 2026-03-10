// ──────────────────────────────────────────────────────────────────────────────
// speech_recognizer_service.dart
//
// Lower-level service that communicates with the Google Cloud Speech-to-Text
// **V2** REST API using `dio`.
//
// V2 endpoints:
//   • Synchronous: POST .../recognizers/_:recognize
//   • Batch (long): POST .../recognizers/_:batchRecognize  (returns LRO)
//   • Operations poll: GET .../operations/{id}
//
// Responsibilities:
//   1. Send a short audio chunk and get a synchronous transcript.
//   2. Send a long audio file via batchRecognize and poll until done.
//   3. Parse the V2 API response into our model classes.
//
// This class does NOT know anything about microphones or recording. It only
// deals with API calls and JSON parsing.
// ──────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config/speech_config.dart';
import '../models/transcription_result.dart';
import '../models/word_info.dart';

/// Communicates with Google Cloud Speech-to-Text **V2** REST endpoints.
///
/// Two main operations:
///
/// | Method                 | API endpoint                     | Use-case       |
/// |------------------------|----------------------------------|----------------|
/// | [recognizeBytes]       | `recognizers/_:recognize`        | Short chunks   |
/// | [recognizeFile]        | `recognizers/_:recognize` **or** | Post-recording |
/// |                        | `recognizers/_:batchRecognize`   | (auto-selected)|
class SpeechRecognizerService {
  /// Creates a [SpeechRecognizerService].
  ///
  /// * [apiKey]    – Your Google Cloud API key with the Speech-to-Text API
  ///                enabled.
  /// * [projectId] – Your Google Cloud project ID (e.g. `'my-project-123'`).
  /// * [location]  – Processing location. Defaults to `'global'`.
  ///                Other options: `'us'`, `'eu'`, or a specific region like
  ///                `'us-central1'`.
  /// * [dio]       – An optional pre-configured [Dio] instance.
  SpeechRecognizerService({
    required String apiKey,
    required String projectId,
    String location = 'global',
    Dio? dio,
  }) : _apiKey = apiKey,
       _projectId = projectId,
       _location = location,
       _dio = dio ?? Dio();

  // ── Constants ──────────────────────────────────────────────────────────────

  /// V2 base URL.
  static const _baseUrl = 'https://speech.googleapis.com/v2';

  /// Audio files shorter than or equal to this many bytes are sent with the
  /// synchronous `recognize` endpoint.
  ///
  /// The API's hard limit for synchronous requests is ~1 minute of audio.
  /// 16 kHz × 16 bits × 1 channel × 60 s = 1 920 000 bytes.
  /// We use a slightly conservative threshold.
  static const int _syncBytesThreshold = 1800000;

  // ── Internals ──────────────────────────────────────────────────────────────

  /// The Google Cloud API key.
  final String _apiKey;

  /// The Google Cloud project ID.
  final String _projectId;

  /// The processing location (`global`, `us`, `eu`, or a region).
  final String _location;

  /// The HTTP client used for all API calls.
  final Dio _dio;

  /// Builds the V2 recognizer resource path.
  String get _recognizerPath =>
      'projects/$_projectId/locations/$_location/recognizers/_';

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Transcribes raw PCM audio **bytes** using the synchronous endpoint.
  ///
  /// This is the method called repeatedly by the real-time timer: each chunk
  /// of PCM data is base64-encoded and sent in a single request.
  ///
  /// Returns a [RecognizeResponse] containing the transcript and metadata,
  /// or `null` if nothing was recognised (e.g. silence).
  ///
  /// * [audioBytes]  – Raw LINEAR16 PCM bytes (no WAV header).
  /// * [config]      – The [SpeechConfig] controlling recognition options.
  Future<RecognizeResponse?> recognizeBytes(
    Uint8List audioBytes,
    SpeechConfig config,
  ) async {
    // Don't waste an API call on an empty buffer.
    if (audioBytes.isEmpty) return null;

    try {
      // ── 1. Base64-encode the raw audio ─────────────────────────────────
      //    The REST API expects audio in base64 when sent inline.
      final base64Audio = base64Encode(audioBytes);

      // ── 2. Build the V2 request body ──────────────────────────────────
      //    V2 puts `content` at the top level (not under `audio`).
      //    We force explicitDecodingConfig with LINEAR16 for raw PCM.
      final body = {
        'config': config.toJson(
          overrideEncoding: SpeechEncoding.linear16,
          forceExplicit: true,
        ),
        'content': base64Audio,
      };

      // ── 3. POST to V2 recognize endpoint ──────────────────────────────
      final response = await _dio.post<Map<String, dynamic>>(
        '$_baseUrl/$_recognizerPath:recognize',
        queryParameters: {'key': _apiKey},
        data: body,
      );

      // ── 4. Parse the response ──────────────────────────────────────────
      return _parseRecognizeResponse(response.data);
    } on DioException catch (e) {
      // Log the error but don't throw - the caller can retry on the next
      // chunk.
      debugPrint('[SpeechRecognizerService] DioException: ${e.message}');
      if (e.response != null) {
        debugPrint('[SpeechRecognizerService] Response: ${e.response?.data}');
      }
      return null;
    } on Exception catch (e) {
      debugPrint('[SpeechRecognizerService] Exception: $e');
      return null;
    }
  }

  /// Transcribes an audio **file** on disk.
  ///
  /// Automatically chooses the right API endpoint:
  /// * File ≤ ~1 min → synchronous `recognizers/_:recognize`.
  /// * File > ~1 min → `recognizers/_:batchRecognize` (LRO) + polling.
  ///
  /// [filePath] – Absolute path to the audio file.
  /// [config]   – The [SpeechConfig] controlling recognition options.
  /// [onProgress] – Optional callback invoked while polling a long-running
  ///                operation. Receives the progress percentage (0 – 100).
  ///
  /// Returns the parsed result, or `null` on failure.
  Future<RecognizeResponse?> recognizeFile(
    String filePath,
    SpeechConfig config, {
    void Function(int progressPercent)? onProgress,
  }) async {
    // ── 1. Read the file into memory ─────────────────────────────────────
    final file = File(filePath);
    if (!await file.exists()) {
      debugPrint('[SpeechRecognizerService] File not found: $filePath');
      return null;
    }

    final fileBytes = await file.readAsBytes();

    // ── 2. Choose sync vs. async based on file size ──────────────────────
    if (fileBytes.length <= _syncBytesThreshold) {
      // Short file → synchronous endpoint.
      return _recognizeSync(fileBytes, config);
    } else {
      // Long file → asynchronous endpoint + polling.
      return _recognizeLongRunning(fileBytes, config, onProgress: onProgress);
    }
  }

  // ── Private: synchronous recognition ───────────────────────────────────────

  /// Sends the full file bytes to the V2 synchronous endpoint.
  Future<RecognizeResponse?> _recognizeSync(
    Uint8List fileBytes,
    SpeechConfig config,
  ) async {
    try {
      // Base64-encode the entire file.
      final base64Audio = base64Encode(fileBytes);

      // V2 request: `content` at top level, config uses autoDecoding or
      // explicit depending on the SpeechConfig setting.
      final body = {'config': config.toJson(), 'content': base64Audio};

      final response = await _dio.post<Map<String, dynamic>>(
        '$_baseUrl/$_recognizerPath:recognize',
        queryParameters: {'key': _apiKey},
        data: body,
      );

      return _parseRecognizeResponse(response.data);
    } on DioException catch (e) {
      debugPrint('[SpeechRecognizerService] sync error: ${e.message}');
      if (e.response != null) {
        debugPrint('[SpeechRecognizerService] Response: ${e.response?.data}');
      }
      return null;
    }
  }

  // ── Private: long-running recognition ──────────────────────────────────────

  /// Sends the file to the V2 batchRecognize endpoint, then polls until
  /// the long-running operation completes.
  Future<RecognizeResponse?> _recognizeLongRunning(
    Uint8List fileBytes,
    SpeechConfig config, {
    void Function(int progressPercent)? onProgress,
  }) async {
    try {
      // ── 1. Base64-encode and submit ────────────────────────────────────
      final base64Audio = base64Encode(fileBytes);

      // V2 batchRecognize wraps files in a `files` array.
      // We use `inlineResult` to get the transcript directly in the
      // operation response rather than writing to GCS.
      final body = {
        'config': config.toJson(),
        'files': [
          {'content': base64Audio},
        ],
        'recognitionOutputConfig': {
          'inlineResponseConfig': <String, dynamic>{},
        },
      };

      final startResponse = await _dio.post<Map<String, dynamic>>(
        '$_baseUrl/$_recognizerPath:batchRecognize',
        queryParameters: {'key': _apiKey},
        data: body,
      );

      // ── 2. Extract the operation name ──────────────────────────────────
      //    The API returns an operation object with a `name` field that we
      //    use to poll for completion.
      final operationName = startResponse.data?['name'] as String?;
      if (operationName == null) {
        debugPrint('[SpeechRecognizerService] No operation name returned.');
        return null;
      }

      // ── 3. Poll until done ─────────────────────────────────────────────
      return _pollOperation(operationName, onProgress: onProgress);
    } on DioException catch (e) {
      debugPrint(
        '[SpeechRecognizerService] batchRecognize error: ${e.message}',
      );
      if (e.response != null) {
        debugPrint('[SpeechRecognizerService] Response: ${e.response?.data}');
      }
      return null;
    }
  }

  /// Polls a long-running operation until it finishes or times out.
  ///
  /// Uses exponential back-off: 2 s → 4 s → 8 s → … up to 30 s.
  Future<RecognizeResponse?> _pollOperation(
    String operationName, {
    void Function(int progressPercent)? onProgress,
    int maxAttempts = 120,
  }) async {
    // Start with a 2-second delay between polls.
    int delaySeconds = 2;

    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      // Wait before each poll (including the first one – the operation needs
      // time to start processing).
      await Future<void>.delayed(Duration(seconds: delaySeconds));

      try {
        // GET the operation status.  V2 operation names include the full
        // resource path, so we use it directly.
        final response = await _dio.get<Map<String, dynamic>>(
          '$_baseUrl/$operationName',
          queryParameters: {'key': _apiKey},
        );

        final data = response.data;
        if (data == null) continue;

        // ── Check metadata for progress ──────────────────────────────────
        final metadata = data['metadata'] as Map<String, dynamic>?;
        if (metadata != null && onProgress != null) {
          final percent = (metadata['progressPercent'] as num?)?.toInt() ?? 0;
          onProgress(percent);
        }

        // ── Check if the operation is complete ───────────────────────────
        final done = data['done'] as bool? ?? false;
        if (done) {
          // Check for errors in the operation response.
          if (data.containsKey('error')) {
            final error = data['error'] as Map<String, dynamic>;
            debugPrint(
              '[SpeechRecognizerService] Operation error: '
              '${error['message']}',
            );
            return null;
          }

          // Parse the final response.  For batchRecognize the results
          // live under `response.results.{key}.inlineResult.transcript`.
          final resultData = data['response'] as Map<String, dynamic>?;
          return _parseBatchResponse(resultData) ??
              _parseRecognizeResponse(resultData);
        }
      } on DioException catch (e) {
        debugPrint('[SpeechRecognizerService] poll error: ${e.message}');
        // Continue polling – transient network errors shouldn't abort.
      }

      // ── Exponential back-off: double the delay up to 30 seconds ────────
      delaySeconds = (delaySeconds * 2).clamp(2, 30);
    }

    debugPrint(
      '[SpeechRecognizerService] Polling timed out after $maxAttempts attempts.',
    );
    return null;
  }

  // ── Response parsing (V2) ───────────────────────────────────────────────────

  /// Parses a V2 batchRecognize operation response.
  ///
  /// The structure is:
  /// ```json
  /// { "results": { "<key>": { "inlineResult": { "transcript": { "results": [...] } } } } }
  /// ```
  RecognizeResponse? _parseBatchResponse(Map<String, dynamic>? data) {
    if (data == null) return null;
    final results = data['results'] as Map<String, dynamic>?;
    if (results == null || results.isEmpty) return null;

    // Take the first (and typically only) file result.
    final firstResult =
        results.values.first as Map<String, dynamic>? ?? <String, dynamic>{};
    final inlineResult = firstResult['inlineResult'] as Map<String, dynamic>?;
    if (inlineResult == null) return null;

    final transcript = inlineResult['transcript'] as Map<String, dynamic>?;
    return _parseRecognizeResponse(transcript);
  }

  /// Parses the JSON body returned by the V2 `recognize` endpoint (or the
  /// inner `transcript` of a batchRecognize result).
  RecognizeResponse? _parseRecognizeResponse(Map<String, dynamic>? data) {
    if (data == null) return null;

    // The `results` array contains one entry per utterance / segment.
    final results = data['results'] as List<dynamic>?;
    if (results == null || results.isEmpty) return null;

    // We accumulate text, words, and alternatives across all result segments.
    final transcriptParts = <String>[];
    double? bestConfidence;
    final allWords = <WordInfo>[];
    final allAlternatives = <SpeechAlternative>[];

    for (final result in results) {
      // Each result contains an `alternatives` array sorted by confidence.
      final alternatives = result['alternatives'] as List<dynamic>?;
      if (alternatives == null || alternatives.isEmpty) continue;

      // The first alternative is always the highest-confidence one.
      final best = alternatives.first as Map<String, dynamic>;

      // ── Transcript text ────────────────────────────────────────────────
      final text = best['transcript'] as String? ?? '';
      if (text.isNotEmpty) transcriptParts.add(text);

      // ── Confidence ─────────────────────────────────────────────────────
      final conf = (best['confidence'] as num?)?.toDouble();
      if (conf != null) {
        bestConfidence = (bestConfidence == null)
            ? conf
            // Average across segments for an overall score.
            : (bestConfidence + conf) / 2;
      }

      // ── Word info ──────────────────────────────────────────────────────
      final words = best['words'] as List<dynamic>?;
      if (words != null) {
        allWords.addAll(
          words.map((w) => WordInfo.fromJson(w as Map<String, dynamic>)),
        );
      }

      // ── Additional alternatives ────────────────────────────────────────
      if (alternatives.length > 1) {
        for (int i = 1; i < alternatives.length; i++) {
          allAlternatives.add(
            SpeechAlternative.fromJson(alternatives[i] as Map<String, dynamic>),
          );
        }
      }
    }

    if (transcriptParts.isEmpty) return null;

    return RecognizeResponse(
      transcript: transcriptParts.join(' ').trim(),
      confidence: bestConfidence,
      words: allWords.isNotEmpty ? allWords : null,
      alternatives: allAlternatives.isNotEmpty ? allAlternatives : null,
    );
  }

  // ── Cleanup ────────────────────────────────────────────────────────────────

  /// Closes the underlying HTTP client.
  ///
  /// Call this when you're done with the service.
  void dispose() {
    _dio.close();
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Internal data class for raw API responses.
//
// This is intentionally *private* to this file (prefixed with `_`). The public
// API exposes only [TranscriptionResult].
// ──────────────────────────────────────────────────────────────────────────────

/// Intermediate data class holding parsed recognition results.
///
/// Used internally to pass data from the recogniser to the main service,
/// which then wraps it into a [TranscriptionResult].
class RecognizeResponse {
  const RecognizeResponse({
    required this.transcript,
    this.confidence,
    this.words,
    this.alternatives,
  });

  /// The best transcript text.
  final String transcript;

  /// Overall confidence score.
  final double? confidence;

  /// Word-level details (if requested).
  final List<WordInfo>? words;

  /// Additional alternative transcripts (if requested).
  final List<SpeechAlternative>? alternatives;
}
