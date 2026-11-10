package com.newagedevs.mockmyapp

import android.graphics.BitmapFactory
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.google.android.gms.tasks.Task
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.common.MlKitException
import com.google.mlkit.common.model.DownloadConditions
import com.google.mlkit.common.model.RemoteModelManager
import com.google.mlkit.genai.common.DownloadCallback
import com.google.mlkit.genai.common.FeatureStatus
import com.google.mlkit.genai.common.GenAiException
import com.google.mlkit.genai.prompt.GenerateContentRequest
import com.google.mlkit.genai.prompt.Generation
import com.google.mlkit.genai.prompt.TextPart
import com.google.mlkit.genai.prompt.java.GenerativeModelFutures
import com.google.mlkit.nl.translate.TranslateLanguage
import com.google.mlkit.nl.translate.TranslateRemoteModel
import com.google.mlkit.nl.translate.Translation
import com.google.mlkit.nl.translate.TranslatorOptions
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.Locale
import java.util.concurrent.ExecutionException
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException

/**
 * The on-device AI behind `mockmyapp/ai` — see `on_device_ai.dart`.
 *
 * Three engines, all of which run on the phone:
 *
 *  * **Gemini Nano**, through AICore and ML Kit's GenAI Prompt API, writes
 *    captions. Only on phones that carry it; everywhere else the Dart side
 *    falls back to its own phrasebook.
 *  * **ML Kit Translation** translates captions. Its language packs download
 *    once from Google; the text itself never leaves the phone.
 *  * **ML Kit Text Recognition**, through Google Play services, reads the words
 *    off a screenshot so a caption can be written about what is on it.
 *
 * The prompts and the reading of the answers live in Dart; this file only
 * runs the models. Everything slow happens on one worker thread — ML Kit's
 * blocking `Tasks.await` and a future's `get` are not allowed on the main
 * thread — and every answer is posted back to it, which is where Flutter wants
 * channel replies.
 */
class OnDeviceAiBridge : MethodChannel.MethodCallHandler {

    private val worker: ExecutorService = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    /** Created on first use: asking AICore for a client costs a bind. */
    private val nano: GenerativeModelFutures by lazy {
        GenerativeModelFutures.from(Generation.getClient())
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "captionStatus" -> run(result) { captionStatus() }
            "writeCaptions" -> {
                val instructions = call.argument<String>("instructions").orEmpty()
                val prompt = call.argument<String>("prompt").orEmpty()
                run(result) { writeCaptions(instructions, prompt) }
            }
            "translationStatus" -> {
                val from = call.argument<String>("from").orEmpty()
                val to = call.argument<String>("to").orEmpty()
                run(result) { translationStatus(from, to) }
            }
            "translate" -> {
                val texts = call.argument<List<String>>("texts") ?: emptyList()
                val from = call.argument<String>("from").orEmpty()
                val to = call.argument<String>("to").orEmpty()
                run(result) { translate(texts, from, to) }
            }
            "canReadText" -> result.success(true)
            "readText" -> {
                val image = call.argument<ByteArray>("image")
                if (image == null) {
                    result.success("")
                } else {
                    run(result) { readText(image) }
                }
            }
            else -> result.notImplemented()
        }
    }

    /**
     * Runs [work] on the worker and answers on the main thread.
     *
     * Catches [Throwable], not just exceptions: a native library that will not
     * link throws an [Error], and on this thread an uncaught one takes the
     * whole app down instead of answering the call. Every failure is also
     * logged under [TAG], so `adb logcat -s MockMyAppAI` shows what the
     * user was told and why.
     */
    private fun run(result: MethodChannel.Result, work: () -> Any?) {
        worker.execute {
            try {
                val value = work()
                main.post { result.success(value) }
            } catch (e: AiFailure) {
                Log.w(TAG, e.message ?: "failed", e.cause ?: e)
                main.post { result.error("ai_failed", e.message, null) }
            } catch (e: Throwable) {
                Log.w(TAG, "unexpected failure", e)
                main.post { result.error("ai_failed", describe(e), null) }
            }
        }
    }

    private class AiFailure(message: String, cause: Throwable? = null) :
        Exception(message, cause)

    /**
     * The real reason behind [e], in one line.
     *
     * `Tasks.await` wraps whatever went wrong in an [ExecutionException], and
     * its message is only the inner one's class name and message run together.
     * ML Kit's own [MlKitException] carries a code that says far more than its
     * message, so it goes in too.
     */
    private fun describe(e: Throwable): String {
        var cause: Throwable = e
        while ((cause is ExecutionException || cause is RuntimeException) &&
            cause.cause != null && cause.cause !== cause
        ) {
            cause = cause.cause!!
        }
        val message = cause.message?.takeIf { it.isNotBlank() } ?: cause.javaClass.simpleName
        return if (cause is MlKitException) "$message (ML Kit error ${cause.errorCode})" else message
    }

    /** Waits for [task], giving up after [minutes] rather than hanging the call forever. */
    private fun <T> waitFor(task: Task<T>, minutes: Long): T =
        Tasks.await(task, minutes, TimeUnit.MINUTES)

    // -------------------------------------------------------------------------
    // Gemini Nano
    // -------------------------------------------------------------------------

    private fun status(engine: String, state: String, reason: String? = null) =
        mapOf("engine" to engine, "state" to state, "reason" to reason)

    private fun nanoState(): Int = try {
        nano.checkStatus().get() ?: FeatureStatus.UNAVAILABLE
    } catch (_: Exception) {
        // No AICore at all — most phones. Not an error, just not here.
        FeatureStatus.UNAVAILABLE
    }

    private fun captionStatus(): Map<String, Any?> = when (nanoState()) {
        FeatureStatus.AVAILABLE -> status("geminiNano", "ready")
        FeatureStatus.DOWNLOADABLE, FeatureStatus.DOWNLOADING ->
            status("geminiNano", "needsDownload")
        else -> status(
            "geminiNano",
            "unavailable",
            "Gemini Nano is not available on this phone.",
        )
    }

    private fun writeCaptions(instructions: String, prompt: String): String {
        when (nanoState()) {
            FeatureStatus.AVAILABLE -> Unit
            FeatureStatus.DOWNLOADABLE -> {
                // Started, not waited for: the model is hundreds of megabytes,
                // and the phrasebook answers now while it arrives.
                nano.download(object : DownloadCallback {})
                throw AiFailure("Gemini Nano is downloading. Try again in a few minutes.")
            }
            FeatureStatus.DOWNLOADING ->
                throw AiFailure("Gemini Nano is still downloading.")
            else -> throw AiFailure("Gemini Nano is not available on this phone.")
        }
        // One text part rather than a system instruction plus a prompt: not
        // every AICore build takes a system prompt, and every one takes text.
        val request = GenerateContentRequest.Builder(
            TextPart("$instructions\n\n$prompt"),
        ).apply {
            temperature = 0.8f
            topK = 40
            candidateCount = 1
            maxOutputTokens = 320
        }.build()
        return try {
            val response = nano.generateContent(request).get()
            response.candidates.firstOrNull()?.text.orEmpty()
        } catch (e: Exception) {
            val cause = e.cause
            throw AiFailure(
                if (cause is GenAiException) {
                    cause.message ?: "Gemini Nano could not answer."
                } else {
                    e.message ?: "Gemini Nano could not answer."
                },
            )
        }
    }

    // -------------------------------------------------------------------------
    // Translation
    // -------------------------------------------------------------------------

    /**
     * ML Kit's code for a store locale, or null for one it cannot write.
     *
     * Traditional Chinese is the one gap that matters: ML Kit has a single
     * Chinese model, and handing a Taiwanese listing Simplified characters
     * would be worse than handing it nothing.
     */
    private fun mlKitLanguage(storeCode: String): String? {
        val tag = when {
            storeCode == "zh-Hant" -> return null
            storeCode == "zh-Hans" -> "zh"
            storeCode.startsWith("nb") -> "no"
            else -> storeCode.substringBefore('-')
        }
        return TranslateLanguage.fromLanguageTag(tag)
    }

    private fun translationStatus(from: String, to: String): Map<String, Any?> {
        val source = mlKitLanguage(from)
        val target = mlKitLanguage(to)
        if (source == null || target == null) {
            return status(
                "mlKit",
                "unavailable",
                "The on-device translator does not write this language.",
            )
        }
        val downloaded = try {
            Tasks.await(
                RemoteModelManager.getInstance()
                    .getDownloadedModels(TranslateRemoteModel::class.java),
            ).map { it.language }.toSet()
        } catch (_: Exception) {
            emptySet()
        }
        val ready = (source == TranslateLanguage.ENGLISH || source in downloaded) &&
            (target == TranslateLanguage.ENGLISH || target in downloaded)
        return status("mlKit", if (ready) "ready" else "needsDownload")
    }

    private fun translate(texts: List<String>, from: String, to: String): List<String> {
        val source = mlKitLanguage(from)
            ?: throw AiFailure("The on-device translator does not write $from.")
        val target = mlKitLanguage(to)
            ?: throw AiFailure("The on-device translator does not write $to.")
        if (source == target) return texts

        val name = Locale.forLanguageTag(target).getDisplayLanguage(Locale.ENGLISH)
            .ifBlank { to }
        Log.i(TAG, "translate ${texts.size} text(s) $from ($source) -> $to ($target)")

        val translator = try {
            Translation.getClient(
                TranslatorOptions.Builder()
                    .setSourceLanguage(source)
                    .setTargetLanguage(target)
                    .build(),
            )
        } catch (e: Throwable) {
            throw AiFailure("The on-device translator would not start: ${describe(e)}", e)
        }
        try {
            // Any network: a language pack is about thirty megabytes, once. The
            // wait is bounded — a download the system has parked forever would
            // otherwise leave the button spinning with no word of why.
            try {
                waitFor(translator.downloadModelIfNeeded(DownloadConditions.Builder().build()), 5)
            } catch (e: TimeoutException) {
                throw AiFailure(
                    "The $name language pack is still downloading. Check the connection and try again.",
                    e,
                )
            } catch (e: Throwable) {
                throw AiFailure("Couldn't download the $name language pack: ${describe(e)}", e)
            }
            return texts.map { text ->
                if (text.isBlank()) {
                    text
                } else {
                    try {
                        waitFor(translator.translate(text), 1)
                    } catch (e: Throwable) {
                        throw AiFailure("Couldn't translate into $name: ${describe(e)}", e)
                    }
                }
            }
        } finally {
            translator.close()
        }
    }

    // -------------------------------------------------------------------------
    // Reading a screenshot
    // -------------------------------------------------------------------------

    private fun readText(image: ByteArray): String {
        val bitmap = BitmapFactory.decodeByteArray(image, 0, image.size) ?: return ""
        val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
        return try {
            val text = Tasks.await(recognizer.process(InputImage.fromBitmap(bitmap, 0)))
            // Top to bottom, the way the screen reads, whatever order the
            // recogniser found the blocks in.
            text.textBlocks
                .sortedBy { it.boundingBox?.top ?: 0 }
                .flatMap { block -> block.lines.map { it.text.trim() } }
                .filter { it.isNotEmpty() }
                .joinToString("\n")
        } catch (_: Exception) {
            ""
        } finally {
            recognizer.close()
            bitmap.recycle()
        }
    }

    fun dispose() {
        worker.shutdown()
    }

    companion object {
        const val CHANNEL = "mockmyapp/ai"

        /** Where failures are logged: `adb logcat -s MockMyAppAI`. */
        private const val TAG = "MockMyAppAI"
    }
}
