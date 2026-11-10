#ifndef RUNNER_VIDEO_ENCODER_BRIDGE_H_
#define RUNNER_VIDEO_ENCODER_BRIDGE_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>

#include <map>
#include <memory>
#include <string>

#include "mp4_writer.h"

// `mockmyapp/video` on Windows — see video_encoder.dart.
//
// The same four calls as the Android and Apple bridges (start, addFrame,
// finish, cancel), plus isAvailable, which the Dart side asks first so a PC
// with no H.264 encoder gets the GIF instead of a failed export.
//
// Everything runs on the platform thread: Dart awaits every frame before
// sending the next, so there is never more than one call in flight, and
// Flutter's own rendering does not run on this thread.
class VideoEncoderBridge {
 public:
  explicit VideoEncoderBridge(flutter::BinaryMessenger* messenger);
  ~VideoEncoderBridge();

 private:
  void Handle(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::map<std::string, std::unique_ptr<Mp4Writer>> sessions_;
  std::map<std::string, std::wstring> paths_;
  int next_id_ = 0;
};

#endif  // RUNNER_VIDEO_ENCODER_BRIDGE_H_
