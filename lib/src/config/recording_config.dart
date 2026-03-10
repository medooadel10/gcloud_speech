// ──────────────────────────────────────────────────────────────────────────────
// recording_config.dart
//
// All configurable parameters for the audio recording hardware.
// Wraps the `record` package's settings into a single, documented class.
// ──────────────────────────────────────────────────────────────────────────────

/// Audio encoder used for the **file** recording (the artifact saved to disk).
///
/// For real-time transcription the package always opens a second stream with
/// PCM 16-bit encoding regardless of what you choose here.
///
/// These values mirror the `record` package's `AudioEncoder` enum.
enum AudioFileEncoder {
  /// Waveform Audio – uncompressed, universally supported.
  wav,

  /// Advanced Audio Coding (Low Complexity) – good compression, widely
  /// supported on iOS/Android.
  aacLc,

  /// AAC Enhanced Low Delay – optimised for real-time communication.
  aacEld,

  /// AAC High-Efficiency – very compact, ideal for speech.
  aacHe,

  /// Opus codec – excellent quality at low bitrates. Requires `.ogg`
  /// container on Android and `.caf` on iOS.
  opus,

  /// Free Lossless Audio Codec – lossless compression, larger files.
  flac,

  /// AMR Narrowband – 8 kHz telephony quality.
  amrNb,

  /// AMR Wideband – 16 kHz telephony quality.
  amrWb,

  /// Vorbis in an OGG container.
  vorbisOgg,
}

/// Configuration for the audio recording hardware.
///
/// Controls how audio is captured from the microphone and written to disk.
///
/// Example:
/// ```dart
/// RecordingConfig(
///   encoder: AudioFileEncoder.wav,
///   sampleRate: 16000,
///   bitRate: 128000,
///   numChannels: 1,
///   autoGain: true,
///   echoCancel: false,
///   noiseSuppress: true,
///   fileNamePrefix: 'meeting',
///   outputDirectory: '/custom/path',
/// )
/// ```
class RecordingConfig {
  /// Creates a [RecordingConfig].
  ///
  /// Every parameter has a sensible default, so you can use the zero-argument
  /// constructor for a quick start.
  const RecordingConfig({
    // ── Encoder / format ──────────────────────────────────────────────────
    this.encoder = AudioFileEncoder.wav,
    this.sampleRate = 16000,
    this.bitRate = 128000,
    this.numChannels = 1,

    // ── Device processing ─────────────────────────────────────────────────
    this.autoGain = false,
    this.echoCancel = false,
    this.noiseSuppress = false,

    // ── File naming ───────────────────────────────────────────────────────
    this.fileNamePrefix = 'audio',
    this.outputDirectory,
  });

  // ─────────────────────────── Encoder / format ─────────────────────────────

  /// The codec used to encode the audio file saved to disk.
  ///
  /// Defaults to [AudioFileEncoder.wav] because WAV is uncompressed and
  /// therefore easiest to send directly to the Speech API (no transcoding
  /// needed).
  final AudioFileEncoder encoder;

  /// Sampling rate in Hertz.
  ///
  /// Must match the value set in [SpeechConfig.sampleRateHertz] so the API
  /// can decode the audio correctly.
  ///
  /// Common values:
  /// * `8000`  – telephony
  /// * `16000` – wideband (default, best trade-off for speech)
  /// * `44100` – CD quality
  /// * `48000` – professional
  final int sampleRate;

  /// Target bit rate in bits per second.
  ///
  /// Only meaningful for lossy encoders (AAC, Opus, AMR, Vorbis).
  /// Ignored for WAV and FLAC.
  ///
  /// Default: 128 000 bps (128 kbps).
  final int bitRate;

  /// Number of audio channels.
  ///
  /// * `1` – mono (recommended for speech recognition).
  /// * `2` – stereo (useful for multi-speaker setups when combined with
  ///         [SpeechConfig.enableSeparateRecognitionPerChannel]).
  final int numChannels;

  // ─────────────────────────── Device processing ────────────────────────────

  /// When `true`, the OS's Automatic Gain Control is enabled.
  ///
  /// AGC normalises volume levels, which can help when the speaker moves
  /// closer to or further from the microphone.
  ///
  /// **Note:** Not all platforms support AGC.
  final bool autoGain;

  /// When `true`, the OS's Acoustic Echo Cancellation is enabled.
  ///
  /// AEC removes playback audio that leaks back into the microphone, which
  /// is critical during phone / video calls.
  final bool echoCancel;

  /// When `true`, the OS's noise-suppression DSP is enabled.
  ///
  /// Reduces background noise (fans, traffic, etc.) which can improve
  /// transcription accuracy in noisy environments.
  final bool noiseSuppress;

  // ──────────────────────────── File naming ──────────────────────────────────

  /// Prefix for the generated file name.
  ///
  /// The final file name follows the pattern:
  /// ```
  /// {prefix}_{timestamp}.{extension}
  /// ```
  /// Default: `"audio"`.
  final String fileNamePrefix;

  /// Custom directory to save audio files.
  ///
  /// When `null` (the default), the platform's application-documents directory
  /// is used (obtained via `path_provider`).
  final String? outputDirectory;

  /// Returns the file extension string that matches [encoder].
  ///
  /// Used internally to construct the output file path.
  String get fileExtension {
    switch (encoder) {
      case AudioFileEncoder.wav:
        return 'wav';
      case AudioFileEncoder.aacLc:
      case AudioFileEncoder.aacEld:
      case AudioFileEncoder.aacHe:
        return 'm4a';
      case AudioFileEncoder.opus:
        return 'ogg';
      case AudioFileEncoder.flac:
        return 'flac';
      case AudioFileEncoder.amrNb:
      case AudioFileEncoder.amrWb:
        return 'amr';
      case AudioFileEncoder.vorbisOgg:
        return 'ogg';
    }
  }

  /// Returns a copy of this config with the given fields replaced.
  RecordingConfig copyWith({
    AudioFileEncoder? encoder,
    int? sampleRate,
    int? bitRate,
    int? numChannels,
    bool? autoGain,
    bool? echoCancel,
    bool? noiseSuppress,
    String? fileNamePrefix,
    String? outputDirectory,
  }) {
    return RecordingConfig(
      encoder: encoder ?? this.encoder,
      sampleRate: sampleRate ?? this.sampleRate,
      bitRate: bitRate ?? this.bitRate,
      numChannels: numChannels ?? this.numChannels,
      autoGain: autoGain ?? this.autoGain,
      echoCancel: echoCancel ?? this.echoCancel,
      noiseSuppress: noiseSuppress ?? this.noiseSuppress,
      fileNamePrefix: fileNamePrefix ?? this.fileNamePrefix,
      outputDirectory: outputDirectory ?? this.outputDirectory,
    );
  }
}
