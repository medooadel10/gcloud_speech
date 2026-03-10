# gcloud_speech

A comprehensive Flutter package for **Google Cloud Speech-to-Text V2** that combines audio recording with transcription in a single, easy-to-use API.

---

## Features

| Feature | Description |
|---------|-------------|
| **Recording** | Start / pause / resume / stop / cancel audio recording |
| **Real-time transcription** | Live captions while recording — `liveTranscript` updates incrementally |
| **Post-recording transcription** | Full-file transcription after recording stops (sync + long-running) |
| **Record-only mode** | Capture audio without any transcription |
| **Auto long-running** | Files > 1 min automatically use `batchRecognize` with polling |
| **Progress tracking** | `transcriptionProgress` notifier for long-running jobs |
| **Word-level timing** | Start/end time offsets for every word |
| **Word confidence** | Per-word confidence scores |
| **Multiple alternatives** | Up to 30 alternative transcripts |
| **Speech adaptation** | Phrase hints with boost values |
| **Multilingual** | Primary + alternative language codes |
| **Profanity filter** | Optionally mask profanity |
| **Spoken punctuation** | Recognise "period", "comma", etc. |
| **Spoken emojis** | Convert "smiley face" to emoji |
| **Model selection** | `latestLong`, `latestShort`, `phoneCall`, `video`, and more |
| **Auto decoding** | Let V2 auto-detect encoding, or specify explicitly |
| **Recording config** | Encoder, sample rate, bit rate, channels, AGC, AEC, noise suppression |
| **Custom file naming** | Prefix + custom output directory |
| **Error callback** | `onError` for non-fatal errors during real-time transcription |
| **copyWith** | Easily derive config variants for specific screens |

---

## Getting started

### 1. Enable the API

Go to the [Google Cloud Console](https://console.cloud.google.com/), enable the **Cloud Speech-to-Text API**, and create an API key.

### 2. Add the dependency

In your app's `pubspec.yaml`:

```yaml
dependencies:
  gcloud_speech:
    path: ../gcloud_speech   # or wherever the package lives
```

### 3. Platform setup

#### Android

Add microphone permission to `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.RECORD_AUDIO" />
```

Set `minSdkVersion` to at least **21** in `android/app/build.gradle.kts`.

#### iOS

Add these keys to `ios/Runner/Info.plist`:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>We need microphone access to record and transcribe audio.</string>
```

---

## Usage

### Import

```dart
import 'package:gcloud_speech/gcloud_speech.dart';
```

This single import gives you access to all public classes:

| Class | Purpose |
|-------|---------|
| `GCloudSpeechService` | Main facade — the only class you interact with |
| `SpeechConfig` | Google Speech API configuration |
| `RecordingConfig` | Audio recording hardware configuration |
| `TranscriptionMode` | When/how to transcribe (realTime / afterRecording / none) |
| `RecordingState` | Recording lifecycle (idle / recording / paused) |
| `TranscriptionResult` | Return value of `stopRecording()` |
| `WordInfo` | Word-level timing + confidence |
| `SpeechAlternative` | Alternative transcript |
| `SpeechModel` | Speech recognition model enum |
| `SpeechEncoding` | Audio encoding enum |
| `SpeechContext` | Phrase hints for speech adaptation |
| `AudioFileEncoder` | File encoder enum for recording |

---

### Example 1 — Real-time transcription (simplest)

```dart
// 1. Create the service.
final service = GCloudSpeechService(
  apiKey: 'YOUR_API_KEY',
  projectId: 'YOUR_PROJECT_ID',
  speechConfig: const SpeechConfig(languageCode: 'en-US'),
);

// 2. Check permission.
if (!await service.checkPermission()) return;

// 3. Start recording with live captions.
await service.startRecording(mode: TranscriptionMode.realTime);

// 4. React to live updates.
service.liveTranscript.addListener(() {
  print('Live: ${service.liveTranscript.value}');
});

// 5. Stop and get the result.
final result = await service.stopRecording();
print(result.audioPath);    // '/data/.../audio_17...wav'
print(result.transcript);   // 'Hello, how are you?'

// 6. Clean up.
await service.dispose();
```

---

### Example 2 — Post-recording transcription

```dart
final service = GCloudSpeechService(
  apiKey: 'YOUR_API_KEY',
  projectId: 'YOUR_PROJECT_ID',
  speechConfig: const SpeechConfig(
    languageCode: 'en-US',
    enableWordTimeOffsets: true,   // get word timing
    enableWordConfidence: true,    // get per-word confidence
    model: SpeechModel.latestLong, // best for long audio
  ),
);

await service.startRecording(mode: TranscriptionMode.afterRecording);

// ... user records for any duration ...

// stopRecording() WAITS until transcription is complete.
final result = await service.stopRecording();

print(result.transcript);   // full text
print(result.confidence);   // overall confidence (0.0 – 1.0)

for (final word in result.words ?? []) {
  print('"${word.word}" ${word.startTime} → ${word.endTime}');
}
```

For files > 1 minute, the package automatically uses `batchRecognize` and polls until done. Track progress via:

```dart
service.transcriptionProgress.addListener(() {
  print('${service.transcriptionProgress.value}%');
});
```

---

### Example 3 — Pause & resume

```dart
await service.startRecording(mode: TranscriptionMode.realTime);

// Pause — microphone stops, no chunks sent.
await service.pauseRecording();

// Resume — microphone reopens, chunks flow again.
await service.resumeRecording();

// Stop.
final result = await service.stopRecording();
```

---

### Example 4 — Cancel (discard)

```dart
await service.startRecording(mode: TranscriptionMode.realTime);

// Discard everything — no file saved, no transcript.
await service.cancelRecording();
```

---

### Example 5 — Record only (no transcription)

```dart
await service.startRecording(mode: TranscriptionMode.none);

final result = await service.stopRecording();
print(result.audioPath);   // path to the file
print(result.transcript);  // null
```

---

### Full SpeechConfig reference

```dart
const config = SpeechConfig(
  // ── Required ──────────────────────────────────────────────
  languageCode: 'en-US',           // BCP-47 code

  // ── Optional language ─────────────────────────────────────
  alternativeLanguageCodes: ['es-ES', 'fr-FR'],

  // ── Audio format ──────────────────────────────────────────
  encoding: SpeechEncoding.linear16,
  sampleRateHertz: 16000,
  audioChannelCount: 1,
  enableSeparateRecognitionPerChannel: false,

  // ── Result options ────────────────────────────────────────
  maxAlternatives: 1,              // 1 – 30
  profanityFilter: false,
  enableWordTimeOffsets: false,
  enableWordConfidence: false,
  enableAutomaticPunctuation: true,
  enableSpokenPunctuation: false,
  enableSpokenEmojis: false,

  // ── Model ─────────────────────────────────────────────────
  model: SpeechModel.defaultModel,
  autoDecoding: true,              // let V2 auto-detect encoding

  // ── Adaptation ────────────────────────────────────────────
  speechContexts: [
    SpeechContext(phrases: ['Flutter', 'Dart'], boost: 15),
  ],

  // ── Real-time tuning ──────────────────────────────────────
  chunkIntervalMs: 3000,           // ms between chunk sends
  minChunkSizeBytes: 1024,         // skip tiny chunks
);
```

---

### Full RecordingConfig reference

```dart
const config = RecordingConfig(
  encoder: AudioFileEncoder.wav,    // file format
  sampleRate: 16000,                // Hz
  bitRate: 128000,                  // bps (lossy only)
  numChannels: 1,                   // 1 = mono, 2 = stereo
  autoGain: false,                  // OS AGC
  echoCancel: false,                // OS AEC
  noiseSuppress: false,             // OS noise suppression
  fileNamePrefix: 'audio',          // file name prefix
  outputDirectory: null,            // null = app docs dir
);
```

---

## Architecture

```
┌─────────────────────────────────────────────────┐
│              GCloudSpeechService                 │  ← public facade
│  ┌──────────────────┐  ┌──────────────────────┐ │
│  │ AudioRecorder     │  │ SpeechRecognizer      │ │  ← internal services
│  │ Service           │  │ Service               │ │
│  │                   │  │                       │ │
│  │ • record pkg      │  │ • dio (REST)          │ │
│  │ • file + stream   │  │ • recognize           │ │
│  │ • pause/resume    │  │ • batchRecognize      │ │
│  └──────────────────┘  └──────────────────────┘ │
└─────────────────────────────────────────────────┘
```

**Files:**

```
lib/
  gcloud_speech.dart                        ← barrel export
  src/
    gcloud_speech_service.dart              ← main facade
    enums/
      recording_state.dart                  ← idle / recording / paused
      transcription_mode.dart               ← realTime / afterRecording / none
    config/
      speech_config.dart                    ← API config (20+ options)
      recording_config.dart                 ← hardware config (10+ options)
    models/
      transcription_result.dart             ← result + SpeechAlternative
      word_info.dart                        ← per-word timing
    services/
      audio_recorder_service.dart           ← record package wrapper
      speech_recognizer_service.dart        ← Google REST API wrapper
example/
  example.dart                              ← 9 runnable examples
```

---

## API Summary

### GCloudSpeechService

| Method / Property | Description |
|---|---|
| `GCloudSpeechService({apiKey, projectId, location, speechConfig, recordingConfig, onError})` | Constructor |
| `checkPermission()` | Request microphone permission |
| `startRecording({mode})` | Start recording → returns file path |
| `pauseRecording()` | Pause the active recording |
| `resumeRecording()` | Resume a paused recording |
| `stopRecording()` | Stop → returns `TranscriptionResult` |
| `cancelRecording()` | Discard the recording |
| `recordingState` | `ValueNotifier<RecordingState>` |
| `liveTranscript` | `ValueNotifier<String>` (real-time mode) |
| `transcriptionProgress` | `ValueNotifier<int>` (after-recording mode) |
| `speechConfig` | Current `SpeechConfig` |
| `recordingConfig` | Current `RecordingConfig` |
| `activeMode` | Current `TranscriptionMode` |
| `currentFilePath` | Path of the current/latest recording |
| `dispose()` | Release all resources |

### TranscriptionResult

| Field | Type | Description |
|---|---|---|
| `audioPath` | `String?` | Path to the audio file |
| `transcript` | `String?` | Best transcript text |
| `confidence` | `double?` | Overall confidence (0.0 – 1.0) |
| `words` | `List<WordInfo>?` | Word-level timing + confidence |
| `audioDuration` | `Duration?` | Audio duration (from word offsets) |
| `alternatives` | `List<SpeechAlternative>?` | Alternative transcripts |

---

## License

Private package — not published to pub.dev.
# gcloud_speech
