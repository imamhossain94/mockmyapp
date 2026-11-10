#include "mp4_writer.h"

#include <codecapi.h>
#include <mfapi.h>
#include <mferror.h>
#include <mfidl.h>
#include <windows.h>

#include <algorithm>
#include <cstdio>
#include <cstring>

using Microsoft::WRL::ComPtr;

namespace {

// Media Foundation counts time in 100-nanosecond units.
constexpr long long kUnitsPerSecond = 10'000'000;

// The silent track: stereo at 48 kHz, App Store Connect's audio for a
// preview, fed as 16-bit PCM — four bytes a stereo sample.
constexpr UINT32 kAudioRate = 48000;
constexpr UINT32 kAudioChannels = 2;
constexpr UINT32 kAudioBytesPerSample = 2 * kAudioChannels;

// 192 kbit/s. Apple's figure is 256, but Windows' own AAC encoder offers only
// 12,000, 16,000, 20,000 or 24,000 bytes a second, and this is the most.
constexpr UINT32 kAacBytesPerSecond = 24000;

std::string Failure(const char* what, HRESULT hr) {
  char buffer[160];
  std::snprintf(buffer, sizeof(buffer), "%s (Media Foundation error 0x%08lX).",
                what, static_cast<unsigned long>(hr));
  return buffer;
}

}  // namespace

Mp4Writer::Mp4Writer() {
  started_media_foundation_ = SUCCEEDED(MFStartup(MF_VERSION, MFSTARTUP_LITE));
}

Mp4Writer::~Mp4Writer() {
  // Whatever was not finished is not a video anyone asked to keep.
  if (writer_) Cancel();
  if (started_media_foundation_) MFShutdown();
}

bool Mp4Writer::IsAvailable() {
  if (FAILED(MFStartup(MF_VERSION, MFSTARTUP_LITE))) return false;
  MFT_REGISTER_TYPE_INFO output = {MFMediaType_Video, MFVideoFormat_H264};
  IMFActivate** found = nullptr;
  UINT32 count = 0;
  const HRESULT hr = MFTEnumEx(
      MFT_CATEGORY_VIDEO_ENCODER,
      MFT_ENUM_FLAG_SYNCMFT | MFT_ENUM_FLAG_ASYNCMFT | MFT_ENUM_FLAG_HARDWARE |
          MFT_ENUM_FLAG_SORTANDFILTER,
      nullptr, &output, &found, &count);
  for (UINT32 i = 0; i < count; i++) found[i]->Release();
  CoTaskMemFree(found);
  MFShutdown();
  return SUCCEEDED(hr) && count > 0;
}

bool Mp4Writer::IsAudioAvailable() {
  if (FAILED(MFStartup(MF_VERSION, MFSTARTUP_LITE))) return false;
  MFT_REGISTER_TYPE_INFO output = {MFMediaType_Audio, MFAudioFormat_AAC};
  IMFActivate** found = nullptr;
  UINT32 count = 0;
  const HRESULT hr = MFTEnumEx(
      MFT_CATEGORY_AUDIO_ENCODER,
      MFT_ENUM_FLAG_SYNCMFT | MFT_ENUM_FLAG_ASYNCMFT | MFT_ENUM_FLAG_HARDWARE |
          MFT_ENUM_FLAG_SORTANDFILTER,
      nullptr, &output, &found, &count);
  for (UINT32 i = 0; i < count; i++) found[i]->Release();
  CoTaskMemFree(found);
  MFShutdown();
  return SUCCEEDED(hr) && count > 0;
}

bool Mp4Writer::Open(const std::wstring& path, int width, int height, int fps,
                     int bitrate, long long audio_samples, std::string* error) {
  if (!started_media_foundation_) {
    *error = "Windows' media components are missing. On an N edition, install "
             "the Media Feature Pack.";
    return false;
  }
  width_ = (width / 2) * 2;
  height_ = (height / 2) * 2;
  fps_ = std::max(1, fps);
  frame_ = 0;
  audio_samples_ = std::max(0LL, audio_samples);
  audio_written_ = 0;
  path_ = path;
  if (width_ < 2 || height_ < 2) {
    *error = "A video needs a size.";
    return false;
  }
  DeleteFileW(path_.c_str());

  // The GPU's encoder where there is one; the sink writer falls back to the
  // software one by itself.
  ComPtr<IMFAttributes> attributes;
  HRESULT hr = MFCreateAttributes(&attributes, 1);
  if (SUCCEEDED(hr)) {
    hr = attributes->SetUINT32(MF_READWRITE_ENABLE_HARDWARE_TRANSFORMS, TRUE);
  }
  if (SUCCEEDED(hr)) {
    hr = MFCreateSinkWriterFromURL(path_.c_str(), nullptr, attributes.Get(),
                                   &writer_);
  }
  if (FAILED(hr)) {
    *error = Failure("The video file could not be created", hr);
    writer_.Reset();
    return false;
  }

  // What comes out: H.264, High profile, a key frame every second so a clip
  // scrubs and loops cleanly.
  ComPtr<IMFMediaType> out;
  hr = MFCreateMediaType(&out);
  if (SUCCEEDED(hr)) hr = out->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
  if (SUCCEEDED(hr)) hr = out->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_H264);
  if (SUCCEEDED(hr)) hr = out->SetUINT32(MF_MT_AVG_BITRATE, bitrate);
  if (SUCCEEDED(hr)) {
    hr = out->SetUINT32(MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive);
  }
  if (SUCCEEDED(hr)) {
    hr = out->SetUINT32(MF_MT_MPEG2_PROFILE, eAVEncH264VProfile_High);
  }
  if (SUCCEEDED(hr)) {
    hr = MFSetAttributeSize(out.Get(), MF_MT_FRAME_SIZE, width_, height_);
  }
  if (SUCCEEDED(hr)) {
    hr = MFSetAttributeRatio(out.Get(), MF_MT_FRAME_RATE, fps_, 1);
  }
  if (SUCCEEDED(hr)) {
    hr = MFSetAttributeRatio(out.Get(), MF_MT_PIXEL_ASPECT_RATIO, 1, 1);
  }
  if (SUCCEEDED(hr)) hr = writer_->AddStream(out.Get(), &stream_);
  if (FAILED(hr)) {
    *error = Failure("This PC cannot encode H.264 at this size", hr);
    writer_.Reset();
    return false;
  }

  // What goes in: 32-bit BGRA, top row first. The stride is stated rather
  // than left to the default, which for RGB formats is bottom-up.
  ComPtr<IMFMediaType> in;
  hr = MFCreateMediaType(&in);
  if (SUCCEEDED(hr)) hr = in->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
  if (SUCCEEDED(hr)) hr = in->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_RGB32);
  if (SUCCEEDED(hr)) {
    hr = in->SetUINT32(MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive);
  }
  if (SUCCEEDED(hr)) {
    hr = in->SetUINT32(MF_MT_DEFAULT_STRIDE, static_cast<UINT32>(width_ * 4));
  }
  if (SUCCEEDED(hr)) {
    hr = MFSetAttributeSize(in.Get(), MF_MT_FRAME_SIZE, width_, height_);
  }
  if (SUCCEEDED(hr)) {
    hr = MFSetAttributeRatio(in.Get(), MF_MT_FRAME_RATE, fps_, 1);
  }
  if (SUCCEEDED(hr)) {
    hr = MFSetAttributeRatio(in.Get(), MF_MT_PIXEL_ASPECT_RATIO, 1, 1);
  }
  if (SUCCEEDED(hr)) hr = writer_->SetInputMediaType(stream_, in.Get(), nullptr);
  if (FAILED(hr)) {
    *error = Failure("The encoder would not start", hr);
    writer_.Reset();
    DeleteFileW(path_.c_str());
    return false;
  }

  if (audio_samples_ > 0) {
    hr = AddAudioStream();
    if (FAILED(hr)) {
      *error = Failure("This PC could not add the silent audio track", hr);
      writer_.Reset();
      DeleteFileW(path_.c_str());
      return false;
    }
  }

  hr = writer_->BeginWriting();
  if (FAILED(hr)) {
    *error = Failure("The encoder would not start", hr);
    writer_.Reset();
    DeleteFileW(path_.c_str());
    return false;
  }
  return true;
}

HRESULT Mp4Writer::AddAudioStream() {
  // What comes out: raw AAC, which is what an MP4 stores, at AAC-LC's usual
  // profile level.
  ComPtr<IMFMediaType> out;
  HRESULT hr = MFCreateMediaType(&out);
  if (SUCCEEDED(hr)) hr = out->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio);
  if (SUCCEEDED(hr)) hr = out->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_AAC);
  if (SUCCEEDED(hr)) hr = out->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, 16);
  if (SUCCEEDED(hr)) {
    hr = out->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, kAudioRate);
  }
  if (SUCCEEDED(hr)) {
    hr = out->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS, kAudioChannels);
  }
  if (SUCCEEDED(hr)) {
    hr = out->SetUINT32(MF_MT_AUDIO_AVG_BYTES_PER_SECOND, kAacBytesPerSecond);
  }
  if (SUCCEEDED(hr)) hr = out->SetUINT32(MF_MT_AAC_PAYLOAD_TYPE, 0);
  if (SUCCEEDED(hr)) {
    hr = out->SetUINT32(MF_MT_AAC_AUDIO_PROFILE_LEVEL_INDICATION, 0x29);
  }
  if (SUCCEEDED(hr)) hr = writer_->AddStream(out.Get(), &audio_stream_);

  // What goes in: 16-bit PCM, interleaved.
  ComPtr<IMFMediaType> in;
  if (SUCCEEDED(hr)) hr = MFCreateMediaType(&in);
  if (SUCCEEDED(hr)) hr = in->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio);
  if (SUCCEEDED(hr)) hr = in->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_PCM);
  if (SUCCEEDED(hr)) hr = in->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, 16);
  if (SUCCEEDED(hr)) {
    hr = in->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, kAudioRate);
  }
  if (SUCCEEDED(hr)) {
    hr = in->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS, kAudioChannels);
  }
  if (SUCCEEDED(hr)) {
    hr = in->SetUINT32(MF_MT_AUDIO_BLOCK_ALIGNMENT, kAudioBytesPerSample);
  }
  if (SUCCEEDED(hr)) {
    hr = in->SetUINT32(MF_MT_AUDIO_AVG_BYTES_PER_SECOND,
                       kAudioRate * kAudioBytesPerSample);
  }
  if (SUCCEEDED(hr)) {
    hr = writer_->SetInputMediaType(audio_stream_, in.Get(), nullptr);
  }
  return hr;
}

bool Mp4Writer::WriteSilence(long long until, std::string* error) {
  const long long target = std::min(until, audio_samples_);
  while (audio_written_ < target) {
    // A tenth of a second at a time at most.
    const long long count =
        std::min<long long>(target - audio_written_, kAudioRate / 10);
    const DWORD bytes = static_cast<DWORD>(count) * kAudioBytesPerSample;

    ComPtr<IMFMediaBuffer> buffer;
    HRESULT hr = MFCreateMemoryBuffer(bytes, &buffer);
    BYTE* data = nullptr;
    if (SUCCEEDED(hr)) hr = buffer->Lock(&data, nullptr, nullptr);
    if (SUCCEEDED(hr)) {
      std::memset(data, 0, bytes);
      buffer->Unlock();
      hr = buffer->SetCurrentLength(bytes);
    }
    ComPtr<IMFSample> sample;
    if (SUCCEEDED(hr)) hr = MFCreateSample(&sample);
    if (SUCCEEDED(hr)) hr = sample->AddBuffer(buffer.Get());
    // Times computed from the sample count, like the frames', so a long clip
    // does not drift.
    const long long start = audio_written_ * kUnitsPerSecond / kAudioRate;
    const long long end =
        (audio_written_ + count) * kUnitsPerSecond / kAudioRate;
    if (SUCCEEDED(hr)) hr = sample->SetSampleTime(start);
    if (SUCCEEDED(hr)) hr = sample->SetSampleDuration(end - start);
    if (SUCCEEDED(hr)) hr = writer_->WriteSample(audio_stream_, sample.Get());
    if (FAILED(hr)) {
      *error = Failure("The silent audio track could not be written", hr);
      return false;
    }
    audio_written_ += count;
  }
  return true;
}

bool Mp4Writer::AddFrame(const uint8_t* rgba, size_t length, int source_width,
                         int source_height, std::string* error) {
  if (!writer_) {
    *error = "No encoder is running.";
    return false;
  }
  const DWORD stride = static_cast<DWORD>(width_) * 4;
  const DWORD size = stride * static_cast<DWORD>(height_);

  ComPtr<IMFMediaBuffer> buffer;
  HRESULT hr = MFCreateMemoryBuffer(size, &buffer);
  BYTE* destination = nullptr;
  if (SUCCEEDED(hr)) hr = buffer->Lock(&destination, nullptr, nullptr);
  if (FAILED(hr)) {
    *error = Failure("The encoder ran out of memory", hr);
    return false;
  }

  std::memset(destination, 0, size);
  const int rows = std::min(height_, source_height);
  const int columns = std::min(width_, source_width);
  const size_t source_stride = static_cast<size_t>(source_width) * 4;
  if (rows > 0 && columns > 0 && length >= source_stride * rows) {
    for (int y = 0; y < rows; y++) {
      const uint8_t* from = rgba + source_stride * y;
      BYTE* to = destination + static_cast<size_t>(stride) * y;
      // RGBA to BGRA: swap red and blue, keep green and alpha.
      for (int x = 0; x < columns; x++) {
        to[0] = from[2];
        to[1] = from[1];
        to[2] = from[0];
        to[3] = from[3];
        from += 4;
        to += 4;
      }
    }
  }
  buffer->Unlock();
  hr = buffer->SetCurrentLength(size);

  ComPtr<IMFSample> sample;
  if (SUCCEEDED(hr)) hr = MFCreateSample(&sample);
  if (SUCCEEDED(hr)) hr = sample->AddBuffer(buffer.Get());
  // Each frame exactly frame / fps seconds in, computed rather than summed so
  // a long clip does not drift.
  if (SUCCEEDED(hr)) {
    hr = sample->SetSampleTime(frame_ * kUnitsPerSecond / fps_);
  }
  if (SUCCEEDED(hr)) {
    hr = sample->SetSampleDuration((frame_ + 1) * kUnitsPerSecond / fps_ -
                                   frame_ * kUnitsPerSecond / fps_);
  }
  if (SUCCEEDED(hr)) hr = writer_->WriteSample(stream_, sample.Get());
  if (FAILED(hr)) {
    *error = Failure("The encoder dropped a frame", hr);
    return false;
  }
  frame_++;
  // The sound keeps pace with the picture, up to this frame's end.
  return audio_samples_ == 0 ||
         WriteSilence(frame_ * kAudioRate / fps_, error);
}

bool Mp4Writer::Finish(std::string* error) {
  if (!writer_) {
    *error = "No encoder is running.";
    return false;
  }
  // The rest of the silence; nearly all of it went in with the frames.
  if (audio_samples_ > 0 && !WriteSilence(audio_samples_, error)) {
    writer_.Reset();
    DeleteFileW(path_.c_str());
    return false;
  }
  const HRESULT hr = writer_->Finalize();
  writer_.Reset();
  if (FAILED(hr)) {
    DeleteFileW(path_.c_str());
    *error = Failure("The video could not be finished", hr);
    return false;
  }
  return true;
}

void Mp4Writer::Cancel() {
  // Releasing an unfinalized writer abandons the file; what it left behind is
  // not a playable video, so it goes too.
  writer_.Reset();
  if (!path_.empty()) DeleteFileW(path_.c_str());
}
