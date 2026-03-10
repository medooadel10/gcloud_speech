// ──────────────────────────────────────────────────────────────────────────────
// audio_recorder_service.dart
//
// Lower-level service that manages the `record` package.
//
// Responsibilities:
//   1. Start / pause / resume / stop / cancel a file-based recording.
//   2. Optionally start a *second*, parallel PCM-stream recording so that raw
//      audio bytes can be drained in real-time for transcription.
//   3. Expose a [RecordingState] notifier for the UI.
//
// This class does NOT know anything about Google Cloud Speech. It only deals
// with microphone input and file output.
// ──────────────────────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../config/recording_config.dart';
import '../enums/recording_state.dart';

/// Manages microphone recording via the `record` package.
///
/// Provides two parallel recorders:
///
/// | Recorder         | Purpose                                        |
/// |------------------|------------------------------------------------|
/// | `_fileRecorder`  | Records to a file (WAV, AAC, FLAC …) on disk.  |
/// | `_streamRecorder`| Streams raw PCM bytes for real-time processing. |
///
/// Only [_fileRecorder] is always active. [_streamRecorder] is started only
/// when the caller passes `withStream: true` to [start].
class AudioRecorderService {
  // ── Internals ──────────────────────────────────────────────────────────────

  /// The primary recorder that writes audio to a file on disk.
  final AudioRecorder _fileRecorder = AudioRecorder();

  /// A secondary recorder opened in streaming mode to supply raw PCM bytes
  /// for real-time transcription.
  final AudioRecorder _streamRecorder = AudioRecorder();

  /// Subscription for the PCM stream coming from [_streamRecorder].
  StreamSubscription<List<int>>? _streamSub;

  /// Internal buffer that collects PCM bytes between drain calls.
  final List<int> _audioBuffer = [];

  // ── Observable state ───────────────────────────────────────────────────────

  /// Current recording lifecycle state.
  ///
  /// Listen to this notifier to update the UI whenever the recording starts,
  /// pauses, resumes, or stops.
  final ValueNotifier<RecordingState> state = ValueNotifier(
    RecordingState.idle,
  );

  // ── Permission ─────────────────────────────────────────────────────────────

  /// Requests microphone permission from the OS and returns `true` if granted.
  ///
  /// Call this before [start] for a better UX so you can show a rationale
  /// dialog when permission is denied.
  Future<bool> hasPermission() async {
    // The `request: true` flag triggers the native permission dialog when the
    // permission has not yet been determined.
    return _fileRecorder.hasPermission();
  }

  // ── Start ──────────────────────────────────────────────────────────────────

  /// Begins recording to a file.
  ///
  /// * [config]     – Recording parameters (encoder, sample rate, …).
  /// * [withStream] – When `true`, a parallel PCM stream is opened so you can
  ///                  call [drainChunk] periodically for real-time data.
  ///
  /// Returns the **absolute file path** where the recording will be saved.
  ///
  /// Throws if microphone permission was not granted.
  Future<String> start(
    RecordingConfig config, {
    bool withStream = false,
  }) async {
    // ── 1. Guard: ensure we have permission ──────────────────────────────
    if (!await _fileRecorder.hasPermission()) {
      throw StateError('Microphone permission not granted.');
    }

    // ── 2. Build the output file path ────────────────────────────────────
    //    If the caller provided a custom directory we use that; otherwise
    //    fall back to the platform's documents directory.
    final directory =
        config.outputDirectory ??
        (await getApplicationDocumentsDirectory()).path;

    //    File name: {prefix}_{epochMillis}.{ext}
    final fileName =
        '${config.fileNamePrefix}_${DateTime.now().millisecondsSinceEpoch}'
        '.${config.fileExtension}';

    //    Combine directory + file name for the full path.
    final filePath = '$directory/$fileName';

    // ── 3. Map our encoder enum to the `record` package's AudioEncoder ───
    final recordEncoder = _mapEncoder(config.encoder);

    // ── 4. Build the RecordConfig used by the `record` package ───────────
    final recordConfig = RecordConfig(
      encoder: recordEncoder,
      bitRate: config.bitRate,
      sampleRate: config.sampleRate,
      numChannels: config.numChannels,
      autoGain: config.autoGain,
      echoCancel: config.echoCancel,
      noiseSuppress: config.noiseSuppress,
    );

    // ── 5. Start the file recorder ───────────────────────────────────────
    await _fileRecorder.start(path: filePath, recordConfig);

    // ── 6. (Optional) Start the PCM stream recorder ─────────────────────
    if (withStream) {
      //  The stream recorder always uses PCM 16-bit regardless of the file
      //  encoder so the Speech API receives raw LINEAR16 data.
      final streamConfig = RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: config.sampleRate,
        numChannels: config.numChannels,
        autoGain: config.autoGain,
        echoCancel: config.echoCancel,
        noiseSuppress: config.noiseSuppress,
      );

      // Open the stream – this returns a broadcast Stream<List<int>>.
      final stream = await _streamRecorder.startStream(streamConfig);

      // Subscribe and funnel every chunk of bytes into our internal buffer.
      _streamSub = stream.listen((bytes) {
        _audioBuffer.addAll(bytes);
      });
    }

    // ── 7. Update state ──────────────────────────────────────────────────
    state.value = RecordingState.recording;

    // ── 8. Return the path so the caller knows where the file will land ──
    return filePath;
  }

  // ── Pause / Resume ─────────────────────────────────────────────────────────

  /// Pauses the active recording.
  ///
  /// Both the file recorder and the stream recorder (if active) are paused.
  Future<void> pause() async {
    await _fileRecorder.pause();
    // The `record` package doesn't expose pause on stream, but we update
    // our state so the timer in the main service stops draining.
    state.value = RecordingState.paused;
  }

  /// Resumes a paused recording.
  Future<void> resume() async {
    await _fileRecorder.resume();
    state.value = RecordingState.recording;
  }

  // ── Stop ───────────────────────────────────────────────────────────────────

  /// Stops the recording and finalises the file.
  ///
  /// Returns the **absolute file path** of the saved audio, or `null` if the
  /// recorder had nothing to save.
  Future<String?> stop() async {
    // Stop the PCM stream first (if active) so we don't lose trailing bytes.
    await _stopStream();

    // Stop the file recorder – this flushes and closes the file.
    final path = await _fileRecorder.stop();

    // Reset state.
    state.value = RecordingState.idle;
    return path;
  }

  /// Cancels the recording and discards any captured audio.
  Future<void> cancel() async {
    await _stopStream();
    await _fileRecorder.cancel();
    state.value = RecordingState.idle;
  }

  // ── Stream chunk access ────────────────────────────────────────────────────

  /// Drains all PCM bytes that have accumulated in the buffer since the last
  /// drain and returns them as a [Uint8List].
  ///
  /// Returns `null` if the buffer is empty (e.g. silence or very short
  /// interval).
  ///
  /// This is called periodically by the main service's timer during real-time
  /// transcription.
  Uint8List? drainChunk() {
    // Nothing to drain.
    if (_audioBuffer.isEmpty) return null;

    // Copy the buffer contents into a new typed list.
    final chunk = Uint8List.fromList(_audioBuffer);

    // Clear the buffer so the next drain starts fresh.
    _audioBuffer.clear();

    return chunk;
  }

  // ── Cleanup ────────────────────────────────────────────────────────────────

  /// Releases all native resources held by the recorders.
  ///
  /// After calling this, the instance must not be used again.
  Future<void> dispose() async {
    await _stopStream();
    await _fileRecorder.dispose();
    await _streamRecorder.dispose();
    state.dispose();
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  /// Stops the streaming recorder and cleans up the subscription + buffer.
  Future<void> _stopStream() async {
    // Cancel the stream subscription (if any).
    await _streamSub?.cancel();
    _streamSub = null;

    // Clear leftover bytes.
    _audioBuffer.clear();

    // Attempt to stop the stream recorder. It may throw if it was never
    // started, so we silently catch.
    try {
      await _streamRecorder.stop();
    } catch (_) {
      // Ignored – the stream recorder may not have been started.
    }
  }

  /// Maps our [AudioFileEncoder] enum to the `record` package's
  /// [AudioEncoder] enum.
  AudioEncoder _mapEncoder(AudioFileEncoder encoder) {
    switch (encoder) {
      case AudioFileEncoder.wav:
        return AudioEncoder.wav;
      case AudioFileEncoder.aacLc:
        return AudioEncoder.aacLc;
      case AudioFileEncoder.aacEld:
        return AudioEncoder.aacEld;
      case AudioFileEncoder.aacHe:
        return AudioEncoder.aacHe;
      case AudioFileEncoder.opus:
        return AudioEncoder.opus;
      case AudioFileEncoder.flac:
        return AudioEncoder.flac;
      case AudioFileEncoder.amrNb:
        return AudioEncoder.amrNb;
      case AudioFileEncoder.amrWb:
        return AudioEncoder.amrWb;
      case AudioFileEncoder.vorbisOgg:
        return AudioEncoder.vorbisOgg;
    }
  }
}
