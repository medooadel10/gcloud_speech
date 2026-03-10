// ──────────────────────────────────────────────────────────────────────────────
// example.dart
//
// ignore_for_file: non_constant_identifier_names
//
// Complete example demonstrating every feature of the `gcloud_speech` package.
//
// Run this file as a standalone Flutter app to try out:
//   • Real-time transcription (live captions while recording)
//   • Post-recording transcription (full-file transcription after stop)
//   • Record-only mode (no transcription)
//   • Pause / resume during recording
//   • All available configuration options
//
// IMPORTANT: Replace 'YOUR_GOOGLE_CLOUD_API_KEY' with a valid API key that
//            has the "Cloud Speech-to-Text API" enabled.
//            Replace 'YOUR_PROJECT_ID' with your Google Cloud project ID.
// ──────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:gcloud_speech/gcloud_speech.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// EXAMPLE 1 — Minimal real-time transcription
//
// This is the simplest possible usage:
//   1. Create the service with your API key and language.
//   2. Start recording in real-time mode.
//   3. Listen to liveTranscript for updates.
//   4. Stop when done.
// ═══════════════════════════════════════════════════════════════════════════════

Future<void> example1_minimalRealTime() async {
  // ── Step 1: Create the service ──────────────────────────────────────────
  // The required parameters are `apiKey` and `projectId`.  SpeechConfig
  // defaults to English (en-US) with automatic punctuation enabled.
  final service = GCloudSpeech(
    apiKey: 'YOUR_GOOGLE_CLOUD_API_KEY',
    projectId: 'YOUR_PROJECT_ID',
    speechConfig: const SpeechConfig(languageCode: 'en-US'),
  );

  // ── Step 2: Check microphone permission ──────────────────────────────────
  // Always request permission before starting.  On iOS/Android a system
  // dialog will appear the first time.
  final hasPermission = await service.checkPermission();
  if (!hasPermission) {
    debugPrint('Microphone permission denied.');
    return;
  }

  // ── Step 3: Start recording with real-time transcription ────────────────
  // `TranscriptionMode.realTime` opens a parallel PCM stream and sends
  // audio chunks to the Speech API every 3 seconds (configurable via
  // `SpeechConfig.chunkIntervalMs`).
  final filePath = await service.startRecording(
    mode: TranscriptionMode.realTime,
  );
  debugPrint('Recording started.  File will be saved to: $filePath');

  // ── Step 4: Listen for live transcript updates ──────────────────────────
  // `liveTranscript` is a ValueNotifier<String> that updates every time a
  // chunk is transcribed.  In a real app you'd use ValueListenableBuilder.
  service.liveTranscript.addListener(() {
    debugPrint('Live transcript: ${service.liveTranscript.value}');
  });

  // ── (Simulate some recording time) ──────────────────────────────────────
  await Future<void>.delayed(const Duration(seconds: 10));

  // ── Step 5: Stop and get the result ─────────────────────────────────────
  // `stopRecording()` drains the last chunk, stops the recorders, and
  // returns a TranscriptionResult with the audio path + transcript.
  final result = await service.stopRecording();

  debugPrint('──────────── Result ────────────');
  debugPrint('Audio file : ${result.audioPath}');
  debugPrint('Transcript : ${result.transcript}');
  debugPrint('────────────────────────────────');

  // ── Step 6: Clean up ────────────────────────────────────────────────────
  await service.dispose();
}

// ═══════════════════════════════════════════════════════════════════════════════
// EXAMPLE 2 — Post-recording transcription
//
// Records audio first, then sends the full file to the Speech API after
// stopping.  Best when you don't need live captions and want maximum accuracy.
// ═══════════════════════════════════════════════════════════════════════════════

Future<void> example2_afterRecording() async {
  // ── Create the service with word-level timing enabled ───────────────────
  // Setting `enableWordTimeOffsets: true` tells the API to return the start
  // and end time of every word — useful for highlighting or subtitle sync.
  final service = GCloudSpeech(
    apiKey: 'YOUR_GOOGLE_CLOUD_API_KEY',
    projectId: 'YOUR_PROJECT_ID',
    speechConfig: const SpeechConfig(
      languageCode: 'en-US',
      enableAutomaticPunctuation: true,
      enableWordTimeOffsets: true,
      enableWordConfidence: true,
      model: SpeechModel.latestLong,
    ),
  );

  // Start recording in after-recording mode.
  await service.startRecording(mode: TranscriptionMode.afterRecording);
  debugPrint('Recording... speak now!');

  // Record for 15 seconds.
  await Future<void>.delayed(const Duration(seconds: 15));

  // Stop — this call will WAIT until the full transcript is ready.
  // For files > 1 minute the package automatically uses the long-running
  // API and polls until done.
  final result = await service.stopRecording();

  debugPrint('Audio path  : ${result.audioPath}');
  debugPrint('Transcript  : ${result.transcript}');
  debugPrint('Confidence  : ${result.confidence}');
  debugPrint('Duration    : ${result.audioDuration}');

  // Print every word with its timing.
  if (result.words != null) {
    for (final word in result.words!) {
      debugPrint(
        '  "${word.word}" '
        '${word.startTime.inMilliseconds}ms → '
        '${word.endTime.inMilliseconds}ms  '
        '(conf: ${word.confidence})',
      );
    }
  }

  await service.dispose();
}

// ═══════════════════════════════════════════════════════════════════════════════
// EXAMPLE 3 — Record-only (no transcription)
//
// Sometimes you just need the audio file — skip transcription entirely.
// ═══════════════════════════════════════════════════════════════════════════════

Future<void> example3_recordOnly() async {
  final service = GCloudSpeech(
    apiKey: 'YOUR_GOOGLE_CLOUD_API_KEY',
    projectId: 'YOUR_PROJECT_ID',
  );

  // `TranscriptionMode.none` — no PCM stream, no API calls.
  await service.startRecording(mode: TranscriptionMode.none);

  await Future<void>.delayed(const Duration(seconds: 5));

  final result = await service.stopRecording();
  debugPrint('Saved to: ${result.audioPath}');
  // result.transcript is null in this mode.

  await service.dispose();
}

// ═══════════════════════════════════════════════════════════════════════════════
// EXAMPLE 4 — Pause & Resume
//
// Demonstrates pausing and resuming mid-recording.
// ═══════════════════════════════════════════════════════════════════════════════

Future<void> example4_pauseResume() async {
  final service = GCloudSpeech(
    apiKey: 'YOUR_GOOGLE_CLOUD_API_KEY',
    projectId: 'YOUR_PROJECT_ID',
    speechConfig: const SpeechConfig(languageCode: 'en-US'),
  );

  await service.startRecording(mode: TranscriptionMode.realTime);
  debugPrint('Recording...');

  // Record for 5 seconds.
  await Future<void>.delayed(const Duration(seconds: 5));

  // Pause — the microphone stops capturing, the chunk timer idles.
  await service.pauseRecording();
  debugPrint('Paused.  State: ${service.recordingState.value}');

  // Wait 3 seconds (no audio captured during this time).
  await Future<void>.delayed(const Duration(seconds: 3));

  // Resume — microphone reopens, chunks flow again.
  await service.resumeRecording();
  debugPrint('Resumed.  State: ${service.recordingState.value}');

  await Future<void>.delayed(const Duration(seconds: 5));

  final result = await service.stopRecording();
  debugPrint('Final transcript: ${result.transcript}');

  await service.dispose();
}

// ═══════════════════════════════════════════════════════════════════════════════
// EXAMPLE 5 — Cancel a recording
//
// Demonstrates discarding a recording without saving or transcribing.
// ═══════════════════════════════════════════════════════════════════════════════

Future<void> example5_cancel() async {
  final service = GCloudSpeech(
    apiKey: 'YOUR_GOOGLE_CLOUD_API_KEY',
    projectId: 'YOUR_PROJECT_ID',
    speechConfig: const SpeechConfig(languageCode: 'en-US'),
  );

  await service.startRecording(mode: TranscriptionMode.realTime);
  debugPrint('Recording...');

  await Future<void>.delayed(const Duration(seconds: 3));

  // Cancel — no file saved, no transcript.
  await service.cancelRecording();
  debugPrint('Recording cancelled.  State: ${service.recordingState.value}');

  await service.dispose();
}

// ═══════════════════════════════════════════════════════════════════════════════
// EXAMPLE 6 — Full configuration showcase
//
// Demonstrates every configurable option in both SpeechConfig and
// RecordingConfig.
// ═══════════════════════════════════════════════════════════════════════════════

Future<void> example6_fullConfig() async {
  // ── Speech API configuration ────────────────────────────────────────────
  const speechConfig = SpeechConfig(
    // ── Language ──────────────────────────────────────────────────────────
    // Primary language the recogniser should expect.
    languageCode: 'en-US',

    // Optional additional languages for multilingual audio.
    alternativeLanguageCodes: ['es-ES', 'fr-FR'],

    // ── Audio format ──────────────────────────────────────────────────────
    // Encoding of the audio sent to the API (overridden to LINEAR16 for
    // real-time; used as-is for post-recording).
    encoding: SpeechEncoding.linear16,

    // Sample rate must match the RecordingConfig.
    sampleRateHertz: 16000,

    // Number of channels (1 = mono, 2 = stereo).
    audioChannelCount: 1,

    // When true + stereo, each channel is transcribed separately.
    enableSeparateRecognitionPerChannel: false,

    // ── Result options ────────────────────────────────────────────────────
    // Max alternative transcripts to return (1 – 30).
    maxAlternatives: 3,

    // Filter profanity by replacing with asterisks.
    profanityFilter: false,

    // Include word-level start/end times.
    enableWordTimeOffsets: true,

    // Include per-word confidence scores.
    enableWordConfidence: true,

    // Insert commas, periods, question marks automatically.
    enableAutomaticPunctuation: true,

    // Recognise spoken punctuation ("period", "comma", …).
    enableSpokenPunctuation: false,

    // Convert spoken emoji names to emoji characters.
    enableSpokenEmojis: false,

    // ── Model ─────────────────────────────────────────────────────────────
    // The recognition model to use.
    model: SpeechModel.latestLong,

    // V2 always uses the best available model variant — `useEnhanced`
    // is no longer needed.

    // Let V2 auto-detect the audio encoding from the file header.
    // Set `autoDecoding: false` to manually specify encoding/sampleRate.
    autoDecoding: true,

    // ── Adaptation ────────────────────────────────────────────────────────
    // Boost domain-specific vocabulary.
    speechContexts: [
      SpeechContext(
        phrases: ['Flutter', 'Dart', 'gcloud_speech', 'Voicemize'],
        boost: 15.0,
      ),
    ],

    // ── Real-time tuning ──────────────────────────────────────────────────
    // How often to send chunks (milliseconds).  Lower = more responsive.
    chunkIntervalMs: 2000,

    // Don't send chunks smaller than this (bytes).
    minChunkSizeBytes: 512,
  );

  // ── Recording hardware configuration ────────────────────────────────────
  const recordingConfig = RecordingConfig(
    // Encoder for the file saved to disk.
    encoder: AudioFileEncoder.wav,

    // Sample rate — must match speechConfig.sampleRateHertz.
    sampleRate: 16000,

    // Bit rate (only used by lossy encoders like AAC).
    bitRate: 128000,

    // Number of channels.
    numChannels: 1,

    // OS-level Automatic Gain Control.
    autoGain: true,

    // OS-level echo cancellation.
    echoCancel: false,

    // OS-level noise suppression.
    noiseSuppress: true,

    // Custom prefix for the generated file name.
    fileNamePrefix: 'meeting',

    // Custom output directory (null = app documents directory).
    outputDirectory: null,
  );

  // ── Create the service with both configs ────────────────────────────────
  final service = GCloudSpeech(
    apiKey: 'YOUR_GOOGLE_CLOUD_API_KEY',
    projectId: 'YOUR_PROJECT_ID',
    speechConfig: speechConfig,
    recordingConfig: recordingConfig,

    // Optional error callback for non-fatal errors (e.g. a single chunk
    // fails but the recording continues).
    onError: (message) {
      debugPrint('⚠️  Non-fatal error: $message');
    },
  );

  // ── Start with real-time transcription ──────────────────────────────────
  final path = await service.startRecording(mode: TranscriptionMode.realTime);
  debugPrint('Recording to: $path');

  // ── Listen for live updates ─────────────────────────────────────────────
  service.liveTranscript.addListener(() {
    debugPrint('LIVE ► ${service.liveTranscript.value}');
  });

  // ── Use recordingState to update UI ─────────────────────────────────────
  service.recordingState.addListener(() {
    debugPrint('State changed → ${service.recordingState.value}');
  });

  // Simulate 10 seconds of recording.
  await Future<void>.delayed(const Duration(seconds: 10));

  // ── Stop and get full result ────────────────────────────────────────────
  final result = await service.stopRecording();

  debugPrint('═══════════ RESULT ═══════════');
  debugPrint('Audio path   : ${result.audioPath}');
  debugPrint('Transcript   : ${result.transcript}');
  debugPrint('Confidence   : ${result.confidence}');
  debugPrint('Duration     : ${result.audioDuration}');
  debugPrint('Words        : ${result.words?.length ?? 0}');
  debugPrint('Alternatives : ${result.alternatives?.length ?? 0}');

  // Print alternatives (if maxAlternatives > 1).
  for (final alt in result.alternatives ?? []) {
    debugPrint('  ALT: "${alt.transcript}" (conf: ${alt.confidence})');
  }

  debugPrint('══════════════════════════════');

  await service.dispose();
}

// ═══════════════════════════════════════════════════════════════════════════════
// EXAMPLE 7 — Arabic language support
//
// Demonstrates using a non-English language.
// ═══════════════════════════════════════════════════════════════════════════════

Future<void> example7_arabicLanguage() async {
  final service = GCloudSpeech(
    apiKey: 'YOUR_GOOGLE_CLOUD_API_KEY',
    projectId: 'YOUR_PROJECT_ID',
    speechConfig: const SpeechConfig(
      // Egyptian Arabic
      languageCode: 'ar-EG',
      enableAutomaticPunctuation: true,
      model: SpeechModel.latestLong,
    ),
  );

  await service.startRecording(mode: TranscriptionMode.realTime);

  service.liveTranscript.addListener(() {
    debugPrint('نص مباشر: ${service.liveTranscript.value}');
  });

  await Future<void>.delayed(const Duration(seconds: 10));

  final result = await service.stopRecording();
  debugPrint('النص النهائي: ${result.transcript}');

  await service.dispose();
}

// ═══════════════════════════════════════════════════════════════════════════════
// EXAMPLE 8 — Using copyWith for one-off config changes
//
// Demonstrates how to create a mutated config without changing the original.
// ═══════════════════════════════════════════════════════════════════════════════

Future<void> example8_copyWith() async {
  // A base config used across your app.
  const baseConfig = SpeechConfig(
    languageCode: 'en-US',
    model: SpeechModel.latestLong,
    enableAutomaticPunctuation: true,
  );

  // For one specific screen, you want faster real-time updates.
  final fastConfig = baseConfig.copyWith(
    chunkIntervalMs: 1500,
    minChunkSizeBytes: 256,
  );

  final service = GCloudSpeech(
    apiKey: 'YOUR_GOOGLE_CLOUD_API_KEY',
    projectId: 'YOUR_PROJECT_ID',
    speechConfig: fastConfig,
  );

  await service.startRecording(mode: TranscriptionMode.realTime);

  await Future<void>.delayed(const Duration(seconds: 8));

  final result = await service.stopRecording();
  debugPrint('Transcript: ${result.transcript}');

  await service.dispose();
}

// ═══════════════════════════════════════════════════════════════════════════════
// EXAMPLE 9 — Post-recording with progress tracking
//
// For long audio files (> 1 min) the package uses the long-running API.
// You can track progress via the `transcriptionProgress` notifier.
// ═══════════════════════════════════════════════════════════════════════════════

Future<void> example9_longRecordingProgress() async {
  final service = GCloudSpeech(
    apiKey: 'YOUR_GOOGLE_CLOUD_API_KEY',
    projectId: 'YOUR_PROJECT_ID',
    speechConfig: const SpeechConfig(
      languageCode: 'en-US',
      model: SpeechModel.latestLong,
    ),
  );

  // Listen for progress updates.
  service.transcriptionProgress.addListener(() {
    debugPrint(
      'Transcription progress: ${service.transcriptionProgress.value}%',
    );
  });

  await service.startRecording(mode: TranscriptionMode.afterRecording);

  // Simulate a long recording (2 minutes).
  await Future<void>.delayed(const Duration(minutes: 2));

  // This will block until the long-running transcription finishes.
  final result = await service.stopRecording();
  debugPrint('Done! Transcript: ${result.transcript}');

  await service.dispose();
}

// ═══════════════════════════════════════════════════════════════════════════════
// FLUTTER APP — A minimal Material app that ties the examples together.
//
// Tap buttons to run each example.  In a real app you'd build a full UI with
// ValueListenableBuilder for live updates.
// ═══════════════════════════════════════════════════════════════════════════════

void main() => runApp(const ExampleApp());

/// Root widget for the example app.
class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'gcloud_speech example',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
      home: const ExampleHomePage(),
    );
  }
}

/// Home page listing all examples.
class ExampleHomePage extends StatelessWidget {
  const ExampleHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    // A list of example names and their functions.
    final examples = <(String, Future<void> Function())>[
      ('1 — Minimal real-time', example1_minimalRealTime),
      ('2 — After recording', example2_afterRecording),
      ('3 — Record only', example3_recordOnly),
      ('4 — Pause & resume', example4_pauseResume),
      ('5 — Cancel recording', example5_cancel),
      ('6 — Full config showcase', example6_fullConfig),
      ('7 — Arabic language', example7_arabicLanguage),
      ('8 — copyWith configs', example8_copyWith),
      ('9 — Long recording progress', example9_longRecordingProgress),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('gcloud_speech examples')),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: examples.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final (name, fn) = examples[index];
          return ElevatedButton(onPressed: () => fn(), child: Text(name));
        },
      ),
    );
  }
}
