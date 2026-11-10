import Flutter
import Foundation
import SwiftUI
import UIKit
import Vision
#if canImport(FoundationModels)
import FoundationModels
#endif
#if canImport(Translation)
import Translation
#endif

/// The on-device AI behind `mockmyapp/ai` — iOS counterpart of
/// `OnDeviceAiBridge.kt`; see `on_device_ai.dart`.
///
///  * **Apple Intelligence**, through the Foundation Models framework (iOS 26),
///    writes captions.
///  * **Apple Translate**, through the Translation framework (iOS 18),
///    translates them. Language packs are the system's own, downloaded once
///    behind the system's own prompt.
///  * **Vision** reads the words off a screenshot.
///
/// Everything runs on the device. The prompts and the reading of answers live
/// in Dart; this file only runs the frameworks, and answers every call on the
/// main thread.
///
/// FoundationModels and Translation are weak-linked in the Runner target
/// (`OTHER_LDFLAGS`), because the app still runs on iOS 15: every use is
/// behind an availability check, and on an older iPhone the Dart side falls
/// back to its phrasebook and the manual translation table.
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
      if #available(iOS 26.0, *) {
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
              "Turn on Apple Intelligence in Settings to write captions with it.")
          case .deviceNotEligible:
            return status(
              "appleIntelligence", "unavailable",
              "This device does not support Apple Intelligence.")
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
      "Writing captions on this device needs Apple Intelligence.")
  }

  private func writeCaptions(
    instructions: String,
    prompt: String,
    result: @escaping FlutterResult
  ) {
    #if canImport(FoundationModels)
      if #available(iOS 26.0, *) {
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
    result(failure("Writing captions on this device needs Apple Intelligence."))
  }

  // MARK: - Apple Translate

  private func translationStatus(from: String, to: String, result: @escaping FlutterResult) {
    #if canImport(Translation)
      if #available(iOS 18.0, *) {
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
        "Translating on this device needs iOS 18 or later."))
  }

  private func translate(
    texts: [String],
    from: String,
    to: String,
    result: @escaping FlutterResult
  ) {
    #if canImport(Translation)
      if #available(iOS 18.0, *) {
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
    result(failure("Translating on this device needs iOS 18 or later."))
  }

  // MARK: - Vision

  private func readText(_ data: Data, result: @escaping FlutterResult) {
    DispatchQueue.global(qos: .userInitiated).async {
      var lines: [String] = []
      let request = VNRecognizeTextRequest { request, _ in
        let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
        // Vision's origin is the bottom left, so the top of the screen is the
        // largest y: sorted that way, the lines read as the screen does.
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
  /// Runs one translation through a `TranslationSession`.
  ///
  /// On iOS 18 a session exists only inside SwiftUI's `translationTask`, so
  /// this mounts an invisible hosting controller in the window for as long as
  /// the translation takes — which is also what lets the system show its own
  /// "download this language" prompt when a pack is missing — and removes it
  /// when done.
  ///
  /// Every call mounts and removes its own controller, so two translations in
  /// flight at once never tear down each other's session.
  @available(iOS 18.0, *)
  private final class TranslationHost {

    static let shared = TranslationHost()

    private enum HostError: LocalizedError {
      case noWindow
      var errorDescription: String? {
        return "Translation needs the app on screen."
      }
    }

    func translate(
      texts: [String],
      source: Locale.Language,
      target: Locale.Language,
      completion: @escaping (Result<[String], Error>) -> Void
    ) {
      DispatchQueue.main.async {
        // Only the words go through the translator; blank lines stay blank.
        let pending = texts.enumerated().filter {
          !$0.element.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if pending.isEmpty {
          completion(.success(texts))
          return
        }
        guard let root = Self.rootViewController() else {
          completion(.failure(HostError.noWindow))
          return
        }

        // Set once the controller is mounted; cleared on the way out, which
        // also breaks the cycle through the view's closure.
        var mounted: UIViewController?
        var finished = false
        let finish: (Result<[String], Error>) -> Void = { outcome in
          DispatchQueue.main.async {
            guard !finished else { return }
            finished = true
            if let controller = mounted {
              controller.willMove(toParent: nil)
              controller.view.removeFromSuperview()
              controller.removeFromParent()
            }
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

        let controller = UIHostingController(rootView: view)
        controller.view.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        controller.view.isUserInteractionEnabled = false
        controller.view.backgroundColor = .clear
        root.addChild(controller)
        root.view.addSubview(controller.view)
        controller.didMove(toParent: root)
        mounted = controller
      }
    }

    private static func rootViewController() -> UIViewController? {
      let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      let windows = scenes.flatMap { $0.windows }
      let window = windows.first { $0.isKeyWindow } ?? windows.first
      var top = window?.rootViewController
      while let presented = top?.presentedViewController {
        top = presented
      }
      return top
    }
  }

  @available(iOS 18.0, *)
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
