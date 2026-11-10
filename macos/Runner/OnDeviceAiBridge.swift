import AppKit
import FlutterMacOS
import Foundation
import SwiftUI
import Vision
#if canImport(FoundationModels)
import FoundationModels
#endif
#if canImport(Translation)
import Translation
#endif

/// The on-device AI behind `mockmyapp/ai` on the Mac — the macOS twin of
/// `ios/Runner/OnDeviceAiBridge.swift`, differing only in how a translation
/// session is hosted: an invisible `NSHostingView` in the window, where iOS
/// uses a `UIHostingController`.
///
/// Apple Intelligence needs macOS 26 and Apple Translate macOS 15; both
/// frameworks are weak-linked in the Runner target, and on an older Mac the
/// Dart side falls back to its phrasebook and the manual translation table.
final class OnDeviceAiBridge: NSObject {

  static let channelName = "mockmyapp/ai"

  static func register(with messenger: FlutterBinaryMessenger) -> OnDeviceAiBridge {
    let bridge = OnDeviceAiBridge()
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

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "captionStatus":
      result(captionStatus())
    case "writeCaptions":
      writeCaptions(
        instructions: args["instructions"] as? String ?? "",
        prompt: args["prompt"] as? String ?? "",
        result: result
      )
    case "translationStatus":
      translationStatus(
        from: args["from"] as? String ?? "",
        to: args["to"] as? String ?? "",
        result: result
      )
    case "translate":
      translate(
        texts: args["texts"] as? [String] ?? [],
        from: args["from"] as? String ?? "",
        to: args["to"] as? String ?? "",
        result: result
      )
    case "canReadText":
      result(true)
    case "readText":
      guard let data = (args["image"] as? FlutterStandardTypedData)?.data else {
        result("")
        return
      }
      readText(data, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func status(_ engine: String, _ state: String, _ reason: String? = nil)
    -> [String: Any?]
  {
    return ["engine": engine, "state": state, "reason": reason]
  }

  private func failure(_ message: String) -> FlutterError {
    return FlutterError(code: "ai_failed", message: message, details: nil)
  }

  // MARK: - Apple Intelligence

  private func captionStatus() -> [String: Any?] {
    #if canImport(FoundationModels)
      if #available(macOS 26.0, *) {
        let model = SystemLanguageModel.default
        if model.isAvailable {
          return status("appleIntelligence", "ready")
        }
        if case .unavailable(let reason) = model.availability {
          switch reason {
          case .modelNotReady:
            return status("appleIntelligence", "needsDownload")
          case .appleIntelligenceNotEnabled:
            return status(
              "appleIntelligence", "unavailable",
              "Turn on Apple Intelligence in System Settings to write captions with it.")
          case .deviceNotEligible:
            return status(
              "appleIntelligence", "unavailable",
              "This Mac does not support Apple Intelligence.")
          @unknown default:
            return status(
              "appleIntelligence", "unavailable",
              "Apple Intelligence is not available right now.")
          }
        }
        return status("appleIntelligence", "unavailable")
      }
    #endif
    return status(
      "appleIntelligence", "unavailable",
      "Writing captions on this Mac needs Apple Intelligence.")
  }

  private func writeCaptions(
    instructions: String,
    prompt: String,
    result: @escaping FlutterResult
  ) {
    #if canImport(FoundationModels)
      if #available(macOS 26.0, *) {
        Task {
          do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(
              to: prompt,
              options: GenerationOptions(temperature: 0.8)
            )
            let text = response.content
            await MainActor.run { result(text) }
          } catch {
            let message = error.localizedDescription
            await MainActor.run { result(self.failure(message)) }
          }
        }
        return
      }
    #endif
    result(failure("Writing captions on this Mac needs Apple Intelligence."))
  }

  // MARK: - Apple Translate

  private func translationStatus(from: String, to: String, result: @escaping FlutterResult) {
    #if canImport(Translation)
      if #available(macOS 15.0, *) {
        Task {
          let availability = LanguageAvailability()
          let found = await availability.status(
            from: Locale.Language(identifier: from),
            to: Locale.Language(identifier: to)
          )
          let map: [String: Any?]
          switch found {
          case .installed:
            map = self.status("appleTranslation", "ready")
          case .supported:
            map = self.status("appleTranslation", "needsDownload")
          case .unsupported:
            map = self.status(
              "appleTranslation", "unavailable",
              "Apple Translate does not translate this language pair.")
          @unknown default:
            map = self.status("appleTranslation", "unavailable")
          }
          await MainActor.run { result(map) }
        }
        return
      }
    #endif
    result(
      status(
        "appleTranslation", "unavailable",
        "Translating on this Mac needs macOS 15 or later."))
  }

  private func translate(
    texts: [String],
    from: String,
    to: String,
    result: @escaping FlutterResult
  ) {
    #if canImport(Translation)
      if #available(macOS 15.0, *) {
        TranslationHost.shared.translate(
          texts: texts,
          source: Locale.Language(identifier: from),
          target: Locale.Language(identifier: to)
        ) { outcome in
          switch outcome {
          case .success(let out):
            result(out)
          case .failure(let error):
            result(self.failure(error.localizedDescription))
          }
        }
        return
      }
    #endif
    result(failure("Translating on this Mac needs macOS 15 or later."))
  }

  // MARK: - Vision

  private func readText(_ data: Data, result: @escaping FlutterResult) {
    DispatchQueue.global(qos: .userInitiated).async {
      var lines: [String] = []
      let request = VNRecognizeTextRequest { request, _ in
        let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
        let ordered = observations.sorted { $0.boundingBox.maxY > $1.boundingBox.maxY }
        lines = ordered.compactMap { $0.topCandidates(1).first?.string }
      }
      request.recognitionLevel = .accurate
      request.usesLanguageCorrection = true
      let handler = VNImageRequestHandler(data: data, options: [:])
      do {
        try handler.perform([request])
      } catch {
        lines = []
      }
      let text =
        lines
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
      DispatchQueue.main.async { result(text) }
    }
  }
}

// MARK: - Translation host

#if canImport(Translation)
  /// Every call mounts and removes its own hosting view, so two translations
  /// in flight at once never tear down each other's session.
  @available(macOS 15.0, *)
  private final class TranslationHost {

    static let shared = TranslationHost()

    private enum HostError: LocalizedError {
      case noWindow
      var errorDescription: String? {
        return "Translation needs the app's window open."
      }
    }

    func translate(
      texts: [String],
      source: Locale.Language,
      target: Locale.Language,
      completion: @escaping (Result<[String], Error>) -> Void
    ) {
      DispatchQueue.main.async {
        let pending = texts.enumerated().filter {
          !$0.element.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if pending.isEmpty {
          completion(.success(texts))
          return
        }
        let window = NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first
        guard let content = window?.contentView else {
          completion(.failure(HostError.noWindow))
          return
        }

        // Set once the view is mounted; cleared on the way out, which also
        // breaks the cycle through the view's closure.
        var mounted: NSView?
        var finished = false
        let finish: (Result<[String], Error>) -> Void = { outcome in
          DispatchQueue.main.async {
            guard !finished else { return }
            finished = true
            mounted?.removeFromSuperview()
            mounted = nil
            completion(outcome)
          }
        }

        let view = TranslationTaskView(
          configuration: TranslationSession.Configuration(source: source, target: target)
        ) { session in
          do {
            try await session.prepareTranslation()
            let requests = pending.map {
              TranslationSession.Request(sourceText: $0.element, clientIdentifier: String($0.offset))
            }
            let responses = try await session.translations(from: requests)
            var out = texts
            for response in responses {
              if let id = response.clientIdentifier, let index = Int(id), index < out.count {
                out[index] = response.targetText
              }
            }
            finish(.success(out))
          } catch {
            finish(.failure(error))
          }
        }

        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 1, height: 1)
        content.addSubview(hosting)
        mounted = hosting
      }
    }
  }

  @available(macOS 15.0, *)
  private struct TranslationTaskView: View {
    let configuration: TranslationSession.Configuration
    let action: (TranslationSession) async -> Void

    var body: some View {
      Color.clear
        .frame(width: 1, height: 1)
        .translationTask(configuration) { session in
          await action(session)
        }
    }
  }
#endif
