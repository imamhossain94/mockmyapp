#include "video_encoder_bridge.h"

#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <cstdint>
#include <vector>


namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;

const EncodableValue* Arg(const EncodableMap& args, const char* key) {
  const auto it = args.find(EncodableValue(key));
  return it == args.end() ? nullptr : &it->second;
}

int IntArg(const EncodableMap& args, const char* key, int fallback) {
  const EncodableValue* value = Arg(args, key);
  if (!value) return fallback;
  if (const auto* i = std::get_if<int32_t>(value)) return *i;
  if (const auto* l = std::get_if<int64_t>(value)) return static_cast<int>(*l);
  return fallback;
}

std::string StringArg(const EncodableMap& args, const char* key) {
  const EncodableValue* value = Arg(args, key);
  if (!value) return "";
  if (const auto* s = std::get_if<std::string>(value)) return *s;
  return "";
}

// A fresh file in the temporary directory: the clip leaves through the
// ordinary save path, and Dart deletes this copy once it has read it.
std::wstring TempVideoPath(int id) {
  wchar_t directory[MAX_PATH + 1];
  const DWORD length = GetTempPathW(MAX_PATH + 1, directory);
  std::wstring path(directory, length);
  path += L"mockmyapp-" + std::to_wstring(GetCurrentProcessId()) + L"-" +
          std::to_wstring(id) + L".mp4";
  return path;
}

std::string Utf8(const std::wstring& wide) {
  if (wide.empty()) return "";
  const int size = WideCharToMultiByte(CP_UTF8, 0, wide.data(),
                                       static_cast<int>(wide.size()), nullptr,
                                       0, nullptr, nullptr);
  std::string out(size, '\0');
  WideCharToMultiByte(CP_UTF8, 0, wide.data(), static_cast<int>(wide.size()),
                      out.data(), size, nullptr, nullptr);
  return out;
}

}  // namespace

VideoEncoderBridge::VideoEncoderBridge(flutter::BinaryMessenger* messenger) {
  channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, "mockmyapp/video",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    Handle(call, std::move(result));
  });
}

VideoEncoderBridge::~VideoEncoderBridge() {
  channel_->SetMethodCallHandler(nullptr);
  // Each writer deletes its own unfinished file as it goes.
  sessions_.clear();
}

void VideoEncoderBridge::Handle(
    const flutter::MethodCall<EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  static const EncodableMap kNoArgs;
  const auto* map = std::get_if<EncodableMap>(call.arguments());
  const EncodableMap& args = map ? *map : kNoArgs;
  const std::string& method = call.method_name();

  if (method == "isAvailable") {
    result->Success(EncodableValue(Mp4Writer::IsAvailable()));
    return;
  }

  if (method == "audioAvailable") {
    result->Success(EncodableValue(Mp4Writer::IsAudioAvailable()));
    return;
  }

  if (method == "start") {
    const int id_number = ++next_id_;
    const std::string id = std::to_string(id_number);
    const std::wstring path = TempVideoPath(id_number);
    auto writer = std::make_unique<Mp4Writer>();
    std::string error;
    // Samples of silence for the sound track; absent means none.
    const long long audio_samples = IntArg(args, "audioSamples", 0);
    if (!writer->Open(path, IntArg(args, "width", 0), IntArg(args, "height", 0),
                      IntArg(args, "fps", 30),
                      IntArg(args, "bitrate", 8'000'000), audio_samples,
                      &error)) {
      result->Error("video_failed", error);
      return;
    }
    sessions_[id] = std::move(writer);
    paths_[id] = path;
    result->Success(EncodableValue(id));
    return;
  }

  const std::string id = StringArg(args, "id");
  const auto session = sessions_.find(id);

  if (method == "addFrame") {
    if (session == sessions_.end()) {
      result->Error("video_failed", "No encoder is running.");
      return;
    }
    const EncodableValue* frame = Arg(args, "rgba");
    const auto* bytes =
        frame ? std::get_if<std::vector<uint8_t>>(frame) : nullptr;
    if (!bytes) {
      result->Error("video_failed", "No frame was sent.");
      return;
    }
    std::string error;
    if (!session->second->AddFrame(bytes->data(), bytes->size(),
                                   IntArg(args, "width", 0),
                                   IntArg(args, "height", 0), &error)) {
      result->Error("video_failed", error);
      return;
    }
    result->Success();
    return;
  }

  if (method == "finish") {
    if (session == sessions_.end()) {
      result->Error("video_failed", "No encoder is running.");
      return;
    }
    std::string error;
    const bool finished = session->second->Finish(&error);
    const std::wstring path = paths_[id];
    sessions_.erase(session);
    paths_.erase(id);
    if (!finished) {
      result->Error("video_failed", error);
      return;
    }
    result->Success(EncodableValue(Utf8(path)));
    return;
  }

  if (method == "cancel") {
    if (session != sessions_.end()) {
      session->second->Cancel();
      sessions_.erase(session);
      paths_.erase(id);
    }
    result->Success();
    return;
  }

  result->NotImplemented();
}
