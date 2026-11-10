import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// Held for the lifetime of the app so the storage channel's handler is not
  /// deallocated straight after registration.
  private var storageBridge: MediaStoreBridge?
  private var aiBridge: OnDeviceAiBridge?
  private var videoBridge: VideoEncoderBridge?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "MediaStoreBridge") {
      storageBridge = MediaStoreBridge.register(with: registrar.messenger())
    }
    // Captions, translation and screen reading, all on the device.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "OnDeviceAiBridge") {
      aiBridge = OnDeviceAiBridge.register(with: registrar.messenger())
    }
    // The device's own H.264 encoder, for video exports.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "VideoEncoderBridge") {
      videoBridge = VideoEncoderBridge.register(with: registrar.messenger())
    }
  }
}
