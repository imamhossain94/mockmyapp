import Flutter
import Photos
import UIKit

/// iOS counterpart of `MediaStoreBridge.kt`.
///
/// Images are added to the photo library (inside a "MockMyApp" album, so
/// the behaviour matches the `Pictures/MockMyApp` folder on Android), and
/// documents are written into the app's Documents directory, which `Info.plist`
/// exposes to the Files app — iOS has no shared Downloads folder.
///
/// Answers with `{displayPath, filePath, uri}` exactly like the Android side so
/// the Dart layer needs no per-platform branching.
final class MediaStoreBridge: NSObject {

  static let channelName = "mockmyapp/storage"

  static func register(with messenger: FlutterBinaryMessenger) -> MediaStoreBridge {
    let bridge = MediaStoreBridge()
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak bridge] call, result in
      bridge?.handle(call, result: result)
    }
    return bridge
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard
      let args = call.arguments as? [String: Any],
      let data = (args["bytes"] as? FlutterStandardTypedData)?.data,
      let fileName = args["fileName"] as? String, !fileName.isEmpty
    else {
      result(FlutterError(code: "bad_arguments",
                          message: "Missing image data or file name.",
                          details: nil))
      return
    }
    let folder = (args["folder"] as? String) ?? ""

    switch call.method {
    case "saveImage":
      saveImage(data: data, fileName: fileName, album: folder, result: result)
    case "saveVideo":
      saveVideo(data: data, fileName: fileName, album: folder, result: result)
    case "saveDownload":
      saveDocument(data: data, fileName: fileName, folder: folder, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Photo library

  private func saveImage(
    data: Data,
    fileName: String,
    album: String,
    result: @escaping FlutterResult
  ) {
    requestAddOnlyAuthorization { authorized in
      guard authorized else {
        result(FlutterError(code: "permission_denied",
                            message: "Photo library access is needed to save images.",
                            details: nil))
        return
      }

      // Only the leaf name is meaningful as an album title; a nested Android
      // path like "MockMyApp/My App" flattens to its last component.
      let albumTitle = album.split(separator: "/").last.map(String.init) ?? "MockMyApp"

      self.fetchOrCreateAlbum(named: albumTitle) { collection in
        PHPhotoLibrary.shared().performChanges {
          let request = PHAssetCreationRequest.forAsset()
          request.addResource(with: .photo, data: data, options: nil)
          if let collection,
             let placeholder = request.placeholderForCreatedAsset,
             let albumChange = PHAssetCollectionChangeRequest(for: collection) {
            albumChange.addAssets([placeholder] as NSArray)
          }
        } completionHandler: { success, error in
          DispatchQueue.main.async {
            if success {
              result([
                "displayPath": "\(albumTitle)/\(fileName)",
                "filePath": nil,
                "uri": nil,
              ] as [String: Any?])
            } else {
              result(FlutterError(code: "save_failed",
                                  message: error?.localizedDescription
                                    ?? "Could not add the image to your photo library.",
                                  details: nil))
            }
          }
        }
      }
    }
  }

  /// A clip into the same album as the stills. Photos imports a video from a
  /// file, not from bytes, so it is staged in the temporary directory first
  /// and removed once Photos has its own copy.
  private func saveVideo(
    data: Data,
    fileName: String,
    album: String,
    result: @escaping FlutterResult
  ) {
    let staged = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString + "-" + fileName)
    do {
      try data.write(to: staged, options: .atomic)
    } catch {
      result(FlutterError(code: "save_failed",
                          message: error.localizedDescription,
                          details: nil))
      return
    }

    requestAddOnlyAuthorization { authorized in
      guard authorized else {
        try? FileManager.default.removeItem(at: staged)
        result(FlutterError(code: "permission_denied",
                            message: "Photo library access is needed to save videos.",
                            details: nil))
        return
      }

      let albumTitle = album.split(separator: "/").last.map(String.init) ?? "MockMyApp"

      self.fetchOrCreateAlbum(named: albumTitle) { collection in
        PHPhotoLibrary.shared().performChanges {
          let request = PHAssetCreationRequest.forAsset()
          request.addResource(with: .video, fileURL: staged, options: nil)
          if let collection,
             let placeholder = request.placeholderForCreatedAsset,
             let albumChange = PHAssetCollectionChangeRequest(for: collection) {
            albumChange.addAssets([placeholder] as NSArray)
          }
        } completionHandler: { success, error in
          try? FileManager.default.removeItem(at: staged)
          DispatchQueue.main.async {
            if success {
              result([
                "displayPath": "\(albumTitle)/\(fileName)",
                "filePath": nil,
                "uri": nil,
              ] as [String: Any?])
            } else {
              result(FlutterError(code: "save_failed",
                                  message: error?.localizedDescription
                                    ?? "Could not add the video to your photo library.",
                                  details: nil))
            }
          }
        }
      }
    }
  }

  private func requestAddOnlyAuthorization(_ completion: @escaping (Bool) -> Void) {
    let handle: (PHAuthorizationStatus) -> Void = { status in
      if #available(iOS 14, *) {
        // `.limited` still allows add-only writes.
        completion(status == .authorized || status == .limited)
      } else {
        completion(status == .authorized)
      }
    }
    if #available(iOS 14, *) {
      let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
      if status == .notDetermined {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { handle($0) }
      } else {
        handle(status)
      }
    } else {
      let status = PHPhotoLibrary.authorizationStatus()
      if status == .notDetermined {
        PHPhotoLibrary.requestAuthorization { handle($0) }
      } else {
        handle(status)
      }
    }
  }

  private func fetchOrCreateAlbum(
    named title: String,
    completion: @escaping (PHAssetCollection?) -> Void
  ) {
    let options = PHFetchOptions()
    options.predicate = NSPredicate(format: "title = %@", title)
    let existing = PHAssetCollection.fetchAssetCollections(
      with: .album, subtype: .any, options: options
    )
    if let album = existing.firstObject {
      completion(album)
      return
    }

    var placeholder: PHObjectPlaceholder?
    PHPhotoLibrary.shared().performChanges {
      let request = PHAssetCollectionChangeRequest
        .creationRequestForAssetCollection(withTitle: title)
      placeholder = request.placeholderForCreatedAssetCollection
    } completionHandler: { success, _ in
      guard success, let id = placeholder?.localIdentifier else {
        // An album is a nicety — fall back to saving into the camera roll.
        completion(nil)
        return
      }
      let created = PHAssetCollection.fetchAssetCollections(
        withLocalIdentifiers: [id], options: nil
      )
      completion(created.firstObject)
    }
  }

  // MARK: - Documents

  private func saveDocument(
    data: Data,
    fileName: String,
    folder: String,
    result: @escaping FlutterResult
  ) {
    do {
      let documents = try FileManager.default.url(
        for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true
      )
      var directory = documents
      for component in folder.split(separator: "/") {
        directory.appendPathComponent(String(component))
      }
      try FileManager.default.createDirectory(
        at: directory, withIntermediateDirectories: true
      )

      let url = uniqueURL(in: directory, fileName: fileName)
      try data.write(to: url, options: .atomic)

      let display = folder.isEmpty
        ? url.lastPathComponent
        : "\(folder)/\(url.lastPathComponent)"
      result([
        "displayPath": display,
        "filePath": url.path,
        "uri": url.absoluteString,
      ] as [String: Any?])
    } catch {
      result(FlutterError(code: "save_failed",
                          message: error.localizedDescription,
                          details: nil))
    }
  }

  private func uniqueURL(in directory: URL, fileName: String) -> URL {
    let base = (fileName as NSString).deletingPathExtension
    let ext = (fileName as NSString).pathExtension
    var candidate = directory.appendingPathComponent(fileName)
    var n = 2
    while FileManager.default.fileExists(atPath: candidate.path) {
      let next = ext.isEmpty ? "\(base) (\(n))" : "\(base) (\(n)).\(ext)"
      candidate = directory.appendingPathComponent(next)
      n += 1
    }
    return candidate
  }
}
