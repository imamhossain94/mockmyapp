#ifndef RUNNER_MP4_WRITER_H_
#define RUNNER_MP4_WRITER_H_

// In this order: mfreadwrite.h uses what mfidl.h declares.
#include <windows.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <wrl/client.h>

#include <cstdint>
#include <string>

// An H.264 MP4 written through Windows' own Media Foundation encoder — the
// Windows counterpart of VideoEncoderBridge.kt (MediaCodec) and
// VideoEncoderBridge.swift (AVAssetWriter).
//
// Deliberately free of anything Flutter, so tool/windows_mp4_check can build
// it on its own and read back what it wrote.
//
// Frames arrive as straight RGBA, rows packed, and are swizzled to the BGRA
// Media Foundation calls RGB32; the sink writer puts the colour converter in
// front of the encoder itself. Every call returns false and fills |error| on
// failure, in words fit for the user.
//
// Asked for, a second stream carries silence as stereo AAC at 48 kHz, fed in
// step with the picture as 16-bit PCM zeros: the sound track App Store Connect
// expects on a preview.
class Mp4Writer {
 public:
  Mp4Writer();
  ~Mp4Writer();

  Mp4Writer(const Mp4Writer&) = delete;
  Mp4Writer& operator=(const Mp4Writer&) = delete;

  // Whether this Windows can encode H.264 at all. The N editions ship without
  // the media stack until the Media Feature Pack is installed, and then there
  // is no encoder to ask.
  static bool IsAvailable();

  // Whether this Windows has an AAC encoder for the silent track. It comes
  // with Media Foundation, so in practice wherever IsAvailable() is true.
  static bool IsAudioAvailable();

  // Starts a file at |path|. Odd sizes are rounded down to even: 4:2:0 halves
  // the colour both ways. |audio_samples| is how much silence, in samples per
  // channel at 48 kHz, the file carries; zero means no sound track.
  bool Open(const std::wstring& path, int width, int height, int fps,
            int bitrate, long long audio_samples, std::string* error);

  // One frame of straight RGBA, |source_width| by |source_height|. A smaller
  // frame is padded with black and a larger one cut, as on the other
  // platforms.
  bool AddFrame(const uint8_t* rgba, size_t length, int source_width,
                int source_height, std::string* error);

  // Writes the index and closes the file.
  bool Finish(std::string* error);

  // Abandons the file and deletes it.
  void Cancel();

  int width() const { return width_; }
  int height() const { return height_; }

 private:
  // Adds the AAC stream, with 16-bit PCM going in.
  HRESULT AddAudioStream();

  // Silence up to |until| samples per channel, never past |audio_samples_|.
  bool WriteSilence(long long until, std::string* error);

  Microsoft::WRL::ComPtr<IMFSinkWriter> writer_;
  std::wstring path_;
  DWORD stream_ = 0;
  DWORD audio_stream_ = 0;
  long long audio_samples_ = 0;
  long long audio_written_ = 0;
  int width_ = 0;
  int height_ = 0;
  int fps_ = 30;
  long long frame_ = 0;
  bool started_media_foundation_ = false;
};

#endif  // RUNNER_MP4_WRITER_H_
