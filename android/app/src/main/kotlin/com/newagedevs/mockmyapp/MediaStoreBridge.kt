package com.newagedevs.mockmyapp

import android.Manifest
import android.app.Activity
import android.content.ContentValues
import android.content.Context
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.io.IOException

/**
 * Writes exported artwork, videos and project backups into user-visible
 * storage.
 *
 * On API 29+ everything goes through MediaStore, which needs no runtime
 * permission for content the app itself creates: images land in
 * `Pictures/<folder>` and documents in `Download/<folder>`. On API 28 and below
 * there is no scoped storage, so the same files are written directly to the
 * public directories behind `WRITE_EXTERNAL_STORAGE` (declared in the manifest
 * with `maxSdkVersion="28"`), requesting it on demand.
 *
 * Every method answers with `{displayPath, filePath}`; `filePath` is null on
 * API 29+ because a MediaStore item has no path the app is allowed to read.
 */
class MediaStoreBridge(private val context: Context) : MethodChannel.MethodCallHandler {

    /** Set by [MainActivity] so legacy permission requests have a host. */
    var activity: Activity? = null

    private var pendingCall: (() -> Unit)? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "saveImage" -> handleSave(call, result, image = true)
            "saveVideo" -> handleSave(call, result, image = false, video = true)
            "saveDownload" -> handleSave(call, result, image = false)
            else -> result.notImplemented()
        }
    }

    private fun handleSave(
        call: MethodCall,
        result: MethodChannel.Result,
        image: Boolean,
        video: Boolean = false,
    ) {
        val bytes = call.argument<ByteArray>("bytes")
        val fileName = call.argument<String>("fileName")
        if (bytes == null || fileName.isNullOrBlank()) {
            result.error("bad_arguments", "Missing image data or file name.", null)
            return
        }
        val mimeType = call.argument<String>("mimeType")
            ?: when {
                video -> "video/mp4"
                image -> "image/png"
                else -> "application/octet-stream"
            }
        val folder = call.argument<String>("folder").orEmpty()

        val run = {
            try {
                result.success(write(bytes, fileName, mimeType, folder, image, video))
            } catch (e: Exception) {
                result.error("save_failed", e.message ?: "Could not write the file.", null)
            }
        }

        if (needsLegacyPermission()) {
            requestLegacyPermission(run) {
                result.error(
                    "permission_denied",
                    "Storage access is needed to save files to this device.",
                    null,
                )
            }
        } else {
            run()
        }
    }

    // -------------------------------------------------------------------------
    // Writing
    // -------------------------------------------------------------------------

    private fun write(
        bytes: ByteArray,
        fileName: String,
        mimeType: String,
        folder: String,
        image: Boolean,
        video: Boolean = false,
    ): Map<String, Any?> {
        // A clip goes to Movies, as the gallery apps expect; a picture to
        // Pictures; anything else to Download.
        val baseDir = when {
            video -> Environment.DIRECTORY_MOVIES
            image -> Environment.DIRECTORY_PICTURES
            else -> Environment.DIRECTORY_DOWNLOADS
        }
        val relativePath = if (folder.isBlank()) baseDir else "$baseDir/$folder"

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            writeViaMediaStore(bytes, fileName, mimeType, relativePath, image, video)
        } else {
            writeLegacy(bytes, fileName, mimeType, baseDir, folder)
        }
    }

    private fun writeViaMediaStore(
        bytes: ByteArray,
        fileName: String,
        mimeType: String,
        relativePath: String,
        image: Boolean,
        video: Boolean,
    ): Map<String, Any?> {
        val collection: Uri = when {
            video -> MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            image -> MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            else -> MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        }

        val resolver = context.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
            put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
            put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }

        val uri = resolver.insert(collection, values)
            ?: throw IOException("The system storage provider rejected the file.")

        try {
            resolver.openOutputStream(uri)?.use { it.write(bytes) }
                ?: throw IOException("Could not open the destination for writing.")
        } catch (e: Exception) {
            // Leave nothing half-written behind if the stream failed mid-way.
            runCatching { resolver.delete(uri, null, null) }
            throw e
        }

        // Clearing IS_PENDING is what publishes the item to other apps.
        resolver.update(
            uri,
            ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) },
            null,
            null,
        )

        // MediaStore may de-duplicate the display name (`foo (1).png`); read the
        // committed name back so the confirmation shown to the user is truthful.
        val committedName = resolver.query(
            uri,
            arrayOf(MediaStore.MediaColumns.DISPLAY_NAME),
            null,
            null,
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) cursor.getString(0) else null
        } ?: fileName

        return mapOf(
            "displayPath" to "$relativePath/$committedName",
            "filePath" to null,
            "uri" to uri.toString(),
        )
    }

    private fun writeLegacy(
        bytes: ByteArray,
        fileName: String,
        mimeType: String,
        baseDir: String,
        folder: String,
    ): Map<String, Any?> {
        @Suppress("DEPRECATION")
        val root = Environment.getExternalStoragePublicDirectory(baseDir)
        val dir = if (folder.isBlank()) root else File(root, folder)
        if (!dir.exists() && !dir.mkdirs()) {
            throw IOException("Could not create ${dir.absolutePath}.")
        }

        val file = uniqueFile(dir, fileName)
        FileOutputStream(file).use { it.write(bytes) }

        // Without this the file exists but stays invisible to the gallery and
        // to file managers until the next media scan.
        MediaScannerConnection.scanFile(
            context,
            arrayOf(file.absolutePath),
            arrayOf(mimeType),
            null,
        )

        return mapOf(
            "displayPath" to if (folder.isBlank()) "$baseDir/${file.name}" else "$baseDir/$folder/${file.name}",
            "filePath" to file.absolutePath,
            "uri" to null,
        )
    }

    private fun uniqueFile(dir: File, fileName: String): File {
        val dot = fileName.lastIndexOf('.')
        val stem = if (dot > 0) fileName.substring(0, dot) else fileName
        val ext = if (dot > 0) fileName.substring(dot) else ""
        var candidate = File(dir, fileName)
        var n = 2
        while (candidate.exists()) {
            candidate = File(dir, "$stem ($n)$ext")
            n++
        }
        return candidate
    }

    // -------------------------------------------------------------------------
    // Legacy permission (API <= 28 only)
    // -------------------------------------------------------------------------

    /** True only on API 23..28, where the write permission is both required
     *  and requested at runtime. Below 23 it is granted at install time. */
    private fun needsLegacyPermission(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) return false
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return false
        return !hasLegacyPermission()
    }

    private fun hasLegacyPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        return context.checkSelfPermission(
            Manifest.permission.WRITE_EXTERNAL_STORAGE,
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun requestLegacyPermission(onGranted: () -> Unit, onDenied: () -> Unit) {
        val host = activity
        if (host == null || Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            onDenied()
            return
        }
        pendingCall = { if (hasLegacyPermission()) onGranted() else onDenied() }
        host.requestPermissions(
            arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
            REQUEST_CODE,
        )
    }

    /** Called by [MainActivity]; returns true when the result was ours. */
    fun onRequestPermissionsResult(requestCode: Int): Boolean {
        if (requestCode != REQUEST_CODE) return false
        val callback = pendingCall
        pendingCall = null
        callback?.invoke()
        return true
    }

    companion object {
        const val CHANNEL = "mockmyapp/storage"
        private const val REQUEST_CODE = 0x4D53 // 'MS'
    }
}
