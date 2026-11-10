package com.newagedevs.mockmyapp

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private var storage: MediaStoreBridge? = null
    private var ai: OnDeviceAiBridge? = null
    private var video: VideoEncoderBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val bridge = MediaStoreBridge(applicationContext)
        bridge.activity = this
        storage = bridge

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            MediaStoreBridge.CHANNEL,
        ).setMethodCallHandler(bridge)

        // Captions, translation and screen reading, all on the phone.
        val aiBridge = OnDeviceAiBridge()
        ai = aiBridge
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            OnDeviceAiBridge.CHANNEL,
        ).setMethodCallHandler(aiBridge)

        // The phone's own H.264 encoder, for video exports.
        val videoBridge = VideoEncoderBridge(applicationContext)
        video = videoBridge
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            VideoEncoderBridge.CHANNEL,
        ).setMethodCallHandler(videoBridge)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        // The bridge only claims its own request code, so plugin permission
        // flows still reach the Flutter embedding via super below.
        if (storage?.onRequestPermissionsResult(requestCode) == true) return
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    override fun onDestroy() {
        storage?.activity = null
        storage = null
        ai?.dispose()
        ai = null
        video?.dispose()
        video = null
        super.onDestroy()
    }
}
