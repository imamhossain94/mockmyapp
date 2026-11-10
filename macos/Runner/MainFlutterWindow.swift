import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  /// Held for the life of the window, so the channels' handlers are not
  /// released straight after registration.
  private var aiBridge: OnDeviceAiBridge?
  private var videoBridge: VideoEncoderBridge?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Captions, translation and screen reading, all on the Mac.
    aiBridge = OnDeviceAiBridge.register(
      with: flutterViewController.registrar(forPlugin: "OnDeviceAiBridge").messenger)
    // The Mac's own H.264 encoder, for video exports.
    videoBridge = VideoEncoderBridge.register(
      with: flutterViewController.registrar(forPlugin: "VideoEncoderBridge").messenger)

    super.awakeFromNib()
  }
}
