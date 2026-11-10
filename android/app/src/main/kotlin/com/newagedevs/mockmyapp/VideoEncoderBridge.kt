package com.newagedevs.mockmyapp

import android.content.Context
import android.media.Image
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.media.MediaFormat
import android.media.MediaMuxer
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.ByteBuffer
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * The MP4 encoder behind `mockmyapp/video` — see `video_encoder.dart`.
 *
 * Frames arrive from Dart as straight RGBA, are converted to YUV 4:2:0 and
 * handed to the phone's own H.264 encoder through [MediaCodec]; the encoded
 * stream is written into an MP4 by [MediaMuxer] in the app's cache, and the
 * path goes back to Dart, which reads the file and saves it like any export.
 *
 * Frames go into the codec's input *images* rather than through a surface,
 * because only a buffer takes an exact presentation time: frame n is shown at
 * n / fps seconds however long it took to draw, which a surface — timestamped
 * when it is posted — cannot promise.
 *
 * When Dart asks for `audioSamples`, the phone's AAC encoder is fed that much
 * silence alongside the picture and the muxer writes it as a second track:
 * stereo, 48 kHz, 256 kbit/s, which App Store Connect asks of a preview.
 */
class VideoEncoderBridge(private val context: Context) : MethodChannel.MethodCallHandler {

    private val worker: ExecutorService = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val sessions = ConcurrentHashMap<String, Encoder>()

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "audioAvailable" -> run(result) { SilentTrack.available() }
            "start" -> {
                val width = call.argument<Int>("width") ?: 0
                val height = call.argument<Int>("height") ?: 0
                val fps = call.argument<Int>("fps") ?: 30
                val bitrate = call.argument<Int>("bitrate") ?: 8_000_000
                // An Integer or a Long, depending on its size.
                val audioSamples = call.argument<Number>("audioSamples")?.toLong() ?: 0L
                run(result) {
                    val dir = File(context.cacheDir, "video").apply { mkdirs() }
                    val id = UUID.randomUUID().toString()
                    sessions[id] =
                        Encoder(File(dir, "$id.mp4"), width, height, fps, bitrate, audioSamples)
                    id
                }
            }
            "addFrame" -> {
                val encoder = sessions[call.argument<String>("id")]
                val rgba = call.argument<ByteArray>("rgba")
                val width = call.argument<Int>("width") ?: 0
                val height = call.argument<Int>("height") ?: 0
                if (encoder == null || rgba == null) {
                    result.error("bad_arguments", "No encoder is running.", null)
                    return
                }
                run(result) {
                    encoder.append(rgba, width, height)
                    null
                }
            }
            "finish" -> {
                val id = call.argument<String>("id")
                val encoder = sessions.remove(id)
                if (encoder == null) {
                    result.error("bad_arguments", "No encoder is running.", null)
                    return
                }
                run(result) { encoder.finish() }
            }
            "cancel" -> {
                val encoder = sessions.remove(call.argument<String>("id"))
                run(result) {
                    encoder?.cancel()
                    null
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun run(result: MethodChannel.Result, work: () -> Any?) {
        worker.execute {
            try {
                val value = work()
                main.post { result.success(value) }
            } catch (e: Exception) {
                main.post {
                    result.error("video_failed", e.message ?: e.javaClass.simpleName, null)
                }
            }
        }
    }

    fun dispose() {
        for (encoder in sessions.values) {
            runCatching { encoder.cancel() }
        }
        sessions.clear()
        worker.shutdown()
    }

    companion object {
        const val CHANNEL = "mockmyapp/video"
    }
}

/**
 * The silent sound track: stereo AAC at 48 kHz and 256 kbit/s — App Store
 * Connect's audio specification for app previews — encoded from 16-bit PCM
 * zeros. How much of it a clip carries is worked out in Dart
 * (`silentSamplesFor`), a little shorter than the picture.
 */
private object SilentTrack {
    const val SAMPLE_RATE = 48_000
    const val CHANNELS = 2
    const val BITRATE = 256_000

    /** 16-bit samples, interleaved: four bytes for each stereo sample. */
    const val BYTES_PER_SAMPLE = 2 * CHANNELS

    /** Whether this phone has an AAC encoder for 48 kHz stereo. */
    fun available(): Boolean = runCatching {
        MediaCodecList(MediaCodecList.REGULAR_CODECS).findEncoderForFormat(
            MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC, SAMPLE_RATE, CHANNELS),
        ) != null
    }.getOrDefault(false)

    fun encoder(): MediaCodec {
        val format = MediaFormat.createAudioFormat(
            MediaFormat.MIMETYPE_AUDIO_AAC,
            SAMPLE_RATE,
            CHANNELS,
        ).apply {
            setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
            setInteger(MediaFormat.KEY_BIT_RATE, BITRATE)
        }
        val codec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC)
        try {
            codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            codec.start()
        } catch (e: Exception) {
            codec.release()
            throw e
        }
        return codec
    }
}

/** One MP4 being written. Used from one thread only — the bridge's worker. */
private class Encoder(
    private val file: File,
    requestedWidth: Int,
    requestedHeight: Int,
    private val fps: Int,
    bitrate: Int,
    /** Samples of silence per channel to write; none means no sound track. */
    private val audioSamples: Long,
) {
    // 4:2:0 halves the colour in both directions, so both sides must be even.
    private val width = (requestedWidth / 2) * 2
    private val height = (requestedHeight / 2) * 2

    private val codec: MediaCodec
    private val audio: MediaCodec?
    private val muxer: MediaMuxer
    private val info = MediaCodec.BufferInfo()
    private val audioInfo = MediaCodec.BufferInfo()
    private var track = -1
    private var audioTrack = -1
    private var audioFormat: MediaFormat? = null
    private var muxing = false
    private var frames = 0L

    /** Samples per channel handed to the AAC encoder so far. */
    private var audioQueued = 0L
    private var audioInputEnded = false
    private var audioOutputEnded = false
    private var zeros = ByteArray(0)

    /** Sound encoded before the muxer could start, written as soon as it has. */
    private val pendingAudio = ArrayList<Pair<ByteArray, MediaCodec.BufferInfo>>()

    init {
        require(width >= 2 && height >= 2) { "A video needs a size." }
        codec = startVideoCodec(bitrate)
        audio = if (audioSamples > 0) {
            try {
                SilentTrack.encoder()
            } catch (e: Exception) {
                codec.release()
                throw IllegalStateException("This phone could not add the silent audio track.", e)
            }
        } else {
            null
        }
        try {
            muxer = MediaMuxer(file.path, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        } catch (e: Exception) {
            codec.release()
            audio?.release()
            throw e
        }
        try {
            primeAudio()
        } catch (e: Exception) {
            runCatching { release() }
            throw e
        }
    }

    /**
     * The phone's H.264 encoder, started — at Level 4.0 where the clip fits it.
     *
     * App Store Connect takes previews up to High Profile Level 4.0, and some
     * phones mark a 1080p clip 4.1 or higher unless asked. So the level is
     * asked for, with the best profile the encoder lists at it, and a phone
     * that refuses the request anyway gets a fresh encoder without it.
     */
    private fun startVideoCodec(bitrate: Int): MediaCodec {
        val first = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
        val profile = if (fitsLevelFour()) levelFourProfile(first.codecInfo) else null
        if (profile != null) {
            try {
                first.configure(videoFormat(bitrate, profile), null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
                first.start()
                return first
            } catch (e: Exception) {
                first.release()
            }
        }
        val codec = if (profile != null) {
            MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
        } else {
            first
        }
        try {
            codec.configure(videoFormat(bitrate, null), null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            codec.start()
        } catch (e: Exception) {
            codec.release()
            throw IllegalStateException(
                "This phone's encoder will not take a $width × $height video.",
                e,
            )
        }
        return codec
    }

    private fun videoFormat(bitrate: Int, profile: Int?): MediaFormat =
        MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, width, height).apply {
            setInteger(
                MediaFormat.KEY_COLOR_FORMAT,
                MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible,
            )
            setInteger(MediaFormat.KEY_BIT_RATE, bitrate)
            setInteger(MediaFormat.KEY_FRAME_RATE, fps)
            // A key frame every second, so a clip scrubs and loops cleanly.
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
            if (profile != null) {
                setInteger(MediaFormat.KEY_PROFILE, profile)
                setInteger(MediaFormat.KEY_LEVEL, MediaCodecInfo.CodecProfileLevel.AVCLevel4)
            }
        }

    /** Whether Level 4.0's limits hold this clip: 8192 macroblocks a frame, 245,760 a second. */
    private fun fitsLevelFour(): Boolean {
        val blocks = ((width + 15) / 16).toLong() * ((height + 15) / 16)
        return blocks <= 8192 && blocks * fps <= 245_760
    }

    /** The best profile this encoder offers at Level 4.0 or above, or null. */
    private fun levelFourProfile(codecInfo: MediaCodecInfo): Int? {
        val levels = runCatching {
            codecInfo.getCapabilitiesForType(MediaFormat.MIMETYPE_VIDEO_AVC).profileLevels
        }.getOrNull() ?: return null
        return listOf(
            MediaCodecInfo.CodecProfileLevel.AVCProfileHigh,
            MediaCodecInfo.CodecProfileLevel.AVCProfileMain,
            MediaCodecInfo.CodecProfileLevel.AVCProfileBaseline,
        ).firstOrNull { profile ->
            levels.any {
                it.profile == profile && it.level >= MediaCodecInfo.CodecProfileLevel.AVCLevel4
            }
        }
    }

    fun append(rgba: ByteArray, sourceWidth: Int, sourceHeight: Int) {
        val index = dequeueInput()
        val image = codec.getInputImage(index)
            ?: throw IllegalStateException("The encoder gave no frame to draw into.")
        fillYuv(image, rgba, sourceWidth, sourceHeight)
        codec.queueInputBuffer(index, 0, width * height * 3 / 2, frames * 1_000_000L / fps, 0)
        frames++
        drain(endOfStream = false)
        // The sound keeps pace with the picture, up to this frame's end.
        feedAudio(frames * SilentTrack.SAMPLE_RATE / fps, wait = false)
        drainAudio()
    }

    fun finish(): String {
        val index = dequeueInput()
        codec.queueInputBuffer(
            index,
            0,
            0,
            frames * 1_000_000L / fps,
            MediaCodec.BUFFER_FLAG_END_OF_STREAM,
        )
        drain(endOfStream = true)
        if (audio != null) {
            feedAudio(audioSamples, wait = true)
            endAudioInput()
            drainAudio(timeoutUs = 10_000, untilEnd = true)
        }
        // A muxer that cannot finish leaves no index, and a file without one
        // is not a video: say so rather than hand it back.
        val stopped = runCatching { if (muxing) muxer.stop() }
        muxing = false
        release()
        stopped.getOrElse { throw IllegalStateException("The video could not be finished.", it) }
        return file.path
    }

    fun cancel() {
        runCatching { release() }
        runCatching { file.delete() }
    }

    private fun release() {
        runCatching { codec.stop() }
        codec.release()
        audio?.let {
            runCatching { it.stop() }
            it.release()
        }
        if (muxing) runCatching { muxer.stop() }
        muxer.release()
    }

    /** An input slot, emptying the output side while there is none free. */
    private fun dequeueInput(): Int {
        repeat(400) {
            val index = codec.dequeueInputBuffer(10_000)
            if (index >= 0) return index
            drain(endOfStream = false)
        }
        throw IllegalStateException("The encoder stopped taking frames.")
    }

    private fun drain(endOfStream: Boolean) {
        var idle = 0
        while (true) {
            val index = codec.dequeueOutputBuffer(info, if (endOfStream) 10_000 else 0)
            when {
                index == MediaCodec.INFO_TRY_AGAIN_LATER -> {
                    if (!endOfStream || ++idle > 500) return
                }
                index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    // Every track is added before the muxer starts; it takes
                    // none after. The sound's format is to hand already, from
                    // priming.
                    if (!muxing) {
                        track = muxer.addTrack(codec.outputFormat)
                        if (audio != null) {
                            val format = audioFormat
                                ?: throw IllegalStateException("The audio encoder never started.")
                            audioTrack = muxer.addTrack(format)
                        }
                        muxer.start()
                        muxing = true
                        writePendingAudio()
                    }
                }
                index >= 0 -> {
                    val buffer = codec.getOutputBuffer(index)
                    if (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) {
                        // Already in the track's format; written again it would be
                        // a frame of garbage.
                        info.size = 0
                    }
                    if (buffer != null && info.size > 0 && muxing) {
                        buffer.position(info.offset)
                        buffer.limit(info.offset + info.size)
                        muxer.writeSampleData(track, buffer, info)
                    }
                    codec.releaseOutputBuffer(index, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) return
                }
            }
        }
    }

    /**
     * Silence into the AAC encoder until it states its output format, which
     * the muxer needs before it can start — and the encoder gives only once it
     * has had some sound. Done before the first frame, so the format is to
     * hand when the picture's arrives.
     */
    private fun primeAudio() {
        if (audio == null) return
        var attempts = 0
        while (audioFormat == null) {
            if (audioQueued < audioSamples) {
                feedAudio(audioQueued + 1024, wait = true)
            } else {
                endAudioInput()
            }
            drainAudio(timeoutUs = 10_000)
            if (audioOutputEnded && audioFormat == null || ++attempts > 300) {
                throw IllegalStateException("The audio encoder would not start.")
            }
        }
    }

    /**
     * Silence up to [until] samples per channel, never past [audioSamples]:
     * as far as the encoder has room for, or — when [wait] — however long it
     * takes to make room.
     */
    private fun feedAudio(until: Long, wait: Boolean) {
        val audio = audio ?: return
        val target = minOf(until, audioSamples)
        var attempts = 0
        while (audioQueued < target && !audioInputEnded) {
            val index = audio.dequeueInputBuffer(if (wait) 10_000 else 0)
            if (index < 0) {
                if (!wait) return
                drainAudio()
                if (++attempts > 400) throw IllegalStateException("The audio encoder stopped taking sound.")
                continue
            }
            val buffer = audio.getInputBuffer(index)
                ?: throw IllegalStateException("The audio encoder gave nowhere to put sound.")
            val room = buffer.capacity() / SilentTrack.BYTES_PER_SAMPLE
            val count = minOf(room.toLong(), target - audioQueued).toInt()
            val bytes = count * SilentTrack.BYTES_PER_SAMPLE
            // Written out each time: a reused buffer still holds what it last
            // carried.
            if (zeros.size < bytes) zeros = ByteArray(bytes)
            buffer.clear()
            buffer.put(zeros, 0, bytes)
            audio.queueInputBuffer(
                index,
                0,
                bytes,
                audioQueued * 1_000_000L / SilentTrack.SAMPLE_RATE,
                0,
            )
            audioQueued += count
        }
    }

    private fun endAudioInput() {
        val audio = audio ?: return
        if (audioInputEnded) return
        repeat(400) {
            val index = audio.dequeueInputBuffer(10_000)
            if (index >= 0) {
                audio.queueInputBuffer(
                    index,
                    0,
                    0,
                    audioQueued * 1_000_000L / SilentTrack.SAMPLE_RATE,
                    MediaCodec.BUFFER_FLAG_END_OF_STREAM,
                )
                audioInputEnded = true
                return
            }
            drainAudio()
        }
        throw IllegalStateException("The audio encoder stopped taking sound.")
    }

    /** Encoded sound out: into the muxer once it has started, held until then. */
    private fun drainAudio(timeoutUs: Long = 0, untilEnd: Boolean = false) {
        val audio = audio ?: return
        var idle = 0
        while (!audioOutputEnded) {
            val index = audio.dequeueOutputBuffer(audioInfo, timeoutUs)
            when {
                index == MediaCodec.INFO_TRY_AGAIN_LATER -> {
                    if (!untilEnd || ++idle > 500) return
                }
                index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    if (audioFormat == null) audioFormat = audio.outputFormat
                }
                index >= 0 -> {
                    val buffer = audio.getOutputBuffer(index)
                    if (audioInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) {
                        // In the track's format already, as for the picture.
                        audioInfo.size = 0
                    }
                    if (buffer != null && audioInfo.size > 0) {
                        buffer.position(audioInfo.offset)
                        buffer.limit(audioInfo.offset + audioInfo.size)
                        if (muxing) {
                            muxer.writeSampleData(audioTrack, buffer, audioInfo)
                        } else {
                            val copy = ByteArray(audioInfo.size)
                            buffer.get(copy)
                            pendingAudio.add(
                                copy to MediaCodec.BufferInfo().apply {
                                    set(0, copy.size, audioInfo.presentationTimeUs, audioInfo.flags)
                                },
                            )
                        }
                    }
                    audio.releaseOutputBuffer(index, false)
                    if (audioInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                        audioOutputEnded = true
                    }
                }
            }
        }
    }

    private fun writePendingAudio() {
        for ((bytes, bufferInfo) in pendingAudio) {
            muxer.writeSampleData(audioTrack, ByteBuffer.wrap(bytes), bufferInfo)
        }
        pendingAudio.clear()
    }

    /**
     * [rgba] into [image]'s planes as BT.601 video-range YUV, averaging each
     * 2 × 2 block for its colour. Written through each plane's own strides, so
     * it fits whatever layout this encoder chose — planar, semi-planar, padded.
     * A frame smaller than the video is padded with black; a larger one is cut.
     */
    private fun fillYuv(image: Image, rgba: ByteArray, sourceWidth: Int, sourceHeight: Int) {
        val yPlane = image.planes[0]
        val uPlane = image.planes[1]
        val vPlane = image.planes[2]
        val yBuffer = yPlane.buffer
        val uBuffer = uPlane.buffer
        val vBuffer = vPlane.buffer
        val yRow = yPlane.rowStride
        val yPixel = yPlane.pixelStride
        val uRow = uPlane.rowStride
        val uPixel = uPlane.pixelStride
        val vRow = vPlane.rowStride
        val vPixel = vPlane.pixelStride
        val stride = sourceWidth * 4

        fun channel(x: Int, y: Int, c: Int): Int =
            if (x < sourceWidth && y < sourceHeight) {
                rgba[y * stride + x * 4 + c].toInt() and 0xFF
            } else {
                0
            }

        for (y in 0 until height) {
            for (x in 0 until width) {
                val r = channel(x, y, 0)
                val g = channel(x, y, 1)
                val b = channel(x, y, 2)
                val luma = ((66 * r + 129 * g + 25 * b + 128) shr 8) + 16
                yBuffer.put(y * yRow + x * yPixel, luma.toByte())
            }
        }
        for (y in 0 until height / 2) {
            for (x in 0 until width / 2) {
                var r = 0
                var g = 0
                var b = 0
                for (dy in 0..1) {
                    for (dx in 0..1) {
                        r += channel(x * 2 + dx, y * 2 + dy, 0)
                        g += channel(x * 2 + dx, y * 2 + dy, 1)
                        b += channel(x * 2 + dx, y * 2 + dy, 2)
                    }
                }
                r = r shr 2
                g = g shr 2
                b = b shr 2
                val u = ((-38 * r - 74 * g + 112 * b + 128) shr 8) + 128
                val v = ((112 * r - 94 * g - 18 * b + 128) shr 8) + 128
                uBuffer.put(y * uRow + x * uPixel, u.toByte())
                vBuffer.put(y * vRow + x * vPixel, v.toByte())
            }
        }
    }
}
