import AVFoundation
import Accelerate
import Foundation

#if os(iOS)
  import Flutter
#else
  import FlutterMacOS
#endif

/// The MP4 encoder behind `mockmyapp/video` — Apple counterpart of
/// `VideoEncoderBridge.kt`; see `video_encoder.dart`.
///
/// Frames arrive from Dart as straight RGBA, are swizzled to BGRA into a pixel
/// buffer from the writer's own pool, and are appended to an `AVAssetWriter`
/// encoding H.264 in hardware, each at exactly frame / fps seconds. The file
/// is written to the temporary directory and its path handed back; Dart reads
/// it and saves it like any other export.
///
/// When Dart asks for `audioSamples`, a second input encodes that much
/// silence as stereo AAC at 48 kHz and 256 kbit/s, which App Store Connect
/// asks of a preview.
///
/// The same file serves the iOS and macOS runners.
final class VideoEncoderBridge: NSObject {

  static let channelName = "mockmyapp/video"

  /// Every session is touched only on [queue], so none of them needs a lock.
  private let queue = DispatchQueue(label: "com.newagedevs.mockmyapp.video")
  private var sessions: [String: VideoEncoderSession] = [:]

  static func register(with messenger: FlutterBinaryMessenger) -> VideoEncoderBridge {
    let bridge = VideoEncoderBridge()
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak bridge] call, result in
      guard let bridge = bridge else {
        result(FlutterMethodNotImplemented)
        return
      }
      bridge.handle(call, result: result)
    }
    return bridge
  }

  private func reply(_ result: @escaping FlutterResult, _ value: Any?) {
    DispatchQueue.main.async { result(value) }
  }

  private func fail(_ result: @escaping FlutterResult, _ message: String) {
    DispatchQueue.main.async {
      result(FlutterError(code: "video_failed", message: message, details: nil))
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "audioAvailable":
      // AVFoundation's AAC encoder is on every iPhone, iPad and Mac.
      result(true)

    case "start":
      let width = args["width"] as? Int ?? 0
      let height = args["height"] as? Int ?? 0
      let fps = args["fps"] as? Int ?? 30
      let bitrate = args["bitrate"] as? Int ?? 8_000_000
      let audioSamples = args["audioSamples"] as? Int ?? 0
      queue.async {
        do {
          let id = UUID().uuidString
          let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(id).mp4")
          self.sessions[id] = try VideoEncoderSession(
            url: url, width: width, height: height, fps: fps, bitrate: bitrate,
            audioSamples: audioSamples)
          self.reply(result, id)
        } catch {
          self.fail(result, error.localizedDescription)
        }
      }

    case "addFrame":
      let id = args["id"] as? String ?? ""
      let width = args["width"] as? Int ?? 0
      let height = args["height"] as? Int ?? 0
      guard let rgba = (args["rgba"] as? FlutterStandardTypedData)?.data else {
        fail(result, "No frame was sent.")
        return
      }
      queue.async {
        guard let session = self.sessions[id] else {
          self.fail(result, "No encoder is running.")
          return
        }
        do {
          try session.append(rgba: rgba, sourceWidth: width, sourceHeight: height)
          self.reply(result, nil)
        } catch {
          self.fail(result, error.localizedDescription)
        }
      }

    case "finish":
      let id = args["id"] as? String ?? ""
      queue.async {
        guard let session = self.sessions.removeValue(forKey: id) else {
          self.fail(result, "No encoder is running.")
          return
        }
        session.finish { outcome in
          switch outcome {
          case .success(let url):
            self.reply(result, url.path)
          case .failure(let error):
            self.fail(result, error.localizedDescription)
          }
        }
      }

    case "cancel":
      let id = args["id"] as? String ?? ""
      queue.async {
        self.sessions.removeValue(forKey: id)?.cancel()
        self.reply(result, nil)
      }

    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

/// One MP4 being written.
final class VideoEncoderSession {

  private enum Failure: LocalizedError {
    case message(String)
    var errorDescription: String? {
      switch self {
      case .message(let text): return text
      }
    }
  }

  /// The silent track's rate and channels: App Store Connect's audio for a
  /// preview. Fed as 16-bit PCM, four bytes a stereo sample.
  private static let sampleRate = 48_000
  private static let channels = 2

  let url: URL
  private let width: Int
  private let height: Int
  private let fps: Int32
  private let writer: AVAssetWriter
  private let input: AVAssetWriterInput
  private let adaptor: AVAssetWriterInputPixelBufferAdaptor
  private var frame: Int64 = 0

  /// The sound, when asked for: its input, the PCM it is fed, how many
  /// samples per channel it gets in all, and how many it has had.
  private let audioInput: AVAssetWriterInput?
  private let pcmFormat: CMAudioFormatDescription?
  private let audioSamples: Int64
  private var audioWritten: Int64 = 0
  private var audioFinished = false

  init(
    url: URL, width requestedWidth: Int, height requestedHeight: Int, fps: Int, bitrate: Int,
    audioSamples: Int
  ) throws {
    // 4:2:0 halves the colour both ways, so both sides must be even.
    let width = (requestedWidth / 2) * 2
    let height = (requestedHeight / 2) * 2
    guard width >= 2, height >= 2 else { throw Failure.message("A video needs a size.") }

    self.url = url
    self.width = width
    self.height = height
    self.fps = Int32(max(1, fps))

    try? FileManager.default.removeItem(at: url)
    // Built in locals and stored last, so nothing is read off `self` before
    // every stored property has a value.
    let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)

    // High Profile Level 4.0 where the clip fits it — 8192 macroblocks a
    // frame, 245,760 a second — because App Store Connect takes previews up
    // to that level, and the automatic level can choose higher.
    let blocks = ((width + 15) / 16) * ((height + 15) / 16)
    let levelFour = blocks <= 8192 && blocks * max(1, fps) <= 245_760
    let settings: [String: Any] = [
      AVVideoCodecKey: AVVideoCodecType.h264,
      AVVideoWidthKey: width,
      AVVideoHeightKey: height,
      AVVideoCompressionPropertiesKey: [
        AVVideoAverageBitRateKey: bitrate,
        AVVideoProfileLevelKey: levelFour
          ? AVVideoProfileLevelH264High40 : AVVideoProfileLevelH264HighAutoLevel,
        AVVideoExpectedSourceFrameRateKey: max(1, fps),
        // A key frame every second, so a clip scrubs and loops cleanly.
        AVVideoMaxKeyFrameIntervalKey: max(1, fps),
      ],
    ]
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
    input.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
      assetWriterInput: input,
      sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height,
      ]
    )
    guard writer.canAdd(input) else {
      throw Failure.message("This device cannot encode a \(width) × \(height) video.")
    }
    writer.add(input)

    var audioInput: AVAssetWriterInput?
    var pcmFormat: CMAudioFormatDescription?
    if audioSamples > 0 {
      var layout = AudioChannelLayout()
      layout.mChannelLayoutTag = kAudioChannelLayoutTag_Stereo
      let audioSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: VideoEncoderSession.sampleRate,
        AVNumberOfChannelsKey: VideoEncoderSession.channels,
        AVEncoderBitRateKey: 256_000,
        AVChannelLayoutKey: withUnsafeBytes(of: &layout) { Data($0) },
      ]
      // Asked first: an input made from settings the writer cannot apply
      // raises an Objective-C exception, which Swift cannot catch.
      guard writer.canApply(outputSettings: audioSettings, forMediaType: .audio) else {
        throw Failure.message("This device cannot add the silent audio track.")
      }
      let sound = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
      sound.expectsMediaDataInRealTime = false
      guard writer.canAdd(sound) else {
        throw Failure.message("This device cannot add the silent audio track.")
      }
      writer.add(sound)

      var pcm = AudioStreamBasicDescription(
        mSampleRate: Float64(VideoEncoderSession.sampleRate),
        mFormatID: kAudioFormatLinearPCM,
        mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
        mBytesPerPacket: 4,
        mFramesPerPacket: 1,
        mBytesPerFrame: 4,
        mChannelsPerFrame: UInt32(VideoEncoderSession.channels),
        mBitsPerChannel: 16,
        mReserved: 0
      )
      var format: CMAudioFormatDescription?
      guard
        CMAudioFormatDescriptionCreate(
          allocator: kCFAllocatorDefault, asbd: &pcm, layoutSize: 0, layout: nil,
          magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format)
          == noErr,
        let format
      else {
        throw Failure.message("This device cannot add the silent audio track.")
      }
      audioInput = sound
      pcmFormat = format
    }

    guard writer.startWriting() else {
      throw Failure.message(writer.error?.localizedDescription ?? "The encoder would not start.")
    }
    writer.startSession(atSourceTime: .zero)

    self.writer = writer
    self.input = input
    self.adaptor = adaptor
    self.audioInput = audioInput
    self.pcmFormat = pcmFormat
    self.audioSamples = Int64(max(0, audioSamples))
  }

  /// One frame of straight RGBA, [sourceWidth] by [sourceHeight]. A frame
  /// smaller than the video is padded with black; a larger one is cut.
  func append(rgba: Data, sourceWidth: Int, sourceHeight: Int) throws {
    // The sound up to this frame's end goes first: the writer interleaves the
    // two tracks, and may hold the picture back until the sound catches up.
    let soundTarget = (frame + 1) * Int64(VideoEncoderSession.sampleRate) / Int64(fps)
    try appendSilence(upTo: soundTarget)
    var waited = 0
    while !input.isReadyForMoreMediaData {
      if writer.status == .failed {
        throw Failure.message(writer.error?.localizedDescription ?? "The encoder failed.")
      }
      try appendSilence(upTo: soundTarget)
      Thread.sleep(forTimeInterval: 0.005)
      waited += 1
      if waited > 2000 { throw Failure.message("The encoder stopped taking frames.") }
    }
    guard let pool = adaptor.pixelBufferPool else {
      throw Failure.message("The encoder has no frames to draw into.")
    }
    var made: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, pool, &made)
    guard let pixels = made else { throw Failure.message("The encoder ran out of frames.") }

    CVPixelBufferLockBaseAddress(pixels, [])
    if let destination = CVPixelBufferGetBaseAddress(pixels) {
      let destinationRow = CVPixelBufferGetBytesPerRow(pixels)
      memset(destination, 0, destinationRow * height)
      let rows = min(height, sourceHeight)
      let columns = min(width, sourceWidth)
      if rows > 0 && columns > 0 && rgba.count >= sourceWidth * 4 * rows {
        rgba.withUnsafeBytes { raw in
          guard let base = raw.baseAddress else { return }
          var source = vImage_Buffer(
            data: UnsafeMutableRawPointer(mutating: base),
            height: vImagePixelCount(rows),
            width: vImagePixelCount(columns),
            rowBytes: sourceWidth * 4
          )
          var target = vImage_Buffer(
            data: destination,
            height: vImagePixelCount(rows),
            width: vImagePixelCount(columns),
            rowBytes: destinationRow
          )
          // RGBA to BGRA: swap red and blue, keep green and alpha.
          let swap: [UInt8] = [2, 1, 0, 3]
          vImagePermuteChannels_ARGB8888(&source, &target, swap, vImage_Flags(kvImageNoFlags))
        }
      }
    }
    CVPixelBufferUnlockBaseAddress(pixels, [])

    guard adaptor.append(pixels, withPresentationTime: CMTime(value: frame, timescale: fps)) else {
      throw Failure.message(writer.error?.localizedDescription ?? "The encoder dropped a frame.")
    }
    frame += 1
  }

  /// Silence up to [target] samples per channel, never past [audioSamples],
  /// as far as the writer takes it now.
  ///
  /// Never waits for room: the writer may be holding the sound back until the
  /// picture catches up, and waiting here would then wait forever.
  private func appendSilence(upTo target: Int64) throws {
    guard let sound = audioInput, !audioFinished else { return }
    let end = min(target, audioSamples)
    while audioWritten < end && sound.isReadyForMoreMediaData {
      // A tenth of a second at a time at most.
      let count = Int(min(end - audioWritten, 4_800))
      guard sound.append(try silence(count, at: audioWritten)) else {
        throw Failure.message(
          writer.error?.localizedDescription ?? "The silent audio track was refused.")
      }
      audioWritten += Int64(count)
    }
    if audioWritten >= audioSamples {
      // Said as soon as it is complete, so the writer stops waiting on it.
      sound.markAsFinished()
      audioFinished = true
    }
  }

  /// [count] samples of stereo silence, starting [start] samples in.
  private func silence(_ count: Int, at start: Int64) throws -> CMSampleBuffer {
    guard let format = pcmFormat else {
      throw Failure.message("The silent audio track has no format.")
    }
    let bytes = count * 2 * VideoEncoderSession.channels
    var block: CMBlockBuffer?
    guard
      CMBlockBufferCreateWithMemoryBlock(
        allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: bytes,
        blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0,
        dataLength: bytes, flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block)
        == kCMBlockBufferNoErr,
      let block,
      CMBlockBufferFillDataBytes(
        with: 0, blockBuffer: block, offsetIntoDestination: 0, dataLength: bytes)
        == kCMBlockBufferNoErr
    else {
      throw Failure.message("The silent audio track ran out of memory.")
    }
    var sample: CMSampleBuffer?
    guard
      CMAudioSampleBufferCreateReadyWithPacketDescriptions(
        allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format,
        sampleCount: count,
        presentationTimeStamp: CMTime(
          value: start, timescale: CMTimeScale(VideoEncoderSession.sampleRate)),
        packetDescriptions: nil, sampleBufferOut: &sample) == noErr,
      let sample
    else {
      throw Failure.message("The silent audio track could not be made.")
    }
    return sample
  }

  func finish(_ completion: @escaping (Result<URL, Error>) -> Void) {
    input.markAsFinished()
    // The rest of the silence, now that the picture is complete and nothing
    // holds the sound back. Bounded, like the picture's wait.
    if let sound = audioInput, !audioFinished {
      var waited = 0
      while !audioFinished && writer.status != .failed && waited <= 2000 {
        if sound.isReadyForMoreMediaData {
          do {
            try appendSilence(upTo: audioSamples)
          } catch {
            break
          }
        } else {
          Thread.sleep(forTimeInterval: 0.005)
          waited += 1
        }
      }
      if !audioFinished {
        sound.markAsFinished()
        audioFinished = true
      }
    }
    // A writer that has failed takes no more calls — it raises an exception
    // Swift cannot catch — and its own error says what went wrong.
    guard writer.status == .writing else {
      completion(
        .failure(writer.error ?? Failure.message("The video could not be finished.")))
      return
    }
    // The clip ends when its last frame does, whatever the sound does: a
    // full frame's time after it starts.
    writer.endSession(atSourceTime: CMTime(value: frame, timescale: fps))
    // Captured by value, so the closure holds the writer rather than self.
    let finishing = writer
    let url = self.url
    finishing.finishWriting {
      if finishing.status == .completed {
        completion(.success(url))
      } else {
        completion(
          .failure(finishing.error ?? Failure.message("The video could not be finished.")))
      }
    }
  }

  func cancel() {
    input.markAsFinished()
    writer.cancelWriting()
    try? FileManager.default.removeItem(at: url)
  }
}
