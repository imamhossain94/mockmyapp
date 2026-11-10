// Writes a short clip through the app's Media Foundation writer and reads it
// back through Windows' own decoder, checking what an export has to get right:
// every frame arrives, the picture is the right way up, red is red, and the
// silent sound track App Store Connect expects is there — stereo AAC at
// 48 kHz, ending before the picture does.
//
// Build and run from the repo root (Visual Studio Build Tools):
//
//   cmake -S tool/windows_mp4_check -B build/windows_mp4_check
//   cmake --build build/windows_mp4_check --config Release
//   build\windows_mp4_check\Release\windows_mp4_check.exe [out.mp4]
//
// Exits 0 and prints PASS when the clip is right. With --skip-unavailable it
// also exits 0, printing SKIP, on a Windows with no H.264 or AAC encoder, as
// CI's Windows Server image may be. (Where Media Foundation is missing
// altogether, mfplat.dll is too and the program cannot load; CI checks for
// it before running this.)

#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <windows.h>
#include <wrl/client.h>

#include <cstdio>
#include <cwchar>
#include <string>
#include <vector>

#include "mp4_writer.h"

using Microsoft::WRL::ComPtr;

namespace {

constexpr int kWidth = 720;
constexpr int kHeight = 1280;
constexpr int kFps = 30;
constexpr int kFrames = 60;

// The silence the app asks for with these frames: the clip's length less
// three AAC frames, in whole AAC frames (silentSamplesFor in
// lib/data/services/video_encoder.dart). 2 s at 48 kHz is 96,000 samples;
// less 3,072 is 92,928; in whole frames of 1,024, 92,160.
constexpr long long kAudioSamples =
    ((static_cast<long long>(kFrames) * 48000 / kFps - 3 * 1024) / 1024) *
    1024;

// Top half red, bottom half green, straight RGBA — what the app sends. Two
// colours no fault confuses: upside down puts green on top, a red/blue swap
// turns the top blue.
std::vector<uint8_t> Frame() {
  std::vector<uint8_t> rgba(static_cast<size_t>(kWidth) * kHeight * 4);
  for (int y = 0; y < kHeight; y++) {
    for (int x = 0; x < kWidth; x++) {
      uint8_t* p = &rgba[(static_cast<size_t>(y) * kWidth + x) * 4];
      const bool top = y < kHeight / 2;
      p[0] = top ? 230 : 20;   // R
      p[1] = top ? 20 : 230;   // G
      p[2] = 20;               // B
      p[3] = 255;              // A
    }
  }
  return rgba;
}

int Fail(const char* what, HRESULT hr = S_OK) {
  std::printf("FAIL: %s (0x%08lX)\n", what, static_cast<unsigned long>(hr));
  return 1;
}

}  // namespace

int wmain(int argc, wchar_t** argv) {
  CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  bool skip_unavailable = false;
  std::wstring out_path;
  for (int i = 1; i < argc; i++) {
    if (std::wcscmp(argv[i], L"--skip-unavailable") == 0) {
      skip_unavailable = true;
    } else {
      out_path = argv[i];
    }
  }

  const bool video = Mp4Writer::IsAvailable();
  const bool audio = video && Mp4Writer::IsAudioAvailable();
  if (!audio) {
    const char* missing = video ? "no AAC encoder" : "no H.264 encoder";
    if (skip_unavailable) {
      std::printf("SKIP: %s on this PC\n", missing);
      return 0;
    }
    return Fail(missing);
  }

  wchar_t temp[MAX_PATH + 1];
  GetTempPathW(MAX_PATH + 1, temp);
  const std::wstring path = !out_path.empty()
                                ? out_path
                                : std::wstring(temp) + L"mp4_check.mp4";

  // Write.
  {
    Mp4Writer writer;
    std::string error;
    if (!writer.Open(path, kWidth, kHeight, kFps, 10'000'000, kAudioSamples,
                     &error)) {
      std::printf("FAIL: open: %s\n", error.c_str());
      return 1;
    }
    const std::vector<uint8_t> frame = Frame();
    for (int i = 0; i < kFrames; i++) {
      if (!writer.AddFrame(frame.data(), frame.size(), kWidth, kHeight,
                           &error)) {
        std::printf("FAIL: frame %d: %s\n", i, error.c_str());
        return 1;
      }
    }
    if (!writer.Finish(&error)) {
      std::printf("FAIL: finish: %s\n", error.c_str());
      return 1;
    }
  }

  // Read back, decoded to RGB32 by the source reader's own converter.
  MFStartup(MF_VERSION);
  ComPtr<IMFAttributes> attributes;
  MFCreateAttributes(&attributes, 1);
  attributes->SetUINT32(MF_SOURCE_READER_ENABLE_VIDEO_PROCESSING, TRUE);
  ComPtr<IMFSourceReader> reader;
  HRESULT hr =
      MFCreateSourceReaderFromURL(path.c_str(), attributes.Get(), &reader);
  if (FAILED(hr)) return Fail("the file does not open as a video", hr);

  // The sound track, as stored: AAC, stereo, 48 kHz.
  ComPtr<IMFMediaType> sound;
  hr = reader->GetNativeMediaType(
      static_cast<DWORD>(MF_SOURCE_READER_FIRST_AUDIO_STREAM), 0, &sound);
  if (FAILED(hr)) return Fail("the file has no audio stream", hr);
  GUID sound_subtype = {};
  sound->GetGUID(MF_MT_SUBTYPE, &sound_subtype);
  const UINT32 channels =
      MFGetAttributeUINT32(sound.Get(), MF_MT_AUDIO_NUM_CHANNELS, 0);
  const UINT32 rate =
      MFGetAttributeUINT32(sound.Get(), MF_MT_AUDIO_SAMPLES_PER_SECOND, 0);
  std::printf("audio %s, %u channels, %u Hz\n",
              sound_subtype == MFAudioFormat_AAC ? "AAC" : "not AAC",
              channels, rate);
  if (sound_subtype != MFAudioFormat_AAC) return Fail("the audio is not AAC");
  if (channels != 2) return Fail("the audio is not stereo");
  if (rate != 48000) return Fail("the audio is not 48 kHz");

  // The whole file lasts as long as its picture: the sound ends first, so it
  // can never push a 30-second preview past App Store Connect's limit.
  PROPVARIANT duration = {};  // VT_EMPTY
  hr = reader->GetPresentationAttribute(
      static_cast<DWORD>(MF_SOURCE_READER_MEDIASOURCE), MF_PD_DURATION,
      &duration);
  if (FAILED(hr)) return Fail("the file states no duration", hr);
  const ULONGLONG length = duration.uhVal.QuadPart;
  PropVariantClear(&duration);
  const ULONGLONG picture = static_cast<ULONGLONG>(kFrames) * 10'000'000ULL /
                            static_cast<ULONGLONG>(kFps);
  std::printf("duration %llu of %llu (100 ns)\n", length, picture);
  // A millisecond's grace for the container's own rounding.
  if (length > picture + 10'000) return Fail("the sound runs past the picture");

  // Only the picture is decoded below; a selected stream that is never read
  // would hold its samples back.
  reader->SetStreamSelection(static_cast<DWORD>(MF_SOURCE_READER_ALL_STREAMS),
                             FALSE);
  reader->SetStreamSelection(
      static_cast<DWORD>(MF_SOURCE_READER_FIRST_VIDEO_STREAM), TRUE);

  ComPtr<IMFMediaType> want;
  MFCreateMediaType(&want);
  want->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
  want->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_RGB32);
  hr = reader->SetCurrentMediaType(
      static_cast<DWORD>(MF_SOURCE_READER_FIRST_VIDEO_STREAM), nullptr,
      want.Get());
  if (FAILED(hr)) return Fail("no RGB decode path", hr);

  ComPtr<IMFMediaType> got;
  reader->GetCurrentMediaType(
      static_cast<DWORD>(MF_SOURCE_READER_FIRST_VIDEO_STREAM), &got);
  UINT32 width = 0, height = 0;
  MFGetAttributeSize(got.Get(), MF_MT_FRAME_SIZE, &width, &height);
  // The decoder states its own row order; a negative stride is bottom-up.
  const INT32 stride =
      static_cast<INT32>(MFGetAttributeUINT32(got.Get(), MF_MT_DEFAULT_STRIDE,
                                              width * 4));

  int frames = 0;
  bool checked = false;
  bool orientation_ok = false;
  bool colour_ok = false;
  for (;;) {
    DWORD flags = 0;
    LONGLONG time = 0;
    ComPtr<IMFSample> sample;
    hr = reader->ReadSample(
        static_cast<DWORD>(MF_SOURCE_READER_FIRST_VIDEO_STREAM), 0, nullptr,
        &flags, &time, &sample);
    if (FAILED(hr)) return Fail("decode failed", hr);
    if (flags & MF_SOURCE_READERF_ENDOFSTREAM) break;
    if (!sample) continue;
    frames++;
    if (checked) continue;
    checked = true;

    ComPtr<IMFMediaBuffer> buffer;
    sample->ConvertToContiguousBuffer(&buffer);
    BYTE* data = nullptr;
    DWORD length = 0;
    buffer->Lock(&data, nullptr, &length);
    auto pixel = [&](UINT32 x, UINT32 y) -> const BYTE* {
      const UINT32 row = stride < 0 ? height - 1 - y : y;
      return data + static_cast<size_t>(row) * (width * 4) + x * 4;
    };
    const BYTE* top = pixel(width / 2, height / 4);
    const BYTE* bottom = pixel(width / 2, height * 3 / 4);
    // BGRA order: [0] blue, [1] green, [2] red.
    orientation_ok = top[1] < 100 && bottom[1] > 150;
    colour_ok = top[2] > 150 && top[0] < 100;
    std::printf("size %ux%u  top RGB(%d,%d,%d)  bottom RGB(%d,%d,%d)\n", width,
                height, top[2], top[1], top[0], bottom[2], bottom[1],
                bottom[0]);
    buffer->Unlock();
  }
  MFShutdown();

  std::printf("frames %d of %d\n", frames, kFrames);
  if (width != kWidth || height != kHeight) return Fail("wrong size");
  if (frames != kFrames) return Fail("frames lost");
  if (!colour_ok) return Fail("red and blue swapped");
  if (!orientation_ok) return Fail("picture upside down");
  std::printf("PASS\n");
  return 0;
}
